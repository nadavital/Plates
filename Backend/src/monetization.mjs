export function createMonetizationHelpers({
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
}) {
  async function ensureQuotaPeriod(userID, plan, now) {
    const date = new Date(now);
    const periodStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    const periodEnd = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
    const limit = PLAN_LIMITS[plan] ?? null;

    let period = await db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE user_id = ? AND period_start = ? AND period_end = ?
    `).get(userID, periodStart.toISOString(), periodEnd.toISOString());

    if (!period) {
      await db.prepare(`
        INSERT INTO quota_periods (
          id, user_id, period_start, period_end, unit_limit, bonus_units, units_used, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        createID('qtp'),
        userID,
        periodStart.toISOString(),
        periodEnd.toISOString(),
        limit,
        0,
        0,
        now,
        now
      );

      period = await db.prepare(`
        SELECT *
        FROM quota_periods
        WHERE user_id = ? AND period_start = ? AND period_end = ?
      `).get(userID, periodStart.toISOString(), periodEnd.toISOString());
    } else if (period.unit_limit !== limit) {
      await db.prepare(`
        UPDATE quota_periods
        SET unit_limit = ?, updated_at = ?
        WHERE id = ?
      `).run(limit, now, period.id);

      period = await db.prepare(`
        SELECT *
        FROM quota_periods
        WHERE id = ?
      `).get(period.id);
    }

    return period;
  }

  function ensureQuotaAvailable(quotaPeriod, unitCost) {
    const effectiveLimit = effectiveQuotaLimit(quotaPeriod);
    if (effectiveLimit == null) {
      return;
    }

    if ((quotaPeriod.units_used + unitCost) > effectiveLimit) {
      throw new HttpError(403, {
        error: 'quota_exhausted_monthly',
        message: 'You have hit your monthly Trai AI limit. Please try again next month.'
      });
    }
  }

  async function reserveQuotaUsage(quotaPeriod, unitCost) {
    const now = isoNow();
    const result = await db.prepare(`
      UPDATE quota_periods
      SET units_used = units_used + ?, updated_at = ?
      WHERE id = ?
        AND (
          unit_limit IS NULL
          OR (units_used + ?) <= (unit_limit + COALESCE(bonus_units, 0))
        )
    `).run(unitCost, now, quotaPeriod.id, unitCost);

    if (result.changes === 0) {
      const latestQuotaPeriod = await db.prepare(`
        SELECT *
        FROM quota_periods
        WHERE id = ?
      `).get(quotaPeriod.id);

      if (latestQuotaPeriod) {
        ensureQuotaAvailable(latestQuotaPeriod, unitCost);
      }

      throw new HttpError(409, {
        error: 'quota_reservation_failed',
        message: 'Unable to reserve AI quota right now. Please try again.'
      });
    }

    return await db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  async function releaseReservedQuotaUsage(quotaPeriod, unitCost) {
    const now = isoNow();
    await db.prepare(`
      UPDATE quota_periods
      SET units_used = MAX(units_used - ?, 0), updated_at = ?
      WHERE id = ?
    `).run(unitCost, now, quotaPeriod.id);

    return await db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  async function recordUsage(userID, quotaPeriod, feature, unitCost, options = {}) {
    const incrementQuotaUnits = options.incrementQuotaUnits ?? true;
    const now = isoNow();

    if (incrementQuotaUnits) {
      await db.prepare(`
        UPDATE quota_periods
        SET units_used = units_used + ?, updated_at = ?
        WHERE id = ?
      `).run(unitCost, now, quotaPeriod.id);
    }

    await db.prepare(`
      INSERT INTO usage_ledger (id, user_id, feature, unit_cost, request_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(createID('ulg'), userID, feature, unitCost, createID('req'), now);
  }

  async function recordAIRequest(userID, feature, action, outcome, latencyMs, model = null, options = {}) {
    const unitCost = FEATURE_COSTS[feature] ?? FEATURE_COSTS.coachChat;
    const usage = normalizeProviderUsageMetadata(options.providerUsage ?? null);
    const provider = normalizeProviderKey(usage?.provider ?? options.provider);
    const providerCostEstimate = usage
      ? estimateProviderUsageCostUSD(provider, usage)
      : null;
    const requestFormat = normalizeRequestFormat(options.requestFormat);
    const retryCount = normalizeRetryCount(options.retryCount);
    const retryReason = normalizeRetryReason(options.retryReason);
    await db.prepare(`
      INSERT INTO ai_requests (
        id, user_id, feature, provider, model, action, outcome, latency_ms,
        input_tokens, output_tokens, total_tokens, cached_input_tokens, reasoning_tokens,
        provider_cost_estimate, provider_usage_json, request_format, retry_count, retry_reason, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      createID('air'),
      userID,
      feature,
      provider === 'unknown' ? usage?.provider ?? options.provider ?? null : provider,
      typeof model === 'string' && model.trim().length > 0 ? model : config.geminiModel,
      action,
      outcome,
      latencyMs,
      usage?.inputTokens ?? null,
      usage?.outputTokens ?? null,
      usage?.totalTokens ?? null,
      usage?.cachedInputTokens ?? null,
      usage?.reasoningTokens ?? null,
      providerCostEstimate ?? estimateUSDCostForUnits(unitCost),
      usage ? JSON.stringify(usage) : null,
      requestFormat,
      retryCount,
      retryReason,
      isoNow()
    );
  }

  function normalizeProviderUsageMetadata(usage) {
    if (!usage || typeof usage !== 'object' || Array.isArray(usage)) {
      return null;
    }

    const normalized = {
      provider: typeof usage.provider === 'string' && usage.provider.trim().length > 0
        ? usage.provider.trim()
        : null,
      inputTokens: normalizeInteger(usage.inputTokens),
      outputTokens: normalizeInteger(usage.outputTokens),
      totalTokens: normalizeInteger(usage.totalTokens),
      cachedInputTokens: normalizeInteger(usage.cachedInputTokens),
      reasoningTokens: normalizeInteger(usage.reasoningTokens),
      raw: usage.raw && typeof usage.raw === 'object' && !Array.isArray(usage.raw)
        ? usage.raw
        : null
    };

    if (
      !normalized.provider
      && normalized.inputTokens == null
      && normalized.outputTokens == null
      && normalized.totalTokens == null
      && normalized.cachedInputTokens == null
      && normalized.reasoningTokens == null
      && !normalized.raw
    ) {
      return null;
    }

    return normalized;
  }

  function normalizeInteger(value) {
    if (!Number.isFinite(value)) {
      return null;
    }
    return Math.max(0, Math.round(value));
  }

  function normalizeRetryCount(value) {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }

  function normalizeRetryReason(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : null;
  }

  function normalizeRequestFormat(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : null;
  }

  async function buildBillingPayload(userID, installationID, appAccountToken, now) {
    const subscription = await ensureSubscription(userID, now);
    const quotaPeriod = await ensureQuotaPeriod(userID, subscription.plan, now);

    return {
      accountSnapshot: {
        installationID,
        appAccountToken,
        identityMode: 'signInWithApple',
        backendEnvironment: config.environment,
        lastSyncedAt: now
      },
      entitlementSnapshot: {
        plan: subscription.plan,
        status: subscription.status,
        sourceDescription: subscription.source ?? 'system',
        renewalDate: subscription.renews_at,
        lastValidatedAt: now
      },
      quotaSnapshot: await buildQuotaSnapshot(quotaPeriod),
      availableProducts: PRODUCT_DEFINITIONS,
      syncState: 'syncedWithBackend',
      syncedAt: now
    };
  }

  async function buildQuotaSnapshot(quotaPeriod) {
    return {
      periodStart: quotaPeriod.period_start,
      periodEnd: quotaPeriod.period_end,
      usedUnits: quotaPeriod.units_used,
      bonusUnits: quotaPeriod.bonus_units ?? 0,
      featureUsageCounts: await featureUsageCountsForUser(quotaPeriod.user_id, quotaPeriod.period_start, quotaPeriod.period_end),
      lastUpdatedAt: quotaPeriod.updated_at
    };
  }

  async function featureUsageCountsForUser(userID, periodStart, periodEnd) {
    const rows = await db.prepare(`
      SELECT feature, COUNT(*) AS count
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ? AND created_at < ?
      GROUP BY feature
    `).all(userID, periodStart, periodEnd);

    return Object.fromEntries(rows.map((row) => [row.feature, row.count]));
  }

  function effectiveQuotaLimit(quotaPeriod) {
    if (quotaPeriod.unit_limit == null) {
      return null;
    }

    return Math.max(quotaPeriod.unit_limit + (quotaPeriod.bonus_units ?? 0), 0);
  }

  function estimateUSDCostForUnits(unitsUsed) {
    return roundCurrency(unitsUsed * UNIT_ECONOMICS.estimatedUSDPerUnit);
  }

  function estimateNetRevenue(priceUSD, share) {
    return roundCurrency(priceUSD * share);
  }

  function roundCurrency(value) {
    return Math.round(value * 100) / 100;
  }

  function roundSmallAmount(value) {
    return Math.round(value * 10000) / 10000;
  }

  function buildMonetizationPolicySummary() {
    return {
      primaryPlan: {
        plan: 'pro',
        priceDisplay: PLAN_PRICING.pro.priceDisplay,
        monthlyPriceUSD: PLAN_PRICING.pro.monthlyPriceUSD,
        monthlyAIUnits: PLAN_LIMITS.pro,
        targetAverageAICostUSD: UNIT_ECONOMICS.targetAveragePaidAICostUSD,
        softBufferAICostUSD: UNIT_ECONOMICS.softBufferPaidAICostUSD,
        hardCeilingAICostUSD: UNIT_ECONOMICS.hardCeilingPaidAICostUSD,
        estimatedNetRevenueUSD: {
          smallBusiness: estimateNetRevenue(PLAN_PRICING.pro.monthlyPriceUSD, UNIT_ECONOMICS.smallBusinessNetRevenueShare),
          standardYearOne: estimateNetRevenue(PLAN_PRICING.pro.monthlyPriceUSD, UNIT_ECONOMICS.standardYearOneNetRevenueShare)
        }
      },
      featureCosts: FEATURE_COSTS,
      estimatedUSDPerUnit: roundSmallAmount(UNIT_ECONOMICS.estimatedUSDPerUnit)
    };
  }

  function summarizeQuotaPeriod(quotaPeriod) {
    const effectiveLimit = effectiveQuotaLimit(quotaPeriod);
    return {
      periodStart: quotaPeriod.period_start,
      periodEnd: quotaPeriod.period_end,
      baseUnitLimit: quotaPeriod.unit_limit,
      bonusUnits: quotaPeriod.bonus_units ?? 0,
      effectiveUnitLimit: effectiveLimit,
      usedUnits: quotaPeriod.units_used,
      remainingUnits: effectiveLimit == null ? null : Math.max(effectiveLimit - quotaPeriod.units_used, 0),
      utilizationRatio: effectiveLimit && effectiveLimit > 0
        ? Math.min(quotaPeriod.units_used / effectiveLimit, 1)
        : null,
      estimatedAICostUSD: estimateUSDCostForUnits(quotaPeriod.units_used),
      updatedAt: quotaPeriod.updated_at
    };
  }

  async function buildUsageAnalytics(userID, latestQuotaPeriod) {
    const trailingWindowStart = buildTrailingWindowStart(30);

    const trailingUsage = await db.prepare(`
      SELECT
        COUNT(*) AS request_count,
        COALESCE(SUM(unit_cost), 0) AS units_used
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, trailingWindowStart);

    const trailingOutcomes = await db.prepare(`
      SELECT outcome, COUNT(*) AS count
      FROM ai_requests
      WHERE user_id = ? AND created_at >= ?
      GROUP BY outcome
    `).all(userID, trailingWindowStart);

    const trailingFeatures = await db.prepare(`
      SELECT feature, COUNT(*) AS request_count, COALESCE(SUM(unit_cost), 0) AS units_used
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
      GROUP BY feature
      ORDER BY units_used DESC, request_count DESC
    `).all(userID, trailingWindowStart);

    const trailingAIRequests = await db.prepare(`
      SELECT
        feature,
        provider,
        model,
        outcome,
        latency_ms,
        request_format,
        retry_count,
        retry_reason,
        input_tokens,
        output_tokens,
        total_tokens,
        cached_input_tokens,
        reasoning_tokens
      FROM ai_requests
      WHERE user_id = ? AND created_at >= ?
      ORDER BY created_at DESC
    `).all(userID, trailingWindowStart);

    const currentPeriodSummary = latestQuotaPeriod ? summarizeQuotaPeriod(latestQuotaPeriod) : null;
    const telemetry = summarizeTelemetryAnalytics(trailingAIRequests);

    return {
      currentPeriod: currentPeriodSummary,
      trailing30Days: {
        requestCount: trailingUsage?.request_count ?? 0,
        unitsUsed: trailingUsage?.units_used ?? 0,
        estimatedAICostUSD: estimateUSDCostForUnits(trailingUsage?.units_used ?? 0),
        averageDailyUnits: Math.round((trailingUsage?.units_used ?? 0) / 30),
        outcomes: Object.fromEntries(trailingOutcomes.map((row) => [row.outcome, row.count])),
        topFeatures: trailingFeatures.map((row) => ({
          feature: row.feature,
          requestCount: row.request_count,
          unitsUsed: row.units_used,
          estimatedAICostUSD: estimateUSDCostForUnits(row.units_used)
        })),
        telemetry
      }
    };
  }

  async function buildGlobalUsageAnalytics(days = 30) {
    const windowDays = normalizeAnalyticsWindowDays(days);
    const trailingWindowStart = buildTrailingWindowStart(windowDays);

    const usageTotals = await db.prepare(`
      SELECT
        COUNT(*) AS request_count,
        COALESCE(SUM(unit_cost), 0) AS units_used,
        COUNT(DISTINCT user_id) AS active_user_count
      FROM usage_ledger
      WHERE created_at >= ?
    `).get(trailingWindowStart);

    const outcomeRows = await db.prepare(`
      SELECT outcome, COUNT(*) AS count
      FROM ai_requests
      WHERE created_at >= ?
      GROUP BY outcome
    `).all(trailingWindowStart);

    const featureRows = await db.prepare(`
      SELECT feature, COUNT(*) AS request_count, COALESCE(SUM(unit_cost), 0) AS units_used
      FROM usage_ledger
      WHERE created_at >= ?
      GROUP BY feature
      ORDER BY units_used DESC, request_count DESC
    `).all(trailingWindowStart);

    const planRows = await db.prepare(`
      SELECT
        COALESCE(subscriptions.plan, 'free') AS plan,
        COUNT(*) AS request_count,
        COALESCE(SUM(usage_ledger.unit_cost), 0) AS units_used,
        COUNT(DISTINCT usage_ledger.user_id) AS active_user_count
      FROM usage_ledger
      LEFT JOIN subscriptions ON subscriptions.user_id = usage_ledger.user_id
      WHERE usage_ledger.created_at >= ?
      GROUP BY COALESCE(subscriptions.plan, 'free')
      ORDER BY units_used DESC, request_count DESC
    `).all(trailingWindowStart);

    const topUserRows = await db.prepare(`
      SELECT
        usage_ledger.user_id,
        COALESCE(subscriptions.plan, 'free') AS plan,
        COALESCE(subscriptions.status, 'unknown') AS subscription_status,
        COUNT(*) AS request_count,
        COALESCE(SUM(usage_ledger.unit_cost), 0) AS units_used,
        MAX(usage_ledger.created_at) AS last_used_at
      FROM usage_ledger
      LEFT JOIN subscriptions ON subscriptions.user_id = usage_ledger.user_id
      WHERE usage_ledger.created_at >= ?
      GROUP BY
        usage_ledger.user_id,
        COALESCE(subscriptions.plan, 'free'),
        COALESCE(subscriptions.status, 'unknown')
      ORDER BY units_used DESC, request_count DESC, last_used_at DESC
      LIMIT 25
    `).all(trailingWindowStart);

    const trailingAIRequests = await db.prepare(`
      SELECT
        user_id,
        feature,
        provider,
        model,
        outcome,
        latency_ms,
        request_format,
        retry_count,
        retry_reason,
        input_tokens,
        output_tokens,
        total_tokens,
        cached_input_tokens,
        reasoning_tokens
      FROM ai_requests
      WHERE created_at >= ?
      ORDER BY created_at DESC
    `).all(trailingWindowStart);

    const telemetry = summarizeTelemetryAnalytics(trailingAIRequests);
    const activeUserCount = usageTotals?.active_user_count ?? 0;

    return {
      windowDays,
      windowStart: trailingWindowStart,
      activeUserCount,
      requestCount: usageTotals?.request_count ?? 0,
      unitsUsed: usageTotals?.units_used ?? 0,
      estimatedAICostUSD: estimateUSDCostForUnits(usageTotals?.units_used ?? 0),
      averageRequestsPerActiveUser: activeUserCount > 0
        ? roundSmallAmount((usageTotals?.request_count ?? 0) / activeUserCount)
        : null,
      averageUnitsPerActiveUser: activeUserCount > 0
        ? roundSmallAmount((usageTotals?.units_used ?? 0) / activeUserCount)
        : null,
      estimatedAICostPerActiveUserUSD: activeUserCount > 0
        ? roundCurrency((usageTotals?.units_used ?? 0) * UNIT_ECONOMICS.estimatedUSDPerUnit / activeUserCount)
        : null,
      outcomes: Object.fromEntries(outcomeRows.map((row) => [row.outcome, row.count])),
      byPlan: planRows.map((row) => ({
        plan: row.plan,
        activeUserCount: row.active_user_count,
        requestCount: row.request_count,
        unitsUsed: row.units_used,
        averageRequestsPerActiveUser: row.active_user_count > 0
          ? roundSmallAmount(row.request_count / row.active_user_count)
          : null,
        averageUnitsPerActiveUser: row.active_user_count > 0
          ? roundSmallAmount(row.units_used / row.active_user_count)
          : null,
        estimatedAICostUSD: estimateUSDCostForUnits(row.units_used)
      })),
      topFeatures: featureRows.map((row) => ({
        feature: row.feature,
        requestCount: row.request_count,
        unitsUsed: row.units_used,
        estimatedAICostUSD: estimateUSDCostForUnits(row.units_used)
      })),
      topUsers: topUserRows.map((row) => ({
        userID: row.user_id,
        plan: row.plan,
        subscriptionStatus: row.subscription_status,
        requestCount: row.request_count,
        unitsUsed: row.units_used,
        estimatedAICostUSD: estimateUSDCostForUnits(row.units_used),
        lastUsedAt: row.last_used_at
      })),
      telemetry: {
        ...telemetry,
        estimatedTrackedAICostPerActiveUserUSD: activeUserCount > 0 && telemetry.estimatedTrackedAICostUSD != null
          ? roundSmallAmount(telemetry.estimatedTrackedAICostUSD / activeUserCount)
          : null
      }
    };
  }

  function summarizeTelemetryAnalytics(aiRequests) {
    const successfulRequests = normalizeArray(aiRequests).filter((row) => row.outcome === 'success');
    const trackedRequests = successfulRequests.filter(hasUsageTelemetry);
    const retriedRequests = successfulRequests.filter((row) => normalizeRetryCount(row.retry_count) > 0);
    const requestFormatCounts = countValues(successfulRequests.map((row) => row.request_format ?? 'unknown'));
    const retryReasonCounts = countValues(
      retriedRequests.map((row) => row.retry_reason ?? 'unknown')
    );

    const byFeature = new Map();
    const byProviderModel = new Map();

    for (const request of successfulRequests) {
      const featureKey = request.feature ?? 'unknown';
      const provider = normalizeProviderKey(request.provider, request.model);
      const model = typeof request.model === 'string' && request.model.trim().length > 0
        ? request.model.trim()
        : 'unknown';
      const usage = normalizeTelemetryRow(request);
      const hasTelemetry = hasUsageTelemetry(request);
      const estimatedRealCostUSD = estimateProviderUsageCostUSD(provider, usage);
      const featureUnits = FEATURE_COSTS[featureKey] ?? FEATURE_COSTS.coachChat;

      accumulateTelemetryBucket(
        byFeature,
        featureKey,
        request,
        usage,
        hasTelemetry,
        estimatedRealCostUSD,
        featureUnits,
        { feature: featureKey }
      );

      const providerModelKey = `${provider}::${model}`;
      accumulateTelemetryBucket(
        byProviderModel,
        providerModelKey,
        request,
        usage,
        hasTelemetry,
        estimatedRealCostUSD,
        featureUnits,
        { provider, model }
      );
    }

    const trackedEstimatedCostUSD = trackedRequests.reduce((sum, request) => {
      const usage = normalizeTelemetryRow(request);
      return sum + (estimateProviderUsageCostUSD(normalizeProviderKey(request.provider, request.model), usage) ?? 0);
    }, 0);

    return {
      pricing: buildTokenPricingSummary(),
      successfulRequestCount: successfulRequests.length,
      trackedRequestCount: trackedRequests.length,
      retriedRequestCount: retriedRequests.length,
      retryRate: successfulRequests.length > 0
        ? roundSmallAmount(retriedRequests.length / successfulRequests.length)
        : null,
      requestFormats: requestFormatCounts,
      retryReasons: retryReasonCounts,
      telemetryCoverageRatio: successfulRequests.length > 0
        ? roundSmallAmount(trackedRequests.length / successfulRequests.length)
        : null,
      estimatedTrackedAICostUSD: trackedRequests.length > 0
        ? roundCurrency(trackedEstimatedCostUSD)
        : null,
      averageTrackedCostPerRequestUSD: trackedRequests.length > 0
        ? roundSmallAmount(trackedEstimatedCostUSD / trackedRequests.length)
        : null,
      byFeature: finalizeTelemetryBuckets(byFeature, ['estimatedTrackedCostUSD', 'requestCount']),
      byProviderModel: finalizeTelemetryBuckets(byProviderModel, ['estimatedTrackedCostUSD', 'requestCount'])
    };
  }

  function accumulateTelemetryBucket(map, key, request, usage, hasTelemetry, estimatedRealCostUSD, featureUnits, identity) {
    const existing = map.get(key) ?? {
      ...identity,
      requestCount: 0,
      trackedRequestCount: 0,
      retriedRequestCount: 0,
      totalLatencyMs: 0,
      latencySampleCount: 0,
      unitsUsedEstimate: 0,
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      cachedInputTokens: 0,
      reasoningTokens: 0,
      estimatedTrackedCostUSD: 0
    };

    existing.requestCount += 1;
    if (Number.isFinite(request.latency_ms)) {
      existing.totalLatencyMs += request.latency_ms;
      existing.latencySampleCount += 1;
    }
    existing.unitsUsedEstimate += featureUnits;
    existing.inputTokens += usage.inputTokens ?? 0;
    existing.outputTokens += usage.outputTokens ?? 0;
    existing.totalTokens += usage.totalTokens ?? 0;
    existing.cachedInputTokens += usage.cachedInputTokens ?? 0;
    existing.reasoningTokens += usage.reasoningTokens ?? 0;

    if (normalizeRetryCount(request.retry_count) > 0) {
      existing.retriedRequestCount += 1;
    }

    if (hasTelemetry) {
      existing.trackedRequestCount += 1;
      existing.estimatedTrackedCostUSD += estimatedRealCostUSD ?? 0;
    }

    map.set(key, existing);
  }

  function finalizeTelemetryBuckets(map, sortKeys = []) {
    return Array.from(map.values())
      .map((entry) => ({
        ...entry,
        averageLatencyMs: entry.latencySampleCount > 0
          ? Math.round(entry.totalLatencyMs / entry.latencySampleCount)
          : null,
        estimatedTrackedCostUSD: entry.trackedRequestCount > 0
          ? roundCurrency(entry.estimatedTrackedCostUSD)
          : null,
        averageTrackedCostPerRequestUSD: entry.trackedRequestCount > 0
          ? roundSmallAmount(entry.estimatedTrackedCostUSD / entry.trackedRequestCount)
          : null,
        averageInputTokens: entry.trackedRequestCount > 0
          ? Math.round(entry.inputTokens / entry.trackedRequestCount)
          : null,
        averageOutputTokens: entry.trackedRequestCount > 0
          ? Math.round(entry.outputTokens / entry.trackedRequestCount)
          : null,
        averageTotalTokens: entry.trackedRequestCount > 0
          ? Math.round(entry.totalTokens / entry.trackedRequestCount)
          : null,
        averageCachedInputTokens: entry.trackedRequestCount > 0
          ? Math.round(entry.cachedInputTokens / entry.trackedRequestCount)
          : null,
        averageReasoningTokens: entry.trackedRequestCount > 0
          ? Math.round(entry.reasoningTokens / entry.trackedRequestCount)
          : null,
        telemetryCoverageRatio: entry.requestCount > 0
          ? roundSmallAmount(entry.trackedRequestCount / entry.requestCount)
          : null,
        retryRate: entry.requestCount > 0
          ? roundSmallAmount(entry.retriedRequestCount / entry.requestCount)
          : null
      }))
      .sort((left, right) => compareTelemetryEntries(left, right, sortKeys));
  }

  function compareTelemetryEntries(left, right, sortKeys) {
    for (const key of sortKeys) {
      const leftValue = left[key] ?? -1;
      const rightValue = right[key] ?? -1;
      if (rightValue !== leftValue) {
        return rightValue - leftValue;
      }
    }

    return String(left.feature ?? left.model ?? '').localeCompare(String(right.feature ?? right.model ?? ''));
  }

  function countValues(values) {
    const counts = new Map();
    for (const value of normalizeArray(values)) {
      const key = typeof value === 'string' && value.trim().length > 0 ? value.trim() : 'unknown';
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }

    return Object.fromEntries(
      Array.from(counts.entries()).sort((left, right) => {
        if (right[1] !== left[1]) {
          return right[1] - left[1];
        }
        return left[0].localeCompare(right[0]);
      })
    );
  }

  function buildTokenPricingSummary() {
    return {
      openai: normalizePricingSummary(config.aiTokenPricing?.openai),
      gemini: normalizePricingSummary(config.aiTokenPricing?.gemini)
    };
  }

  function normalizePricingSummary(pricing) {
    if (!pricing) {
      return null;
    }

    return {
      inputUSDPer1M: normalizePricingValue(pricing.inputUSDPer1M),
      outputUSDPer1M: normalizePricingValue(pricing.outputUSDPer1M),
      cachedInputUSDPer1M: normalizePricingValue(pricing.cachedInputUSDPer1M)
    };
  }

  function normalizePricingValue(value) {
    return Number.isFinite(value) ? roundSmallAmount(value) : null;
  }

  function estimateProviderUsageCostUSD(provider, usage) {
    const pricing = config.aiTokenPricing?.[provider];
    if (!pricing) {
      return null;
    }

    const inputRate = Number.isFinite(pricing.inputUSDPer1M) ? pricing.inputUSDPer1M : null;
    const outputRate = Number.isFinite(pricing.outputUSDPer1M) ? pricing.outputUSDPer1M : null;
    const cachedRate = Number.isFinite(pricing.cachedInputUSDPer1M)
      ? pricing.cachedInputUSDPer1M
      : inputRate;

    if (inputRate == null || outputRate == null) {
      return null;
    }

    const cachedInputTokens = usage.cachedInputTokens ?? 0;
    const totalInputTokens = usage.inputTokens ?? 0;
    const uncachedInputTokens = Math.max(totalInputTokens - cachedInputTokens, 0);
    const outputTokens = usage.outputTokens ?? 0;

    const estimatedCost =
      ((uncachedInputTokens / 1_000_000) * inputRate)
      + ((cachedInputTokens / 1_000_000) * (cachedRate ?? inputRate))
      + ((outputTokens / 1_000_000) * outputRate);

    return roundSmallAmount(estimatedCost);
  }

  function normalizeTelemetryRow(row) {
    return {
      inputTokens: normalizeInteger(row.input_tokens),
      outputTokens: normalizeInteger(row.output_tokens),
      totalTokens: normalizeInteger(row.total_tokens),
      cachedInputTokens: normalizeInteger(row.cached_input_tokens),
      reasoningTokens: normalizeInteger(row.reasoning_tokens)
    };
  }

  function hasUsageTelemetry(row) {
    return normalizeInteger(row.input_tokens) != null
      || normalizeInteger(row.output_tokens) != null
      || normalizeInteger(row.total_tokens) != null
      || normalizeInteger(row.cached_input_tokens) != null
      || normalizeInteger(row.reasoning_tokens) != null;
  }

  function normalizeProviderKey(value, model = null) {
    const normalized = typeof value === 'string' ? value.trim().toLowerCase() : '';
    if (normalized === 'openai' || normalized === 'gemini') {
      return normalized;
    }

    const normalizedModel = typeof model === 'string' ? model.trim().toLowerCase() : '';
    if (
      normalizedModel.startsWith('gpt-')
      || normalizedModel.startsWith('o1')
      || normalizedModel.startsWith('o3')
      || normalizedModel.startsWith('o4')
    ) {
      return 'openai';
    }
    if (normalizedModel.startsWith('gemini')) {
      return 'gemini';
    }

    return 'unknown';
  }

  function normalizeArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function buildTrailingWindowStart(days) {
    return new Date(Date.now() - (days * 24 * 60 * 60 * 1000)).toISOString();
  }

  function normalizeAnalyticsWindowDays(days) {
    if (!Number.isFinite(days)) {
      return 30;
    }

    return Math.min(Math.max(Math.round(days), 1), 90);
  }

  function normalizeAdminReason(reason) {
    const normalized = typeof reason === 'string' ? reason.trim() : '';
    return normalized.length > 0 ? normalized : null;
  }

  async function applyQuotaAdjustment({ userID, quotaPeriod, unitDelta, reason, createdBy }, now) {
    const currentBonusUnits = quotaPeriod.bonus_units ?? 0;
    const nextBonusUnits = currentBonusUnits + unitDelta;
    const effectiveLimit = quotaPeriod.unit_limit == null ? null : Math.max(quotaPeriod.unit_limit + nextBonusUnits, 0);

    if (quotaPeriod.unit_limit != null && effectiveLimit < quotaPeriod.units_used) {
      throw new HttpError(400, {
        error: 'invalid_adjustment',
        message: 'Adjustment would reduce the effective limit below the user\'s existing usage.'
      });
    }

    await db.prepare(`
      UPDATE quota_periods
      SET bonus_units = ?, updated_at = ?
      WHERE id = ?
    `).run(nextBonusUnits, now, quotaPeriod.id);

    await recordAdminAdjustment({
      userID,
      quotaPeriodID: quotaPeriod.id,
      adjustmentType: unitDelta > 0 ? 'manual_credit' : 'manual_debit',
      unitDelta,
      previousUnitsUsed: quotaPeriod.units_used,
      newUnitsUsed: quotaPeriod.units_used,
      reason,
      createdBy
    }, now);

    return await db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  async function resetQuotaUsage({ userID, quotaPeriod, resetUsedUnitsTo, reason, createdBy }, now) {
    await db.prepare(`
      UPDATE quota_periods
      SET units_used = ?, updated_at = ?
      WHERE id = ?
    `).run(resetUsedUnitsTo, now, quotaPeriod.id);

    await recordAdminAdjustment({
      userID,
      quotaPeriodID: quotaPeriod.id,
      adjustmentType: 'quota_reset',
      unitDelta: 0,
      previousUnitsUsed: quotaPeriod.units_used,
      newUnitsUsed: resetUsedUnitsTo,
      reason,
      createdBy
    }, now);

    return await db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  async function recordAdminAdjustment({
    userID,
    quotaPeriodID,
    adjustmentType,
    unitDelta,
    previousUnitsUsed,
    newUnitsUsed,
    reason,
    createdBy
  }, now) {
    await db.prepare(`
      INSERT INTO admin_adjustments (
        id, user_id, quota_period_id, adjustment_type, unit_delta,
        previous_units_used, new_units_used, reason, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      createID('adj'),
      userID,
      quotaPeriodID,
      adjustmentType,
      unitDelta,
      previousUnitsUsed ?? null,
      newUnitsUsed ?? null,
      reason,
      createdBy ?? 'admin-api',
      now
    );
  }

  return {
    ensureQuotaPeriod,
    ensureQuotaAvailable,
    reserveQuotaUsage,
    releaseReservedQuotaUsage,
    recordUsage,
    recordAIRequest,
    buildBillingPayload,
    buildQuotaSnapshot,
    featureUsageCountsForUser,
    effectiveQuotaLimit,
    estimateUSDCostForUnits,
    buildMonetizationPolicySummary,
    summarizeQuotaPeriod,
    buildUsageAnalytics,
    buildGlobalUsageAnalytics,
    normalizeAdminReason,
    applyQuotaAdjustment,
    resetQuotaUsage,
    recordAdminAdjustment
  };
}
