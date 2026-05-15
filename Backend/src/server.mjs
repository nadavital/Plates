import http from 'node:http';
import crypto from 'node:crypto';
import {
  createConfig,
  validateConfig,
  loadTrustedAppStoreRoots,
  PLAN_LIMITS,
  PLAN_PRICING,
  UNIT_ECONOMICS,
  FEATURE_COSTS,
  PRODUCT_DEFINITIONS
} from './config.mjs';
import { createDatabase } from './database.mjs';
import { createAIProvider, normalizeAIProviderName } from './ai-provider.mjs';
import { createMonetizationHelpers } from './monetization.mjs';
import { createAuthHelpers } from './auth.mjs';
import { createAppStoreHelpers } from './appstore.mjs';
import { createRouteHandlers } from './routes.mjs';

const config = createConfig();
validateConfig(config);

const trustedAppStoreRoots = loadTrustedAppStoreRoots(config);
const db = await createDatabase(config);

async function buildAdminUserInspection(userID) {
  const now = isoNow();
  const user = await db.prepare(`
    SELECT id, created_at, updated_at, status
    FROM users
    WHERE id = ?
  `).get(userID);

  const identities = await db.prepare(`
    SELECT provider, provider_user_id, email, display_name, created_at, updated_at
    FROM auth_identities
    WHERE user_id = ?
    ORDER BY created_at ASC
  `).all(userID);

  const sessions = await db.prepare(`
    SELECT id, installation_id, app_account_token, expires_at, created_at, updated_at
    FROM sessions
    WHERE user_id = ?
    ORDER BY updated_at DESC
    LIMIT 10
  `).all(userID);

  const subscription = await db.prepare(`
    SELECT *
    FROM subscriptions
    WHERE user_id = ?
  `).get(userID);

  const subscriptionOverride = await getActiveSubscriptionOverride(userID, now);
  const effectiveSubscription = subscription
    ? resolveEffectiveSubscription(subscription, subscriptionOverride)
    : null;
  const latestQuotaPeriod = await db.prepare(`
    SELECT *
    FROM quota_periods
    WHERE user_id = ?
    ORDER BY period_start DESC
    LIMIT 1
  `).get(userID);

  const recentUsage = await db.prepare(`
    SELECT feature, unit_cost, created_at
    FROM usage_ledger
    WHERE user_id = ?
    ORDER BY created_at DESC
    LIMIT 20
  `).all(userID);

  const recentAIRequests = await db.prepare(`
    SELECT
      feature,
      provider,
      model,
      action,
      outcome,
      latency_ms,
      input_tokens,
      output_tokens,
      total_tokens,
      cached_input_tokens,
      reasoning_tokens,
      provider_cost_estimate,
      provider_usage_json,
      request_format,
      retry_count,
      retry_reason,
      created_at
    FROM ai_requests
    WHERE user_id = ?
    ORDER BY created_at DESC
    LIMIT 20
  `).all(userID);

  const recentTransactions = await db.prepare(`
    SELECT environment, product_id, transaction_id, original_transaction_id, purchase_date, expires_date, revocation_date, signed_date, updated_at
    FROM storekit_transactions
    WHERE user_id = ?
    ORDER BY COALESCE(signed_date, updated_at) DESC
    LIMIT 20
  `).all(userID);

  const recentNotifications = await db.prepare(`
    SELECT notification_uuid, notification_type, subtype, environment, related_transaction_id, related_original_transaction_id, processed_at
    FROM app_store_notifications
    WHERE related_original_transaction_id IN (
      SELECT original_transaction_id
      FROM storekit_transactions
      WHERE user_id = ?
    )
    ORDER BY processed_at DESC
    LIMIT 20
  `).all(userID);

  const recentAdjustments = await db.prepare(`
    SELECT adjustment_type, unit_delta, previous_units_used, new_units_used, reason, created_by, created_at
    FROM admin_adjustments
    WHERE user_id = ?
    ORDER BY created_at DESC
    LIMIT 20
  `).all(userID);

  return {
    user,
    identities,
    sessions,
    subscription,
    subscriptionOverride: subscriptionOverride ?? null,
    effectiveSubscription,
    latestQuotaPeriod,
    quotaStatus: latestQuotaPeriod ? summarizeQuotaPeriod(latestQuotaPeriod) : null,
    usageAnalytics: await buildUsageAnalytics(userID, latestQuotaPeriod),
    recentUsage,
    recentAIRequests,
    recentTransactions,
    recentNotifications,
    recentAdjustments,
    monetizationPolicy: buildMonetizationPolicySummary()
  };
}

