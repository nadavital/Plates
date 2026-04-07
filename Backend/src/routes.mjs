export function createRouteHandlers({
  db,
  config,
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

  async function routeRequest(req, res) {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, {
        ok: true,
        environment: config.environment,
        hasGeminiKey: Boolean(config.geminiApiKey),
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
    const user = findOrCreateUserFromApple(normalizedBody, now);
    const session = createSession(user.id, body.installationID, body.appAccountToken, now);
    const billing = buildBillingPayload(user.id, body.installationID, body.appAccountToken, now);

    sendJson(res, 200, {
      session: buildSessionSnapshot(session, user, now),
      billing
    });
  }

  async function handleRefresh(req, res) {
    const body = await readJson(req);
    assertRequired(body, ['refreshToken', 'appAccountToken']);

    const refreshTokenHash = hashToken(body.refreshToken);
    const row = db.prepare(`
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
    const tokens = rotateSessionTokens(row.id, now);
    const identity = db.prepare(`
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

    const billing = buildBillingPayload(row.user_id, row.installation_id ?? 'unknown-installation', row.app_account_token, now);
    sendJson(res, 200, {
      session: buildSessionSnapshot(session, user, now),
      billing
    });
  }

  async function handleBootstrap(req, res) {
    const auth = requireSession(req);
    const now = isoNow();
    const billing = buildBillingPayload(
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
    const auth = requireSession(req);
    const billing = buildBillingPayload(
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
      appAccountToken: url.searchParams.get('appAccountToken'),
      originalTransactionId: url.searchParams.get('originalTransactionId')
    });

    const userID = resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    sendJson(res, 200, buildAdminUserInspection(userID));
  }

  async function handleAdminReconcileSubscription(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = resolveAdminUserID(lookup);
    if (!userID) {
      throw new HttpError(404, {
        error: 'user_not_found',
        message: 'No user matched the provided lookup.'
      });
    }

    const summary = reconcileUserSubscriptionFromLedger(userID, isoNow());
    sendJson(res, 200, summary);
  }

  async function handleAdminQuotaAdjustment(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = resolveAdminUserID(lookup);
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
    const subscription = ensureSubscription(userID, now);
    const quotaPeriod = ensureQuotaPeriod(userID, subscription.plan, now);
    const reason = normalizeAdminReason(body.reason);

    const updatedQuotaPeriod = applyQuotaAdjustment({
      userID,
      quotaPeriod,
      unitDelta,
      reason,
      createdBy: body.createdBy
    }, now);

    sendJson(res, 200, {
      userID,
      adjustedAt: now,
      quotaSnapshot: buildQuotaSnapshot(updatedQuotaPeriod),
      analytics: buildUsageAnalytics(userID, updatedQuotaPeriod)
    });
  }

  async function handleAdminQuotaReset(req, res) {
    requireAdmin(req);
    const body = await readJson(req);

    const lookup = resolveAdminLookup({
      userID: body.userID,
      appAccountToken: body.appAccountToken,
      originalTransactionId: body.originalTransactionId
    });

    const userID = resolveAdminUserID(lookup);
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
    const subscription = ensureSubscription(userID, now);
    const quotaPeriod = ensureQuotaPeriod(userID, subscription.plan, now);
    const reason = normalizeAdminReason(body.reason);

    const updatedQuotaPeriod = resetQuotaUsage({
      userID,
      quotaPeriod,
      resetUsedUnitsTo,
      reason,
      createdBy: body.createdBy
    }, now);

    sendJson(res, 200, {
      userID,
      resetAt: now,
      quotaSnapshot: buildQuotaSnapshot(updatedQuotaPeriod),
      analytics: buildUsageAnalytics(userID, updatedQuotaPeriod)
    });
  }

  async function handleStoreKitSync(req, res) {
    const auth = requireSession(req);
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

    const matchedUserIDs = new Set(
      normalizedEntitlements
        .map((entitlement) => {
          if (!entitlement) {
            return null;
          }

          const originalTransactionOwner = findUserIDForOriginalTransaction(entitlement.originalTransactionID);
          if (originalTransactionOwner) {
            return originalTransactionOwner;
          }

          return findUserIDForStoreKitTransaction(entitlement);
        })
        .filter(Boolean)
    );

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

    applyStoreKitSubscriptionState(auth.user.id, normalizedEntitlements, now);
    persistStoreKitTransactions(auth.user.id, normalizedEntitlements, signedTransactions, now);

    const billing = buildBillingPayload(
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
      ? findUserIDForStoreKitTransaction(transaction)
      : renewalInfo
        ? findUserIDForOriginalTransaction(renewalInfo.originalTransactionId)
        : null;

    if (userID) {
      applyNotificationLifecycleUpdate(userID, {
        notification,
        transaction,
        renewalInfo
      }, now);

      if (transaction) {
        persistStoreKitTransactions(userID, [transaction], [signedTransactionInfo], now);
      }
    }

    persistAppStoreNotification(notification, body.signedPayload, transaction, renewalInfo, now);
    sendJson(res, 200, {
      ok: true,
      matchedUser: Boolean(userID)
    });
  }

  async function handleAIProxy(req, res, url, { streaming }) {
    const auth = requireSession(req);
    const action = streaming ? 'streamGenerateContent' : 'generateContent';
    const requestBody = await readJson(req, {
      maxBytes: config.aiProxyMaxRequestBytes
    });
    const feature = normalizeAIProxyFeature(req.headers['x-trai-ai-feature'], requestBody);
    sanitizeAIProxyRequestBody(requestBody);

    const subscription = ensureSubscription(auth.user.id, isoNow());
    ensureEntitled(subscription);
    enforceAIProxyBurstLimits(auth.user.id);
    const releaseConcurrencySlot = reserveAIConcurrencySlot(auth.user.id);

    const quotaPeriod = ensureQuotaPeriod(auth.user.id, subscription.plan, isoNow());
    const unitCost = FEATURE_COSTS[feature] ?? FEATURE_COSTS.coachChat;
    const reservedQuotaPeriod = reserveQuotaUsage(quotaPeriod, unitCost);

    if (!config.geminiApiKey) {
      releaseReservedQuotaUsage(reservedQuotaPeriod, unitCost);
      throw new HttpError(503, {
        error: 'gemini_not_configured',
        message: 'GEMINI_API_KEY is required for AI proxy requests.'
      });
    }

    const startedAt = Date.now();
    let reservationReleased = false;
    let responseStarted = false;
    let deliveryCompleted = false;

    try {
      const upstreamURL = buildGeminiURL(action, streaming);
      const upstreamResponse = await fetch(upstreamURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        throw new HttpError(upstreamResponse.status, {
          error: 'gemini_error',
          message: errorText || 'Gemini proxy request failed.'
        });
      }

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
        releaseReservedQuotaUsage(reservedQuotaPeriod, unitCost);
        reservationReleased = true;
      }

      const outcome = responseStarted ? 'delivery_failed' : 'upstream_error';
      recordAIRequest(auth.user.id, feature, action, outcome, Date.now() - startedAt);

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
      recordUsage(auth.user.id, reservedQuotaPeriod, feature, unitCost, {
        incrementQuotaUnits: false
      });
      recordAIRequest(auth.user.id, feature, action, 'success', Date.now() - startedAt);
    } catch (error) {
      console.error('Failed to finalize AI proxy accounting', error);
    }
  }

  function buildGeminiURL(action, streaming) {
    const query = new URLSearchParams({ key: config.geminiApiKey });
    if (streaming) {
      query.set('alt', 'sse');
    }

    return `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:${action}?${query.toString()}`;
  }

  function ensureEntitled(subscription) {
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

  function enforceAIProxyBurstLimits(userID) {
    const oneMinuteAgo = new Date(Date.now() - (60 * 1000)).toISOString();
    const tenMinutesAgo = new Date(Date.now() - (10 * 60 * 1000)).toISOString();

    const recentAttempts = db.prepare(`
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

    const recentUsage = db.prepare(`
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
