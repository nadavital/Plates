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
  function ensureQuotaPeriod(userID, plan, now) {
    const date = new Date(now);
    const periodStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    const periodEnd = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
    const limit = PLAN_LIMITS[plan] ?? null;

    let period = db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE user_id = ? AND period_start = ? AND period_end = ?
    `).get(userID, periodStart.toISOString(), periodEnd.toISOString());

    if (!period) {
      db.prepare(`
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

      period = db.prepare(`
        SELECT *
        FROM quota_periods
        WHERE user_id = ? AND period_start = ? AND period_end = ?
      `).get(userID, periodStart.toISOString(), periodEnd.toISOString());
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
        error: 'quota_exhausted',
        message: 'AI is temporarily unavailable for this account right now.'
      });
    }
  }

  function reserveQuotaUsage(quotaPeriod, unitCost) {
    const now = isoNow();
    const result = db.prepare(`
      UPDATE quota_periods
      SET units_used = units_used + ?, updated_at = ?
      WHERE id = ?
        AND (
          unit_limit IS NULL
          OR (units_used + ?) <= (unit_limit + COALESCE(bonus_units, 0))
        )
    `).run(unitCost, now, quotaPeriod.id, unitCost);

    if (result.changes === 0) {
      const latestQuotaPeriod = db.prepare(`
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

    return db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  function releaseReservedQuotaUsage(quotaPeriod, unitCost) {
    const now = isoNow();
    db.prepare(`
      UPDATE quota_periods
      SET units_used = MAX(units_used - ?, 0), updated_at = ?
      WHERE id = ?
    `).run(unitCost, now, quotaPeriod.id);

    return db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  function recordUsage(userID, quotaPeriod, feature, unitCost, options = {}) {
    const incrementQuotaUnits = options.incrementQuotaUnits ?? true;
    const now = isoNow();

    if (incrementQuotaUnits) {
      db.prepare(`
        UPDATE quota_periods
        SET units_used = units_used + ?, updated_at = ?
        WHERE id = ?
      `).run(unitCost, now, quotaPeriod.id);
    }

    db.prepare(`
      INSERT INTO usage_ledger (id, user_id, feature, unit_cost, request_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(createID('ulg'), userID, feature, unitCost, createID('req'), now);
  }

  function recordAIRequest(userID, feature, action, outcome, latencyMs) {
    const unitCost = FEATURE_COSTS[feature] ?? FEATURE_COSTS.coachChat;
    db.prepare(`
      INSERT INTO ai_requests (id, user_id, feature, model, action, outcome, latency_ms, provider_cost_estimate, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      createID('air'),
      userID,
      feature,
      config.geminiModel,
      action,
      outcome,
      latencyMs,
      estimateUSDCostForUnits(unitCost),
      isoNow()
    );
  }

  function buildBillingPayload(userID, installationID, appAccountToken, now) {
    const subscription = ensureSubscription(userID, now);
    const quotaPeriod = ensureQuotaPeriod(userID, subscription.plan, now);

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
        sourceDescription: 'backend-bootstrap',
        renewalDate: subscription.renews_at,
        lastValidatedAt: now
      },
      quotaSnapshot: buildQuotaSnapshot(quotaPeriod),
      transportMode: 'backendProxy',
      availableProducts: PRODUCT_DEFINITIONS,
      syncState: 'syncedWithBackend',
      syncedAt: now
    };
  }

  function buildQuotaSnapshot(quotaPeriod) {
    return {
      periodStart: quotaPeriod.period_start,
      periodEnd: quotaPeriod.period_end,
      usedUnits: quotaPeriod.units_used,
      bonusUnits: quotaPeriod.bonus_units ?? 0,
      featureUsageCounts: featureUsageCountsForUser(quotaPeriod.user_id, quotaPeriod.period_start, quotaPeriod.period_end),
      lastUpdatedAt: quotaPeriod.updated_at
    };
  }

  function featureUsageCountsForUser(userID, periodStart, periodEnd) {
    const rows = db.prepare(`
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

  function buildUsageAnalytics(userID, latestQuotaPeriod) {
    const trailingWindowStart = new Date(Date.now() - (30 * 24 * 60 * 60 * 1000)).toISOString();

    const trailingUsage = db.prepare(`
      SELECT
        COUNT(*) AS request_count,
        COALESCE(SUM(unit_cost), 0) AS units_used
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
    `).get(userID, trailingWindowStart);

    const trailingOutcomes = db.prepare(`
      SELECT outcome, COUNT(*) AS count
      FROM ai_requests
      WHERE user_id = ? AND created_at >= ?
      GROUP BY outcome
    `).all(userID, trailingWindowStart);

    const trailingFeatures = db.prepare(`
      SELECT feature, COUNT(*) AS request_count, COALESCE(SUM(unit_cost), 0) AS units_used
      FROM usage_ledger
      WHERE user_id = ? AND created_at >= ?
      GROUP BY feature
      ORDER BY units_used DESC, request_count DESC
    `).all(userID, trailingWindowStart);

    const currentPeriodSummary = latestQuotaPeriod ? summarizeQuotaPeriod(latestQuotaPeriod) : null;

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
        }))
      }
    };
  }

  function normalizeAdminReason(reason) {
    const normalized = typeof reason === 'string' ? reason.trim() : '';
    return normalized.length > 0 ? normalized : null;
  }

  function applyQuotaAdjustment({ userID, quotaPeriod, unitDelta, reason, createdBy }, now) {
    const currentBonusUnits = quotaPeriod.bonus_units ?? 0;
    const nextBonusUnits = currentBonusUnits + unitDelta;
    const effectiveLimit = quotaPeriod.unit_limit == null ? null : Math.max(quotaPeriod.unit_limit + nextBonusUnits, 0);

    if (quotaPeriod.unit_limit != null && effectiveLimit < quotaPeriod.units_used) {
      throw new HttpError(400, {
        error: 'invalid_adjustment',
        message: 'Adjustment would reduce the effective limit below the user\'s existing usage.'
      });
    }

    db.prepare(`
      UPDATE quota_periods
      SET bonus_units = ?, updated_at = ?
      WHERE id = ?
    `).run(nextBonusUnits, now, quotaPeriod.id);

    recordAdminAdjustment({
      userID,
      quotaPeriodID: quotaPeriod.id,
      adjustmentType: unitDelta > 0 ? 'manual_credit' : 'manual_debit',
      unitDelta,
      previousUnitsUsed: quotaPeriod.units_used,
      newUnitsUsed: quotaPeriod.units_used,
      reason,
      createdBy
    }, now);

    return db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  function resetQuotaUsage({ userID, quotaPeriod, resetUsedUnitsTo, reason, createdBy }, now) {
    db.prepare(`
      UPDATE quota_periods
      SET units_used = ?, updated_at = ?
      WHERE id = ?
    `).run(resetUsedUnitsTo, now, quotaPeriod.id);

    recordAdminAdjustment({
      userID,
      quotaPeriodID: quotaPeriod.id,
      adjustmentType: 'quota_reset',
      unitDelta: 0,
      previousUnitsUsed: quotaPeriod.units_used,
      newUnitsUsed: resetUsedUnitsTo,
      reason,
      createdBy
    }, now);

    return db.prepare(`
      SELECT *
      FROM quota_periods
      WHERE id = ?
    `).get(quotaPeriod.id);
  }

  function recordAdminAdjustment({
    userID,
    quotaPeriodID,
    adjustmentType,
    unitDelta,
    previousUnitsUsed,
    newUnitsUsed,
    reason,
    createdBy
  }, now) {
    db.prepare(`
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
    normalizeAdminReason,
    applyQuotaAdjustment,
    resetQuotaUsage,
    recordAdminAdjustment
  };
}