async function buildAdminUsageSummary(options = 30) {
  return {
    generatedAt: new Date().toISOString(),
    usageAnalytics: await buildGlobalUsageAnalytics(options),
    monetizationPolicy: buildMonetizationPolicySummary()
  };
}

async function buildAdminUsers(options = {}) {
  const now = isoNow();
  const limit = normalizeAdminUsersLimit(options.limit);
  const offset = normalizeAdminUsersOffset(options.offset);
  const emailFilter = normalizeSearchText(options.email);
  const queryFilter = normalizeSearchText(options.query);
  const planFilter = normalizeSearchText(options.plan);
  const statusFilter = normalizeSearchText(options.status);
  const usageWindowStart = new Date(Date.now() - (30 * 24 * 60 * 60 * 1000)).toISOString();

  const rows = await db.prepare(`
    /* admin_user_list */
    SELECT
      users.id AS user_id,
      users.created_at,
      users.updated_at,
      users.status AS user_status,
      auth_identities.provider AS identity_provider,
      auth_identities.email,
      auth_identities.display_name,
      auth_identities.updated_at AS identity_updated_at,
      subscriptions.plan AS subscription_plan,
      subscriptions.status AS subscription_status,
      subscriptions.source AS subscription_source,
      subscriptions.renews_at,
      subscriptions.expires_at,
      session_summary.last_session_at,
      usage_summary.request_count_30d,
      usage_summary.units_used_30d,
      usage_summary.last_used_at
    FROM users
    LEFT JOIN auth_identities ON auth_identities.id = (
      SELECT id
      FROM auth_identities
      WHERE user_id = users.id
      ORDER BY created_at ASC
      LIMIT 1
    )
    LEFT JOIN subscriptions ON subscriptions.user_id = users.id
    LEFT JOIN (
      SELECT user_id, MAX(updated_at) AS last_session_at
      FROM sessions
      GROUP BY user_id
    ) AS session_summary ON session_summary.user_id = users.id
    LEFT JOIN (
      SELECT
        user_id,
        COUNT(*) AS request_count_30d,
        COALESCE(SUM(unit_cost), 0) AS units_used_30d,
        MAX(created_at) AS last_used_at
      FROM usage_ledger
      WHERE created_at >= ?
      GROUP BY user_id
    ) AS usage_summary ON usage_summary.user_id = users.id
    ORDER BY COALESCE(session_summary.last_session_at, users.updated_at, users.created_at) DESC, users.created_at DESC
    LIMIT 5000
  `).all(usageWindowStart);

  const enrichedRows = [];
  const seenUserIDs = new Set();
  for (const row of rows) {
    if (seenUserIDs.has(row.user_id)) {
      continue;
    }
    seenUserIDs.add(row.user_id);

    const rawSubscription = fallbackAdminSubscription(row);
    const subscriptionOverride = await getActiveSubscriptionOverride(row.user_id, now);
    const effectiveSubscription = resolveEffectiveSubscription(rawSubscription, subscriptionOverride);
    const user = adminUserRowToResponse(row, rawSubscription, effectiveSubscription);

    if (emailFilter && !String(user.email ?? '').toLowerCase().includes(emailFilter)) {
      continue;
    }
    if (queryFilter && !adminUserMatchesQuery(user, queryFilter)) {
      continue;
    }
    if (planFilter && String(user.subscription.plan ?? '').toLowerCase() !== planFilter) {
      continue;
    }
    if (statusFilter && String(user.userStatus ?? '').toLowerCase() !== statusFilter) {
      continue;
    }

    enrichedRows.push(user);
  }

  return {
    generatedAt: now,
    filters: {
      query: options.query ?? null,
      email: options.email ?? null,
      plan: options.plan ?? null,
      status: options.status ?? null
    },
    pagination: {
      limit,
      offset,
      totalMatching: enrichedRows.length,
      hasMore: offset + limit < enrichedRows.length
    },
    users: enrichedRows.slice(offset, offset + limit)
  };
}

