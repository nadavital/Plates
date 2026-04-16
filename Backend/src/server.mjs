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

async function buildAdminUsageSummary(days = 30) {
  return {
    generatedAt: new Date().toISOString(),
    usageAnalytics: await buildGlobalUsageAnalytics(days),
    monetizationPolicy: buildMonetizationPolicySummary()
  };
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
  const maxBytes = Number.isFinite(options.maxBytes) ? Math.max(options.maxBytes, 0) : null;
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
  resolveAdminUserID
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
  resetQuotaUsage
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
  ensureQuotaPeriod,
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
