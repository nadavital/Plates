export function createRouteHandlers({
  db,
  config,
  aiProvider,
  HttpError,
  readJson,
  sendJson,
  buildSessionSnapshot,
  buildAdminUserInspection,
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

  async function routeRequest(req, res) {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, {
        ok: true,
        environment: config.environment,
        aiProvider: aiProvider.name,
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
    const action = streaming ? 'stream' : 'generate';
    const requestBody = await readJson(req, {
      maxBytes: config.aiProxyMaxRequestBytes
    });
    const feature = normalizeAIProxyFeature(req.headers['x-trai-ai-feature'], requestBody);
    sanitizeAIProxyRequestBody(requestBody);

    const subscription = await ensureSubscription(auth.user.id, isoNow());
    ensureEntitled(subscription);
    await enforceAIProxyBurstLimits(auth.user.id);
    const releaseConcurrencySlot = reserveAIConcurrencySlot(auth.user.id);

    const quotaPeriod = await ensureQuotaPeriod(auth.user.id, subscription.plan, isoNow());
    const unitCost = FEATURE_COSTS[feature] ?? FEATURE_COSTS.coachChat;
    const reservedQuotaPeriod = await reserveQuotaUsage(quotaPeriod, unitCost);

    const startedAt = Date.now();
    let reservationReleased = false;
    let responseStarted = false;
    let deliveryCompleted = false;

    try {
      const upstreamResponse = await aiProvider.execute(requestBody, { streaming });

      if (streaming) {
        res.writeHead(200, {
          'Content-Type': upstreamResponse.headers.get('content-type') ?? 'text/event-stream',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive'
        });
        responseStarted = true;

        for await (const chunk of upstreamResponse.body) {
          await writeResponseChunk(res, chunk);
        }
        await endResponse(res);
      } else {
        const bodyText = await upstreamResponse.text();
        res.writeHead(200, {
          'Content-Type': upstreamResponse.headers.get('content-type') ?? 'application/json'
        });
        responseStarted = true;
        await endResponse(res, bodyText);
      }

      deliveryCompleted = true;
    } catch (error) {
      if (!deliveryCompleted && !reservationReleased) {
        await releaseReservedQuotaUsage(reservedQuotaPeriod, unitCost);
        reservationReleased = true;
      }

      const outcome = responseStarted ? 'delivery_failed' : 'upstream_error';
      await recordAIRequest(auth.user.id, feature, action, outcome, Date.now() - startedAt);

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
      await recordAIRequest(auth.user.id, feature, action, 'success', Date.now() - startedAt);
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

  function normalizeAIProxyFeature(headerValue, requestBody) {
    const requestedFeature = normalizeRequestedFeature(headerValue);
    const minimumFeature = inferMinimumFeatureForRequest(requestBody);

    const requestedCost = FEATURE_COSTS[requestedFeature] ?? FEATURE_COSTS.coachChat;
    const minimumCost = FEATURE_COSTS[minimumFeature] ?? FEATURE_COSTS.coachChat;
    return minimumCost > requestedCost ? minimumFeature : requestedFeature;
  }

  function normalizeRequestedFeature(headerValue) {
    const requested = String(headerValue ?? 'coachChat');
    return Object.hasOwn(FEATURE_COSTS, requested) ? requested : 'coachChat';
  }

  function inferMinimumFeatureForRequest(requestBody) {
    let hasInlineMedia = false;
    let hasFunctionResponses = false;
    let hasTools = false;

    if (Array.isArray(requestBody?.contents)) {
      for (const content of requestBody.contents) {
        if (!Array.isArray(content?.parts)) {
          continue;
        }

        for (const part of content.parts) {
          if (part?.inline_data) {
            hasInlineMedia = true;
          }
          if (part?.functionResponse) {
            hasFunctionResponses = true;
          }
        }
      }
    }

    if (Array.isArray(requestBody?.tools)) {
      hasTools = requestBody.tools.some((tool) =>
        Array.isArray(tool?.function_declarations) && tool.function_declarations.length > 0
      );
    }

    if (hasInlineMedia) {
      return 'exercisePhotoAnalysis';
    }

    if (hasFunctionResponses) {
      return 'agentToolFollowUp';
    }

    if (hasTools) {
      return 'agentCoachChat';
    }

    return 'coachChat';
  }

  function sanitizeAIProxyRequestBody(requestBody) {
    if (!requestBody || typeof requestBody !== 'object' || Array.isArray(requestBody)) {
      throw new HttpError(400, {
        error: 'invalid_ai_request',
        message: 'AI proxy request body must be a JSON object.'
      });
    }

    const contents = requestBody.contents;
    if (!Array.isArray(contents) || contents.length === 0) {
      throw new HttpError(400, {
        error: 'invalid_ai_request',
        message: 'AI proxy requests must include at least one content item.'
      });
    }

    if (contents.length > config.aiProxyMaxContents) {
      throw new HttpError(413, {
        error: 'ai_request_too_large',
        message: 'Conversation context is too large for the AI proxy.'
      });
    }

    let totalTextChars = 0;
    let inlineImages = 0;
    let inlineImageBytes = 0;

    for (const content of contents) {
      if (!content || typeof content !== 'object' || Array.isArray(content)) {
        throw new HttpError(400, {
          error: 'invalid_ai_request',
          message: 'Each content entry must be an object.'
        });
      }

      if (!Array.isArray(content.parts) || content.parts.length === 0) {
        throw new HttpError(400, {
          error: 'invalid_ai_request',
          message: 'Each content entry must include at least one part.'
        });
      }

      if (content.parts.length > config.aiProxyMaxPartsPerContent) {
        throw new HttpError(413, {
          error: 'ai_request_too_large',
          message: 'One of the AI content entries contains too many parts.'
        });
      }

      for (const part of content.parts) {
        if (typeof part?.text === 'string') {
          totalTextChars += part.text.length;
        }

        if (part?.inline_data) {
          inlineImages += 1;
          const inlineData = typeof part.inline_data.data === 'string' ? part.inline_data.data : '';
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
        if (!Array.isArray(tool?.function_declarations)) {
          return count;
        }
        return count + tool.function_declarations.length;
      }, 0);

      if (declarationCount > config.aiProxyMaxFunctionDeclarations) {
        throw new HttpError(413, {
          error: 'ai_request_too_large',
          message: 'Too many tool declarations were sent to the AI proxy.'
        });
      }
    }

    const generationConfig = requestBody.generationConfig;
    if (generationConfig && typeof generationConfig === 'object' && !Array.isArray(generationConfig)) {
      const requestedMaxOutputTokens = Number.parseInt(generationConfig.maxOutputTokens ?? `${config.aiProxyMaxOutputTokens}`, 10);
      generationConfig.maxOutputTokens = Number.isFinite(requestedMaxOutputTokens)
        ? Math.min(Math.max(requestedMaxOutputTokens, 1), config.aiProxyMaxOutputTokens)
        : config.aiProxyMaxOutputTokens;

      if (generationConfig.candidateCount != null) {
        generationConfig.candidateCount = 1;
      }
    } else {
      requestBody.generationConfig = {
        maxOutputTokens: config.aiProxyMaxOutputTokens
      };
    }
  }

  async function enforceAIProxyBurstLimits(userID) {
    const oneMinuteAgo = new Date(Date.now() - (60 * 1000)).toISOString();
    const tenMinutesAgo = new Date(Date.now() - (10 * 60 * 1000)).toISOString();

    const recentAttempts = await db.prepare(`
      SELECT COUNT(*) AS count
      FROM ai_requests
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, oneMinuteAgo);

    if ((recentAttempts?.count ?? 0) >= config.aiProxyMaxRequestsPerMinute) {
      throw new HttpError(429, {
        error: 'ai_rate_limited',
        message: 'AI is temporarily unavailable for this account right now.'
      });
    }

    const recentUsage = await db.prepare(`
      SELECT COALESCE(SUM(unit_cost), 0) AS units
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, tenMinutesAgo);

    if ((recentUsage?.units ?? 0) >= config.aiProxyMaxUnitsPerTenMinutes) {
      throw new HttpError(429, {
        error: 'ai_rate_limited',
        message: 'AI is temporarily unavailable for this account right now.'
      });
    }
  }

  function reserveAIConcurrencySlot(userID) {
    const activeRequests = activeAIRequestsByUser.get(userID) ?? 0;
    if (activeRequests >= config.aiProxyMaxConcurrentRequestsPerUser) {
      throw new HttpError(429, {
        error: 'ai_rate_limited',
        message: 'AI is temporarily unavailable for this account right now.'
      });
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