function adminUserRowToResponse(row, rawSubscription, effectiveSubscription) {
  return {
    userID: row.user_id,
    userStatus: row.user_status,
    email: row.email ?? null,
    displayName: row.display_name ?? null,
    identityProvider: row.identity_provider ?? null,
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
    identityUpdatedAt: row.identity_updated_at ?? null,
    lastSessionAt: row.last_session_at ?? null,
    lastUsedAt: row.last_used_at ?? null,
    subscription: {
      plan: effectiveSubscription?.plan ?? 'free',
      status: effectiveSubscription?.status ?? 'unknown',
      source: effectiveSubscription?.source ?? 'system',
      renewsAt: effectiveSubscription?.renews_at ?? null,
      expiresAt: effectiveSubscription?.expires_at ?? null,
      rawPlan: rawSubscription.plan,
      rawStatus: rawSubscription.status,
      rawSource: rawSubscription.source
    },
    usageLast30Days: {
      requestCount: row.request_count_30d ?? 0,
      unitsUsed: row.units_used_30d ?? 0
    }
  };
}

function fallbackAdminSubscription(row) {
  return {
    user_id: row.user_id,
    plan: row.subscription_plan ?? 'free',
    status: row.subscription_status ?? 'unknown',
    source: row.subscription_source ?? 'system',
    source_transaction_id: null,
    renews_at: row.renews_at ?? null,
    expires_at: row.expires_at ?? null
  };
}

function adminUserMatchesQuery(user, query) {
  return [
    user.userID,
    user.email,
    user.displayName,
    user.identityProvider,
    user.subscription.plan,
    user.subscription.source
  ].some((value) => String(value ?? '').toLowerCase().includes(query));
}

function normalizeSearchText(value) {
  const normalized = typeof value === 'string' ? value.trim().toLowerCase() : '';
  return normalized.length > 0 ? normalized : null;
}

function normalizeAdminUsersLimit(limit) {
  if (!Number.isFinite(limit)) {
    return 25;
  }
  return Math.min(Math.max(Math.round(limit), 1), 100);
}

function normalizeAdminUsersOffset(offset) {
  if (!Number.isFinite(offset)) {
    return 0;
  }
  return Math.max(Math.round(offset), 0);
}

function buildSessionSnapshot(session, user, now, accessTokenOverride = session.accessToken) {
  return {
    userID: user.id,
    identityProvider: 'apple',
    email: user.email ?? null,
    displayName: user.displayName ?? null,
    accessToken: accessTokenOverride,
    refreshToken: session.refreshToken ?? null,
    expiresAt: session.expires_at ?? session.expiresAt ?? null,
    lastAuthenticatedAt: now
  };
}

async function readJson(req, options = {}) {
  const requestedMaxBytes = Number.isFinite(options.maxBytes)
    ? options.maxBytes
    : config.jsonBodyMaxRequestBytes;
  const maxBytes = Number.isFinite(requestedMaxBytes) ? Math.max(requestedMaxBytes, 0) : null;
  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (maxBytes != null && totalBytes > maxBytes) {
      throw new HttpError(413, {
        error: 'request_too_large',
        message: 'Request body is too large.'
      });
    }
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw) {
    return {};
  }

  try {
    return JSON.parse(raw);
  } catch {
    throw new HttpError(400, {
      error: 'invalid_json',
      message: 'Request body must be valid JSON.'
    });
  }
}

function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json'
  });
  res.end(JSON.stringify(body));
}

function parseJWT(token) {
  const parts = String(token ?? '').split('.');
  if (parts.length !== 3) {
    throw new HttpError(400, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token must be a three-part JWT.'
    });
  }

  let header;
  let payload;

  try {
    header = JSON.parse(base64URLDecode(parts[0]).toString('utf8'));
    payload = JSON.parse(base64URLDecode(parts[1]).toString('utf8'));
  } catch {
    throw new HttpError(400, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token contains malformed JSON.'
    });
  }

  return {
    parts,
    header,
    payload
  };
}

