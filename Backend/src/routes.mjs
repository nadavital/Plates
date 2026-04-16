import { createHash } from 'node:crypto';
import {
  canonicalMessagesFromTraiRequest,
  normalizeIncomingTraiRequest,
  traiEventToGeminiSSEChunk,
  traiResponseToGeminiJSON
} from './trai-ai-contract.mjs';

export function createRouteHandlers({
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
}) {
  const activeAIRequestsByUser = new Map();
  const allowedAdminSubscriptionSources = new Set(['system', 'adminGrant', 'promo', 'developer']);
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  function normalizeAIProviderOverride(value) {
    const rawValue = Array.isArray(value) ? value[0] : value;
    if (typeof rawValue !== 'string') {
      return null;
    }

    const normalizedValue = rawValue.trim().toLowerCase();
    if (normalizedValue === 'gemini' || normalizedValue === 'openai') {
      return normalizedValue;
    }

    return null;
  }

  function aiProviderForRequest(req) {
    if (config.environment === 'production') {
      return aiProvider;
    }

    const providerOverride = normalizeAIProviderOverride(req.headers['x-trai-ai-provider-override']);
    return providerOverride ? resolveAIProvider(providerOverride) : aiProvider;
  }

  async function routeRequest(req, res) {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, {
        ok: true,
        environment: config.environment,
        aiProvider: aiProvider.name,
        aiProviderModel: aiProvider.model,
        aiProviderCapabilities: aiProvider.capabilities,
        hasProviderKey: aiProvider.isConfigured(),
        hasGeminiKey: Boolean(config.geminiApiKey),
        hasOpenAIKey: Boolean(config.openAIApiKey),
        allowDevAppleBypass: config.allowDevAppleBypass
      });
    }

    if (req.method === 'POST' && url.pathname === '/v1/auth/apple/exchange') {
      return handleAppleExchange(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/auth/refresh') {
      return handleRefresh(req, res);
    }

    if (req.method === 'GET' && url.pathname === '/v1/account/bootstrap') {
      return handleBootstrap(req, res);
    }

    if (req.method === 'GET' && url.pathname === '/v1/billing/status') {
      return handleBillingStatus(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/billing/sync-storekit') {
      return handleStoreKitSync(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/app-store/notifications') {
      return handleAppStoreNotification(req, res);
    }

    if (req.method === 'GET' && url.pathname === '/v1/admin/user-inspect') {
      return handleAdminUserInspect(req, res, url);
    }

    if (req.method === 'GET' && url.pathname === '/v1/admin/usage-summary') {
      return handleAdminUsageSummary(req, res, url);
    }

    if (req.method === 'POST' && url.pathname === '/v1/admin/reconcile-subscription') {
      return handleAdminReconcileSubscription(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/admin/subscription-override') {
      return handleAdminSubscriptionOverride(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/admin/quota-adjustment') {
      return handleAdminQuotaAdjustment(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/admin/quota-reset') {
      return handleAdminQuotaReset(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/v1/ai/generate') {
      return handleAIProxy(req, res, url, { streaming: false });
    }

    if (req.method === 'POST' && url.pathname === '/v1/ai/stream') {
      return handleAIProxy(req, res, url, { streaming: true });
    }

    sendJson(res, 404, { error: 'not_found' });
  }

  function handleServerError(res, error) {
    if (error instanceof HttpError) {
      sendJson(res, error.statusCode, error.payload);
      return;
    }

    console.error(error);
    sendJson(res, 500, {
      error: 'internal_server_error',
      message: 'Unexpected server error.'
    });
  }

  function normalizeUUIDString(value) {
    if (typeof value !== 'string') {
      return null;
    }

    const normalizedValue = value.trim().toLowerCase();
    return uuidPattern.test(normalizedValue) ? normalizedValue : null;
  }

  function deriveStoreKitAppAccountToken(appAccountToken) {
    const normalizedSource = typeof appAccountToken === 'string'
      ? appAccountToken.trim()
      : '';
    if (!normalizedSource) {
      return null;
    }

    const directUUID = normalizeUUIDString(normalizedSource);
    if (directUUID) {
      return directUUID;
    }

    const digest = createHash('sha256')
      .update(`trai.storekit.appAccountToken.v1:${normalizedSource}`)
      .digest();
    const bytes = Array.from(digest.subarray(0, 16));
    if (bytes.length !== 16) {
      return null;
    }

    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return [
      bytes.slice(0, 4).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
      bytes.slice(4, 6).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
      bytes.slice(6, 8).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
      bytes.slice(8, 10).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
      bytes.slice(10, 16).map((byte) => byte.toString(16).padStart(2, '0')).join('')
    ].join('-');
  }

  function validateStoreKitAppAccountAssociation(auth, entitlementsWithMatchedUsers) {
    const acceptedTokens = new Set();
    const derivedToken = deriveStoreKitAppAccountToken(auth.session.app_account_token);
    if (derivedToken) {
      acceptedTokens.add(derivedToken);
    }

    const legacyInstallationToken = normalizeUUIDString(auth.session.installation_id);
    if (legacyInstallationToken) {
      acceptedTokens.add(legacyInstallationToken);
    }

    if (acceptedTokens.size === 0) {
      return;
    }

    const mismatchedEntitlement = entitlementsWithMatchedUsers.find(({ entitlement, matchedUserID }) =>
      matchedUserID !== auth.user.id
      && entitlement?.appAccountToken
      && !acceptedTokens.has(entitlement.appAccountToken)
    );

    if (mismatchedEntitlement) {
      throw new HttpError(409, {
        error: 'subscription_owner_conflict',
        message: 'This App Store subscription is linked to a different Trai account.'
      });
    }
  }

  async function handleAppleExchange(req, res) {
    const body = await readJson(req);
    assertRequired(body, [
      'installationID',
      'appAccountToken',
      'identityToken',
      'authorizationCode',
      'appleUserID'
    ]);

    const verification = await verifyAppleIdentity(body);
    const normalizedBody = {
      ...body,
      appleUserID: verification.appleUserID,
      email: verification.email ?? body.email ?? null
    };

    if (body.email && verification.email && body.email !== verification.email) {
      throw new HttpError(401, {
        error: 'invalid_apple_identity_token',
        message: 'Apple email claim does not match the provided account email.'
      });
    }

    const now = isoNow();
    const user = await findOrCreateUserFromApple(normalizedBody, now);
    const session = await createSession(user.id, body.installationID, body.appAccountToken, now);
    const billing = await buildBillingPayload(user.id, body.installationID, body.appAccountToken, now);

    sendJson(res, 200, {
      session: buildSessionSnapshot(session, user, now),
      billing
    });
  }

  async function handleRefresh(req, res) {
    const body = await readJson(req);
    assertRequired(body, ['refreshToken', 'appAccountToken']);

    const refreshTokenHash = hashToken(body.refreshToken);
    const row = await db.prepare(`
      SELECT
        sessions.id,
        sessions.user_id,
        sessions.installation_id,
        sessions.app_account_token,
        sessions.refresh_token_hash,
        sessions.expires_at,
        users.status
      FROM sessions
      JOIN users ON users.id = sessions.user_id
      WHERE sessions.refresh_token_hash = ?
    `).get(refreshTokenHash);

    if (!row || row.app_account_token !== body.appAccountToken) {
      throw new HttpError(401, {
        error: 'unauthorized',
        message: 'Refresh token not found.'
      });
    }

    if (row.expires_at && Date.parse(row.expires_at) < Date.now()) {
      throw new HttpError(401, {
        error: 'session_expired',
        message: 'Session has expired.'
      });
    }

    const now = isoNow();
    const tokens = await rotateSessionTokens(row.id, now);
    const identity = await db.prepare(`
      SELECT email, display_name
      FROM auth_identities
      WHERE user_id = ?
      ORDER BY created_at ASC
      LIMIT 1
    `).get(row.user_id);

    const user = {
      id: row.user_id,
      status: row.status,
      email: identity?.email ?? null,
      displayName: identity?.display_name ?? null
    };

    const session = {
      ...row,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expires_at: tokens.expiresAt
    };

    const billing = await buildBillingPayload(row.user_id, row.installation_id ?? 'unknown-installation', row.app_account_token, now);
    sendJson(res, 200, {
      session: buildSessionSnapshot(session, user, now),
      billing
    });
  }

  async function handleBootstrap(req, res) {
    const auth = await requireSession(req);
    const now = isoNow();
    const billing = await buildBillingPayload(
      auth.user.id,
      auth.session.installation_id ?? 'unknown-installation',
      auth.session.app_account_token,
      now
    );

    sendJson(res, 200, {
      session: buildSessionSnapshot(auth.session, auth.user, now, auth.accessToken),
      billing
    });
  }

  async function handleBillingStatus(req, res) {
    const auth = await requireSession(req);
    const billing = await buildBillingPayload(
      auth.user.id,
      auth.session.installation_id ?? 'unknown-installation',
      auth.session.app_account_token,
      isoNow()
    );
    sendJson(res, 200, billing);
  }

  async function handleAdminUserInspect(req, res, url) {
    requireAdmin(req);

    const lookup = resolveAdminLookup({
      userID: url.searchParams.get('userID'),
      email: url.searchParams.get('email'),
      appAccountToken: url.searchParams.get('appAccountToken'),
      originalTransactionId: url.searchParams.get('originalTransactionId')
    });

    const userID = await resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    sendJson(res, 200, await buildAdminUserInspection(userID));
  }

  async function handleAdminUsageSummary(req, res, url) {
    requireAdmin(req);

    const requestedDays = Number.parseInt(url.searchParams.get('days') ?? '30', 10);
    sendJson(res, 200, await buildAdminUsageSummary(requestedDays));
  }

  async function handleAdminReconcileSubscription(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      email: body.email,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = await resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    const summary = await reconcileUserSubscriptionFromLedger(userID, isoNow());
    sendJson(res, 200, summary);
  }

  async function handleAdminSubscriptionOverride(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      email: body.email,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = await resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    const plan = String(body.plan ?? '').trim();
    const allowedPlans = new Set(['free', 'pro', 'developer']);
    if (!allowedPlans.has(plan)) {
      throw new HttpError(400, {
        error: 'invalid_plan',
        message: 'plan must be one of: free, pro, developer.'
      });
    }

    const status = String(body.status ?? 'active').trim();
    const allowedStatuses = new Set(['active', 'trial', 'gracePeriod', 'billingRetry', 'expired', 'refunded', 'revoked']);
    if (!allowedStatuses.has(status)) {
      throw new HttpError(400, {
        error: 'invalid_status',
        message: 'status is not recognized.'
      });
    }

    const source = normalizeAdminSubscriptionSource(body.source, plan);
    if (!allowedAdminSubscriptionSources.has(source)) {
      throw new HttpError(400, {
        error: 'invalid_source',
        message: 'source must be one of: system, adminGrant, promo, developer.'
      });
    }

    const now = isoNow();
    const currentSubscription = await ensureSubscription(userID, now);
    const reason = normalizeAdminReason(body.reason) ?? 'manual subscription override';

    await db.prepare(`
      UPDATE subscriptions
      SET plan = ?, status = ?, source = ?, source_transaction_id = ?, renews_at = ?, expires_at = ?, updated_at = ?
      WHERE user_id = ?
    `).run(
      plan,
      status,
      source,
      null,
      body.renewsAt ?? currentSubscription.renews_at ?? null,
      body.expiresAt ?? currentSubscription.expires_at ?? null,
      now,
      userID
    );

    const updatedSubscription = await ensureSubscription(userID, now);
    const quotaPeriod = await ensureQuotaPeriod(userID, updatedSubscription.plan, now);

    await db.prepare(`
      INSERT INTO admin_adjustments (
        id, user_id, quota_period_id, adjustment_type, unit_delta, previous_units_used, new_units_used, reason, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      `adm_${Date.now()}_${Math.random().toString(16).slice(2, 10)}`,
      userID,
      quotaPeriod?.id ?? null,
      'subscription_override',
      0,
      quotaPeriod?.units_used ?? null,
      quotaPeriod?.units_used ?? null,
      `plan ${currentSubscription.plan}/${currentSubscription.status}/${currentSubscription.source ?? 'system'} -> ${updatedSubscription.plan}/${updatedSubscription.status}/${updatedSubscription.source ?? source}; ${reason}`,
      body.createdBy ?? 'admin',
      now
    );

    sendJson(res, 200, {
      userID,
      overriddenAt: now,
      subscription: updatedSubscription,
      quotaSnapshot: await buildQuotaSnapshot(quotaPeriod),
      analytics: await buildUsageAnalytics(userID, quotaPeriod)
    });
  }

  function normalizeAdminSubscriptionSource(value, plan) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }

    if (plan === 'free') {
      return 'system';
    }

    if (plan === 'developer') {
      return 'developer';
    }

    return 'adminGrant';
  }

  async function handleAdminQuotaAdjustment(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      email: body.email,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = await resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    const unitDelta = Number.parseInt(String(body.unitDelta ?? ''), 10);
    if (!Number.isFinite(unitDelta) || unitDelta === 0) {
      throw new HttpError(400, {
        error: 'invalid_adjustment',
        message: 'unitDelta must be a non-zero integer.'
      });
    }

    const now = isoNow();
    const subscription = await ensureSubscription(userID, now);
    const quotaPeriod = await ensureQuotaPeriod(userID, subscription.plan, now);
    const reason = normalizeAdminReason(body.reason);

    const updatedQuotaPeriod = await applyQuotaAdjustment({
      userID,
      quotaPeriod,
      unitDelta,
      reason,
      createdBy: body.createdBy
    }, now);

    sendJson(res, 200, {
      userID,
      adjustedAt: now,
      quotaSnapshot: await buildQuotaSnapshot(updatedQuotaPeriod),
      analytics: await buildUsageAnalytics(userID, updatedQuotaPeriod)
    });
  }

  async function handleAdminQuotaReset(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      email: body.email,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = await resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    const resetUsedUnitsTo = Number.parseInt(String(body.resetUsedUnitsTo ?? '0'), 10);
    if (!Number.isFinite(resetUsedUnitsTo) || resetUsedUnitsTo < 0) {
      throw new HttpError(400, {
        error: 'invalid_adjustment',
        message: 'resetUsedUnitsTo must be a non-negative integer.'
      });
    }

    const now = isoNow();
    const subscription = await ensureSubscription(userID, now);
    const quotaPeriod = await ensureQuotaPeriod(userID, subscription.plan, now);
    const reason = normalizeAdminReason(body.reason);

    const updatedQuotaPeriod = await resetQuotaUsage({
      userID,
      quotaPeriod,
      resetUsedUnitsTo,
      reason,
      createdBy: body.createdBy
    }, now);

    sendJson(res, 200, {
      userID,
      resetAt: now,
      quotaSnapshot: await buildQuotaSnapshot(updatedQuotaPeriod),
      analytics: await buildUsageAnalytics(userID, updatedQuotaPeriod)
    });
  }

  async function handleStoreKitSync(req, res) {
    const auth = await requireSession(req);
    const body = await readJson(req);
    const signedTransactions = Array.isArray(body.signedTransactions) ? body.signedTransactions : [];
    const entitlements = Array.isArray(body.entitlements) ? body.entitlements : [];
    const now = isoNow();

    if (signedTransactions.length == 0 && entitlements.length > 0) {
      const allowUnsignedLocalSync = config.environment === 'localDevelopment';
      if (!allowUnsignedLocalSync) {
        throw new HttpError(400, {
          error: 'signed_transactions_required',
          message: 'Signed StoreKit transactions are required for subscription sync.'
        });
      }
    }

    const normalizedEntitlements = signedTransactions.length > 0
      ? signedTransactions.map((signedTransaction) => verifyAndDecodeStoreKitTransaction(signedTransaction))
      : entitlements
          .map(normalizeStoreKitEntitlement)
          .filter(Boolean);

    const matchedUserIDCandidates = await Promise.all(
      normalizedEntitlements.map(async (entitlement) => {
          if (!entitlement) {
            return null;
          }

          const originalTransactionOwner = await findUserIDForOriginalTransaction(entitlement.originalTransactionID);
          if (originalTransactionOwner) {
            return originalTransactionOwner;
          }

          return await findUserIDForStoreKitTransaction(entitlement);
        })
    );

    validateStoreKitAppAccountAssociation(
      auth,
      normalizedEntitlements.map((entitlement, index) => ({
        entitlement,
        matchedUserID: matchedUserIDCandidates[index] ?? null
      }))
    );

    const matchedUserIDs = new Set(matchedUserIDCandidates.filter(Boolean));

    if (matchedUserIDs.size > 1) {
      throw new HttpError(409, {
        error: 'subscription_owner_conflict',
        message: 'These StoreKit transactions are already linked to multiple Trai accounts.'
      });
    }

    const matchedUserID = matchedUserIDs.values().next().value ?? null;
    if (matchedUserID && matchedUserID !== auth.user.id) {
      throw new HttpError(409, {
        error: 'subscription_owner_conflict',
        message: 'This App Store subscription is already linked to a different Trai account.'
      });
    }

    await applyStoreKitSubscriptionState(auth.user.id, normalizedEntitlements, now);
    await persistStoreKitTransactions(auth.user.id, normalizedEntitlements, signedTransactions, now);

    const billing = await buildBillingPayload(
      auth.user.id,
      auth.session.installation_id ?? 'unknown-installation',
      auth.session.app_account_token,
      now
    );

    sendJson(res, 200, billing);
  }

  async function handleAppStoreNotification(req, res) {
    const body = await readJson(req);
    assertRequired(body, ['signedPayload']);

    const notification = verifyAndDecodeAppStoreNotification(body.signedPayload);
    const signedTransactionInfo = notification.data?.signedTransactionInfo ?? null;
    const signedRenewalInfo = notification.data?.signedRenewalInfo ?? null;
    const transaction = signedTransactionInfo ? verifyAndDecodeStoreKitTransaction(signedTransactionInfo) : null;
    const renewalInfo = signedRenewalInfo ? verifyAndDecodeAppStoreRenewalInfo(signedRenewalInfo) : null;
    const now = isoNow();

    const userID = transaction
      ? await findUserIDForStoreKitTransaction(transaction)
      : renewalInfo
        ? await findUserIDForOriginalTransaction(renewalInfo.originalTransactionId)
        : null;

    if (userID) {
      await applyNotificationLifecycleUpdate(userID, {
        notification,
        transaction,
        renewalInfo
      }, now);

      if (transaction) {
        await persistStoreKitTransactions(userID, [transaction], [signedTransactionInfo], now);
      }
    }

    await persistAppStoreNotification(notification, body.signedPayload, transaction, renewalInfo, now);
    sendJson(res, 200, {
      ok: true,
      matchedUser: Boolean(userID)
    });
  }

  async function handleAIProxy(req, res, url, { streaming }) {
    const auth = await requireSession(req);
    const selectedAIProvider = aiProviderForRequest(req);
    const action = streaming ? 'stream' : 'generate';
    const requestBody = await readJson(req, {
      maxBytes: config.aiProxyMaxRequestBytes
    });
    sanitizeIncomingTraiRequestBody(requestBody);
    const traiRequest = normalizeIncomingTraiRequest(requestBody);
    const feature = normalizeAIProxyFeature(req.headers['x-trai-ai-feature'], traiRequest);

    const subscription = await ensureSubscription(auth.user.id, isoNow());
    ensureEntitled(subscription);
    const unitCost = FEATURE_COSTS[feature] ?? FEATURE_COSTS.coachChat;
    await enforceAIProxyBurstLimits(auth.user.id, subscription.plan, unitCost);
    const releaseConcurrencySlot = reserveAIConcurrencySlot(auth.user.id);

    const quotaPeriod = await ensureQuotaPeriod(auth.user.id, subscription.plan, isoNow());
    const reservedQuotaPeriod = await reserveQuotaUsage(quotaPeriod, unitCost);

    const startedAt = Date.now();
    let reservationReleased = false;
    let responseStarted = false;
    let deliveryCompleted = false;
    let providerUsageMetadata = null;
    let retryCount = 0;
    let retryReason = null;

    try {
      const execution = await executeTraiRequestWithRetries(
        selectedAIProvider,
        traiRequest,
        { streaming, feature }
      );
      const providerResult = execution.providerResult;
      retryCount = execution.retryCount;
      retryReason = execution.retryReason;
      providerUsageMetadata = providerResult.type === 'stream'
        ? providerResult.getUsageMetadata?.() ?? null
        : providerResult.usageMetadata ?? null;

      if (streaming) {
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive'
        });
        responseStarted = true;

        for await (const event of providerResult.stream) {
          await writeResponseChunk(res, Buffer.from(traiEventToGeminiSSEChunk(event), 'utf8'));
        }
        await writeResponseChunk(res, Buffer.from('data: [DONE]\n\n', 'utf8'));
        await endResponse(res);
        providerUsageMetadata = providerResult.getUsageMetadata?.() ?? providerUsageMetadata;
      } else {
        const bodyText = JSON.stringify(traiResponseToGeminiJSON(providerResult.response));
        logTraiRequestSuccessSummary({
          feature,
          providerName: selectedAIProvider.name,
          traiRequest,
          traiResponse: providerResult.response
        });
        res.writeHead(200, {
          'Content-Type': 'application/json'
        });
        responseStarted = true;
        await endResponse(res, bodyText);
        providerUsageMetadata = providerResult.usageMetadata ?? providerUsageMetadata;
      }

      deliveryCompleted = true;
    } catch (error) {
      if (!deliveryCompleted && !reservationReleased) {
        await releaseReservedQuotaUsage(reservedQuotaPeriod, unitCost);
        reservationReleased = true;
      }

      const outcome = responseStarted ? 'delivery_failed' : 'upstream_error';
      await recordAIRequest(
        auth.user.id,
        feature,
        action,
        outcome,
        Date.now() - startedAt,
        selectedAIProvider.model,
        {
          provider: selectedAIProvider.name,
          providerUsage: providerUsageMetadata,
          requestFormat: traiRequest?.requestFormat,
          retryCount,
          retryReason
        }
      );

      if (responseStarted) {
        if (!res.destroyed) {
          res.destroy(error);
        }
        return;
      }

      throw error;
    } finally {
      releaseConcurrencySlot();
    }

    try {
      await recordUsage(auth.user.id, reservedQuotaPeriod, feature, unitCost, {
        incrementQuotaUnits: false
      });
      await recordAIRequest(
        auth.user.id,
        feature,
        action,
        'success',
        Date.now() - startedAt,
        selectedAIProvider.model,
        {
          provider: selectedAIProvider.name,
          providerUsage: providerUsageMetadata,
          requestFormat: traiRequest?.requestFormat,
          retryCount,
          retryReason
        }
      );
    } catch (error) {
      console.error('Failed to finalize AI proxy accounting', error);
    }
  }

  function ensureEntitled(subscription) {
    if (subscription.plan === 'free') {
      throw new HttpError(403, {
        error: 'subscription_required',
        message: 'Trai Pro is required to use AI features.'
      });
    }

    const entitledStatuses = new Set(['active', 'trial', 'gracePeriod']);
    if (!entitledStatuses.has(subscription.status) && subscription.plan !== 'developer') {
      throw new HttpError(403, {
        error: 'subscription_inactive',
        message: `Subscription is ${subscription.status}.`
      });
    }
  }

  function responseClosedError() {
    const error = new Error('Response closed before delivery completed.');
    error.code = 'RESPONSE_CLOSED';
    return error;
  }

  async function writeResponseChunk(res, chunk) {
    if (res.destroyed || !res.writable) {
      throw responseClosedError();
    }

    await new Promise((resolve, reject) => {
      const onClose = () => {
        cleanup();
        reject(responseClosedError());
      };
      const onError = (error) => {
        cleanup();
        reject(error);
      };
      const cleanup = () => {
        res.off('close', onClose);
        res.off('error', onError);
      };

      res.once('close', onClose);
      res.once('error', onError);
      res.write(chunk, (error) => {
        cleanup();
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }

  function normalizeAIProxyFeature(headerValue, traiRequest) {
    const requestedFeature = normalizeRequestedFeature(headerValue);
    const minimumFeature = inferMinimumFeatureForTraiRequest(traiRequest);

    const requestedCost = FEATURE_COSTS[requestedFeature] ?? FEATURE_COSTS.coachChat;
    const minimumCost = FEATURE_COSTS[minimumFeature] ?? FEATURE_COSTS.coachChat;
    return minimumCost > requestedCost ? minimumFeature : requestedFeature;
  }

  function normalizeRequestedFeature(headerValue) {
    const requested = String(headerValue ?? 'coachChat');
    return Object.hasOwn(FEATURE_COSTS, requested) ? requested : 'coachChat';
  }

  function inferMinimumFeatureForTraiRequest(traiRequest) {
    let hasImages = false;
    let hasToolResponses = false;
    let hasTools = false;

    for (const message of canonicalMessagesFromTraiRequest(traiRequest)) {
      for (const part of normalizeArray(message?.parts)) {
        if (part?.type === 'image') {
          hasImages = true;
        }
        if (part?.type === 'tool_response') {
          hasToolResponses = true;
        }
      }
    }

    hasTools = normalizeArray(traiRequest?.tools).some((tool) =>
      typeof tool?.name === 'string' && tool.name.trim().length > 0
    );

    if (hasImages) {
      return 'exercisePhotoAnalysis';
    }

    if (hasToolResponses) {
      return 'agentToolFollowUp';
    }

    if (hasTools) {
      return 'agentCoachChat';
    }

    return 'coachChat';
  }

  function sanitizeIncomingTraiRequestBody(requestBody) {
    if (!requestBody || typeof requestBody !== 'object' || Array.isArray(requestBody)) {
      throw new HttpError(400, {
        error: 'invalid_ai_request',
        message: 'AI proxy request body must be a JSON object.'
      });
    }

    const messageEntries = extractIncomingRequestMessages(requestBody);
    if (messageEntries.length === 0) {
      throw new HttpError(400, {
        error: 'invalid_ai_request',
        message: 'AI proxy requests must include at least one message.'
      });
    }

    if (messageEntries.length > config.aiProxyMaxContents) {
      throw new HttpError(413, {
        error: 'ai_request_too_large',
        message: 'Conversation context is too large for the AI proxy.'
      });
    }

    let totalTextChars = 0;
    let inlineImages = 0;
    let inlineImageBytes = 0;

    for (const message of messageEntries) {
      if (!message || typeof message !== 'object' || Array.isArray(message)) {
        throw new HttpError(400, {
          error: 'invalid_ai_request',
          message: 'Each AI message must be an object.'
        });
      }

      if (!Array.isArray(message.parts) || message.parts.length === 0) {
        throw new HttpError(400, {
          error: 'invalid_ai_request',
          message: 'Each AI message must include at least one part.'
        });
      }

      if (message.parts.length > config.aiProxyMaxPartsPerContent) {
        throw new HttpError(413, {
          error: 'ai_request_too_large',
          message: 'One of the AI messages contains too many parts.'
        });
      }

      for (const part of message.parts) {
        if (typeof part?.text === 'string') {
          totalTextChars += part.text.length;
        }

        const imagePart = extractRequestImagePart(part);
        if (imagePart) {
          inlineImages += 1;
          const inlineData = typeof imagePart.data === 'string' ? imagePart.data : '';
          inlineImageBytes += Buffer.byteLength(inlineData, 'base64');
        }
      }
    }

    if (totalTextChars > config.aiProxyMaxTotalTextChars) {
      throw new HttpError(413, {
        error: 'ai_request_too_large',
        message: 'Prompt context is too large for the AI proxy.'
      });
    }

    if (inlineImages > config.aiProxyMaxInlineImages || inlineImageBytes > config.aiProxyMaxInlineImageBytes) {
      throw new HttpError(413, {
        error: 'ai_request_too_large',
        message: 'Attached media is too large for the AI proxy.'
      });
    }

    if (Array.isArray(requestBody.tools)) {
      const declarationCount = requestBody.tools.reduce((count, tool) => {
        if (Array.isArray(tool?.function_declarations)) {
          return count + tool.function_declarations.length;
        }
        if (typeof tool?.name === 'string' && tool.name.trim().length > 0) {
          return count + 1;
        }
        return count;
      }, 0);

      if (declarationCount > config.aiProxyMaxFunctionDeclarations) {
        throw new HttpError(413, {
          error: 'ai_request_too_large',
          message: 'Too many tool declarations were sent to the AI proxy.'
        });
      }
    }

    const canonicalGeneration = normalizeObject(requestBody.generation);
    const legacyGenerationConfig = normalizeObject(requestBody.generationConfig);
    const isCanonicalRequest = looksLikeCanonicalRequestBody(requestBody);
    const activeGeneration = isCanonicalRequest ? canonicalGeneration : legacyGenerationConfig;
    const requestedMaxOutputTokens = Number.parseInt(activeGeneration.maxOutputTokens ?? `${config.aiProxyMaxOutputTokens}`, 10);
    const normalizedMaxOutputTokens = Number.isFinite(requestedMaxOutputTokens)
      ? Math.min(Math.max(requestedMaxOutputTokens, 1), config.aiProxyMaxOutputTokens)
      : config.aiProxyMaxOutputTokens;

    if (isCanonicalRequest) {
      requestBody.generation = {
        ...canonicalGeneration,
        maxOutputTokens: normalizedMaxOutputTokens
      };
      return;
    }

    requestBody.generationConfig = {
      ...legacyGenerationConfig,
      maxOutputTokens: normalizedMaxOutputTokens
    };
    if (requestBody.generationConfig.candidateCount != null) {
      requestBody.generationConfig.candidateCount = 1;
    }
  }

  function extractIncomingRequestMessages(requestBody) {
    if (Array.isArray(requestBody?.messages)) {
      return requestBody.messages;
    }

    if (Array.isArray(requestBody?.contents)) {
      return requestBody.contents;
    }

    return [];
  }

  function normalizeObject(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  }

  function looksLikeCanonicalRequestBody(requestBody) {
    return Array.isArray(requestBody?.messages)
      || Object.prototype.hasOwnProperty.call(requestBody ?? {}, 'system')
      || Object.prototype.hasOwnProperty.call(requestBody ?? {}, 'generation')
      || Object.prototype.hasOwnProperty.call(requestBody ?? {}, 'output');
  }

  function extractInlineDataPart(part) {
    const inlineDataPart = part?.inlineData ?? part?.inline_data;
    return inlineDataPart && typeof inlineDataPart === 'object' && !Array.isArray(inlineDataPart)
      ? inlineDataPart
      : null;
  }

  function extractRequestImagePart(part) {
    const inlineDataPart = extractInlineDataPart(part);
    if (inlineDataPart) {
      return inlineDataPart;
    }

    if (
      part?.type === 'image'
      && typeof part?.mimeType === 'string'
      && typeof part?.data === 'string'
    ) {
      return {
        mimeType: part.mimeType,
        data: part.data
      };
    }

    return null;
  }

  function logTraiRequestSuccessSummary({ feature, providerName, traiRequest, traiResponse }) {
    if (
      feature !== 'foodPhotoAnalysis'
      && feature !== 'exercisePhotoAnalysis'
      && !requestContainsImages(traiRequest)
    ) {
      return;
    }

    const responseText = normalizeArray(traiResponse?.parts)
      .filter((part) => part?.type === 'text' && typeof part?.text === 'string')
      .map((part) => part.text)
      .join('\n');

    const baseSummary = {
      feature,
      provider: providerName,
      requestFormat: typeof traiRequest?.requestFormat === 'string' ? traiRequest.requestFormat : 'unknown',
      imageCount: countTraiRequestImages(traiRequest),
      responseChars: responseText.length
    };

    const parsed = parseTopLevelJSONObject(responseText);

    if (feature === 'foodPhotoAnalysis' && parsed) {
      const summary = summarizeFoodAnalysisPayload(parsed);

      console.log('[AI image summary]', JSON.stringify({
        ...baseSummary,
        classification: summary.classification,
        calories: summary.calories,
        proteinGrams: summary.proteinGrams,
        carbsGrams: summary.carbsGrams,
        fatGrams: summary.fatGrams,
        confidence: summary.confidence
      }));
      return;
    }

    if (feature === 'exercisePhotoAnalysis' && parsed) {
      const normalizedName = String(parsed.equipmentName ?? '').trim().toLowerCase();
      console.log('[AI image summary]', JSON.stringify({
        ...baseSummary,
        classification: normalizedName === 'unclear gym equipment' ? 'unclear' : normalizedName ? 'identified' : 'missing_name',
        suggestedExercisesCount: Array.isArray(parsed.suggestedExercises) ? parsed.suggestedExercises.length : 0
      }));
      return;
    }

    console.log('[AI image summary]', JSON.stringify(baseSummary));
  }

  function requestContainsImages(traiRequest) {
    return countTraiRequestImages(traiRequest) > 0;
  }

  async function executeTraiRequestWithRetries(selectedAIProvider, traiRequest, { streaming, feature }) {
    const providerResult = await selectedAIProvider.execute(traiRequest, { streaming });
    if (streaming || providerResult?.type !== 'single' || feature !== 'foodPhotoAnalysis') {
      return {
        providerResult,
        retryCount: 0,
        retryReason: null
      };
    }

    const foodSummary = summarizeFoodAnalysisResponse(providerResult.response);
    if (!shouldRetryFoodAnalysis(foodSummary)) {
      return {
        providerResult,
        retryCount: 0,
        retryReason: null
      };
    }

    const retryReason = 'identified_zero_macro_estimate';
    console.log('[AI food retry]', JSON.stringify({
      provider: selectedAIProvider.name,
      reason: retryReason,
      classification: foodSummary.classification,
      calories: foodSummary.calories,
      proteinGrams: foodSummary.proteinGrams,
      carbsGrams: foodSummary.carbsGrams,
      fatGrams: foodSummary.fatGrams
    }));

    const retryRequest = buildFoodAnalysisRetryRequest(traiRequest, providerResult.response);
    return {
      providerResult: await selectedAIProvider.execute(retryRequest, { streaming: false }),
      retryCount: 1,
      retryReason
    };
  }

  function shouldRetryFoodAnalysis(foodSummary) {
    return foodSummary.classification === 'identified'
      && foodSummary.calories === 0
      && foodSummary.proteinGrams === 0
      && foodSummary.carbsGrams === 0
      && foodSummary.fatGrams === 0;
  }

  function buildFoodAnalysisRetryRequest(traiRequest, traiResponse) {
    const priorResponseText = extractTraiResponseText(traiResponse);
    const correctiveText = [
      'Your previous food-analysis result was invalid.',
      'You identified a non-water food or drink but returned 0 calories and 0g macros.',
      'Re-examine the same image carefully and return one of these only:',
      '1. A realistic non-zero calorie/macro estimate for the identified food or drink, or',
      '2. The exact sentinel name "Unclear food or drink" only if there is no identifiable loggable food or drink visible at all.',
      'Do not return 0 calories and 0g macros unless the item is clearly plain water or plain sparkling water with no additions.'
    ].join(' ');

    return {
      ...traiRequest,
      canonicalMessages: [
        ...canonicalMessagesFromTraiRequest(traiRequest),
        {
          role: 'assistant',
          parts: [{ type: 'text', text: priorResponseText }]
        },
        {
          role: 'user',
          parts: [{ type: 'text', text: correctiveText }]
        }
      ]
    };
  }

  function countTraiRequestImages(traiRequest) {
    return canonicalMessagesFromTraiRequest(traiRequest).reduce((count, message) => {
      return count + normalizeArray(message?.parts).filter((part) => part?.type === 'image').length;
    }, 0);
  }

  function summarizeFoodAnalysisResponse(traiResponse) {
    const parsed = parseTopLevelJSONObject(extractTraiResponseText(traiResponse));
    return summarizeFoodAnalysisPayload(parsed);
  }

  function summarizeFoodAnalysisPayload(parsed) {
    const normalizedName = String(parsed?.name ?? '').trim().toLowerCase();
    const classification =
      normalizedName === 'unclear food or drink'
        ? 'unclear'
        : ['water', 'plain water', 'sparkling water', 'plain sparkling water'].includes(normalizedName)
          ? 'water'
          : normalizedName.length > 0
            ? 'identified'
            : 'missing_name';

    return {
      classification,
      calories: finiteNumberOrNull(parsed?.calories),
      proteinGrams: finiteNumberOrNull(parsed?.proteinGrams),
      carbsGrams: finiteNumberOrNull(parsed?.carbsGrams),
      fatGrams: finiteNumberOrNull(parsed?.fatGrams),
      confidence: typeof parsed?.confidence === 'string' ? parsed.confidence : null
    };
  }

  function extractTraiResponseText(traiResponse) {
    return normalizeArray(traiResponse?.parts)
      .filter((part) => part?.type === 'text' && typeof part?.text === 'string')
      .map((part) => part.text)
      .join('\n');
  }

  function parseTopLevelJSONObject(text) {
    if (typeof text !== 'string' || text.trim().length === 0) {
      return null;
    }

    const trimmed = text.trim();
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) {
      return null;
    }

    try {
      const parsed = JSON.parse(match[0]);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
    } catch {
      return null;
    }
  }

  function finiteNumberOrNull(value) {
    return Number.isFinite(value) ? value : null;
  }

  function normalizeArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function pacingLimitError(error, message) {
    return new HttpError(429, { error, message });
  }

  function quotaLimitError(error, message) {
    return new HttpError(403, { error, message });
  }

  async function enforceAIProxyBurstLimits(userID, plan, unitCost) {
    const oneMinuteAgo = new Date(Date.now() - (60 * 1000)).toISOString();
    const tenMinutesAgo = new Date(Date.now() - (10 * 60 * 1000)).toISOString();
    const twentyFourHoursAgo = new Date(Date.now() - (24 * 60 * 60 * 1000)).toISOString();
    const sevenDaysAgo = new Date(Date.now() - (7 * 24 * 60 * 60 * 1000)).toISOString();

    const recentAttempts = await db.prepare(`
      SELECT COUNT(*) AS count
      FROM ai_requests
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, oneMinuteAgo);

    if ((recentAttempts?.count ?? 0) >= config.aiProxyMaxRequestsPerMinute) {
      throw pacingLimitError(
        'ai_rate_limited_requests_per_minute',
        'You are sending Trai AI requests too quickly right now. Please wait a minute and try again.'
      );
    }

    const recentUsage = await db.prepare(`
      SELECT COALESCE(SUM(unit_cost), 0) AS units
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, tenMinutesAgo);

    if (((recentUsage?.units ?? 0) + unitCost) > config.aiProxyMaxUnitsPerTenMinutes) {
      throw pacingLimitError(
        'ai_rate_limited_units_per_ten_minutes',
        'You have hit a short-term Trai AI pacing limit. Please wait a bit and try again.'
      );
    }

    if (plan !== 'developer') {
      const dailyUsage = await db.prepare(`
        SELECT COALESCE(SUM(unit_cost), 0) AS units
        FROM usage_ledger
        WHERE user_id = ? AND created_at >= ?
      `).get(userID, twentyFourHoursAgo);

      if (((dailyUsage?.units ?? 0) + unitCost) > config.aiProxyMaxUnitsPer24Hours) {
        throw quotaLimitError(
          'quota_exhausted_daily',
          'You have hit your daily Trai AI limit. Please try again tomorrow.'
        );
      }

      const weeklyUsage = await db.prepare(`
        SELECT COALESCE(SUM(unit_cost), 0) AS units
        FROM usage_ledger
        WHERE user_id = ? AND created_at >= ?
      `).get(userID, sevenDaysAgo);

      if (((weeklyUsage?.units ?? 0) + unitCost) > config.aiProxyMaxUnitsPer7Days) {
        throw quotaLimitError(
          'quota_exhausted_weekly',
          'You have hit your weekly Trai AI limit. Please try again in a few days.'
        );
      }
    }
  }

  function reserveAIConcurrencySlot(userID) {
    const activeRequests = activeAIRequestsByUser.get(userID) ?? 0;
    if (activeRequests >= config.aiProxyMaxConcurrentRequestsPerUser) {
      throw pacingLimitError(
        'ai_rate_limited_concurrency',
        'Another Trai AI request is still running. Please wait a moment and try again.'
      );
    }

    activeAIRequestsByUser.set(userID, activeRequests + 1);

    return () => {
      const latestActiveRequests = activeAIRequestsByUser.get(userID) ?? 0;
      if (latestActiveRequests <= 1) {
        activeAIRequestsByUser.delete(userID);
        return;
      }

      activeAIRequestsByUser.set(userID, latestActiveRequests - 1);
    };
  }

  async function endResponse(res, body) {
    if (res.destroyed || !res.writable) {
      throw responseClosedError();
    }

    await new Promise((resolve, reject) => {
      const onClose = () => {
        cleanup();
        reject(responseClosedError());
      };
      const onError = (error) => {
        cleanup();
        reject(error);
      };
      const cleanup = () => {
        res.off('close', onClose);
        res.off('error', onError);
      };

      res.once('close', onClose);
      res.once('error', onError);
      res.end(body, (error) => {
        cleanup();
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }

  return {
    routeRequest,
    handleServerError
  };
}