function validateAppleClaims(claims, body) {
  if (claims.iss !== config.appleIssuer) {
    throw new HttpError(401, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token issuer is invalid.'
    });
  }

  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  const hasExpectedAudience = audiences.some((audience) => config.appleExpectedAudiences.includes(audience));
  if (!hasExpectedAudience) {
    throw new HttpError(401, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token audience is invalid.'
    });
  }

  if (claims.sub !== body.appleUserID) {
    throw new HttpError(401, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token subject does not match the Apple user identifier.'
    });
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(claims.exp) || claims.exp <= nowSeconds) {
    throw new HttpError(401, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token has expired.'
    });
  }

  if (claims.iat && Number.isFinite(claims.iat) && claims.iat > (nowSeconds + 300)) {
    throw new HttpError(401, {
      error: 'invalid_apple_identity_token',
      message: 'Apple identity token issue time is in the future.'
    });
  }

  if (body.rawNonce) {
    const expectedNonce = sha256Hex(body.rawNonce);
    if (claims.nonce !== expectedNonce) {
      throw new HttpError(401, {
        error: 'invalid_apple_identity_token',
        message: 'Apple identity token nonce does not match the original sign-in request.'
      });
    }
  }

  if (claims.nonce && !body.rawNonce) {
    throw new HttpError(400, {
      error: 'missing_field',
      message: 'Missing required field: rawNonce'
    });
  }
}

function assertRequired(body, fields) {
  for (const field of fields) {
    if (!body[field]) {
      throw new HttpError(400, {
        error: 'missing_field',
        message: `Missing required field: ${field}`
      });
    }
  }
}

function looksLikeJWT(value) {
  return typeof value === 'string' && value.split('.').length === 3;
}

function base64URLDecode(value) {
  const normalized = value
    .replaceAll('-', '+')
    .replaceAll('_', '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=');

  return Buffer.from(normalized, 'base64');
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function normalizeNumericIdentifier(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Number.isSafeInteger(value) ? String(Math.trunc(value)) : null;
  }

  if (typeof value === 'bigint') {
    return value.toString();
  }

  if (typeof value === 'string') {
    const trimmedValue = value.trim();
    if (/^\d+$/.test(trimmedValue)) {
      return trimmedValue;
    }
  }

  return null;
}

function normalizeMillisecondsTimestamp(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function normalizeDateString(value) {
  if (!value) {
    return null;
  }

  const timestampValue = normalizeMillisecondsTimestamp(value);
  if (timestampValue != null) {
    return new Date(timestampValue).toISOString();
  }

  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    return null;
  }

  return new Date(parsed).toISOString();
}

function createID(prefix) {
  return `${prefix}_${crypto.randomUUID().replaceAll('-', '')}`;
}

function planRank(plan) {
  switch (plan) {
    case 'free':
      return 0;
    case 'pro':
      return 1;
    case 'developer':
      return 2;
    default:
      return -1;
  }
}

function isoNow() {
  return new Date().toISOString();
}

class HttpError extends Error {
  constructor(statusCode, payload) {
    super(payload?.message ?? 'HTTP error');
    this.statusCode = statusCode;
    this.payload = payload;
  }
}

function resolveAIProvider(providerOverride = null) {
  return createAIProvider(
    {
      ...config,
      aiProvider: normalizeAIProviderName(providerOverride ?? config.aiProvider)
    },
    HttpError
  );
}

const aiProvider = resolveAIProvider();

let authHelpers;
let appStoreHelpers;

authHelpers = createAuthHelpers({
  db,
  config,
  aiProvider,
  HttpError,
  createID,
  hashToken,
  looksLikeJWT,
  parseJWT,
  validateAppleClaims,
  base64URLDecode,
  ensureSubscription: (...args) => authHelpers.ensureSubscription(...args),
  findUserIDForOriginalTransaction: (...args) => appStoreHelpers.findUserIDForOriginalTransaction(...args)
});

const {
  verifyAppleIdentity,
  findOrCreateUserFromApple,
  createSession,
  rotateSessionTokens,
  requireSession,
  ensureSubscription,
  requireAdmin,
  resolveAdminLookup,
  resolveAdminUserID,
  normalizeGrantEmail,
  applyPendingSubscriptionGrantForEmail
} = authHelpers;

appStoreHelpers = createAppStoreHelpers({
  db,
  config,
  trustedAppStoreRoots,
  HttpError,
  createID,
  isoNow,
  PRODUCT_DEFINITIONS,
  normalizeNumericIdentifier,
  normalizeMillisecondsTimestamp,
  normalizeDateString,
  base64URLDecode,
  ensureSubscription: (...args) => authHelpers.ensureSubscription(...args),
  planRank
});

const {
  applyStoreKitSubscriptionState,
  applyNotificationLifecycleUpdate,
  reconcileUserSubscriptionFromLedger,
  updateSubscriptionRecord,
  normalizeStoreKitEntitlement,
  persistAppStoreNotification,
  findUserIDForStoreKitTransaction,
  findUserIDForOriginalTransaction,
  storeKitTransactionRowToEntitlement,
  verifyAndDecodeStoreKitTransaction,
  persistStoreKitTransactions,
  verifyAndDecodeAppStoreNotification,
  verifyAndDecodeAppStoreRenewalInfo
} = appStoreHelpers;

const {
  ensureQuotaPeriod,
  getActiveSubscriptionOverride,
  getEffectiveSubscription,
  resolveEffectiveSubscription,
  ensureQuotaAvailable,
  reserveQuotaUsage,
  releaseReservedQuotaUsage,
  recordUsage,
  recordAIRequest,
  buildBillingPayload,
  buildQuotaSnapshot,
  effectiveQuotaLimit,
  buildMonetizationPolicySummary,
  summarizeQuotaPeriod,
  buildUsageAnalytics,
  buildGlobalUsageAnalytics,
  normalizeAdminReason,
  applyQuotaAdjustment,
  resetQuotaUsage,
  recordAdminAdjustment
} = createMonetizationHelpers({
  db,
  config,
  HttpError,
  createID,
  isoNow,
  ensureSubscription,
  PLAN_LIMITS,
  PLAN_PRICING,
  UNIT_ECONOMICS,
  FEATURE_COSTS,
  PRODUCT_DEFINITIONS
});

const { routeRequest, handleServerError } = createRouteHandlers({
  db,
  config,
  aiProvider,
  resolveAIProvider,
  HttpError,
  readJson,
  sendJson,
  buildSessionSnapshot,
  buildAdminUserInspection,
  buildAdminUsers,
  buildAdminUsageSummary,
  assertRequired,
  hashToken,
  isoNow,
  verifyAppleIdentity,
  findOrCreateUserFromApple,
  createSession,
  rotateSessionTokens,
  requireSession,
  ensureSubscription,
  requireAdmin,
  resolveAdminLookup,
  resolveAdminUserID,
  normalizeGrantEmail,
  applyPendingSubscriptionGrantForEmail,
  ensureQuotaPeriod,
  getActiveSubscriptionOverride,
  getEffectiveSubscription,
  ensureQuotaAvailable,
  reserveQuotaUsage,
  releaseReservedQuotaUsage,
  recordUsage,
  recordAIRequest,
  buildBillingPayload,
  buildQuotaSnapshot,
  buildUsageAnalytics,
  normalizeAdminReason,
  applyQuotaAdjustment,
  resetQuotaUsage,
  recordAdminAdjustment,
  applyStoreKitSubscriptionState,
  applyNotificationLifecycleUpdate,
  reconcileUserSubscriptionFromLedger,
  normalizeStoreKitEntitlement,
  persistAppStoreNotification,
  findUserIDForStoreKitTransaction,
  findUserIDForOriginalTransaction,
  verifyAndDecodeStoreKitTransaction,
  persistStoreKitTransactions,
  verifyAndDecodeAppStoreNotification,
  verifyAndDecodeAppStoreRenewalInfo,
  FEATURE_COSTS
});

const server = http.createServer(async (req, res) => {
  try {
    await routeRequest(req, res);
  } catch (error) {
    handleServerError(res, error);
  }
});

server.listen(config.port, config.host, () => {
  console.log(`Trai backend listening on http://${config.host}:${config.port}`);
});
