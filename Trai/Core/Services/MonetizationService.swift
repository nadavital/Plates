import Foundation

@MainActor @Observable
final class MonetizationService {
    static let shared = MonetizationService()

    private enum DefaultsKey {
        static let entitlementSnapshot = "monetization.entitlementSnapshot.v1"
        static let quotaSnapshot = "monetization.quotaSnapshot.v1"
        static let transportMode = "monetization.transportMode.v1"
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let encoder = JSONEncoder()
    @ObservationIgnored
    private let decoder = JSONDecoder()

    private(set) var entitlementSnapshot: EntitlementSnapshot
    private(set) var quotaSnapshot: AIQuotaSnapshot
    private(set) var aiTransportMode: AITransportMode

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let now = Date()
        let defaultEntitlement = Self.defaultEntitlement(now: now)
        let defaultQuota = Self.defaultQuotaSnapshot(now: now)

        if let storedEntitlement = Self.decode(
            EntitlementSnapshot.self,
            forKey: DefaultsKey.entitlementSnapshot,
            using: defaults
        ) {
            entitlementSnapshot = storedEntitlement
        } else {
            entitlementSnapshot = defaultEntitlement
        }

        if let storedQuota = Self.decode(
            AIQuotaSnapshot.self,
            forKey: DefaultsKey.quotaSnapshot,
            using: defaults
        ) {
            quotaSnapshot = storedQuota
        } else {
            quotaSnapshot = defaultQuota
        }

        if let rawTransport = defaults.string(forKey: DefaultsKey.transportMode),
           let transport = AITransportMode(rawValue: rawTransport) {
            aiTransportMode = transport
        } else {
            aiTransportMode = .directGemini
        }

        refreshStateIfNeeded(now: now)
    }

    var currentPlan: SubscriptionPlan {
        entitlementSnapshot.plan
    }

    var currentStatus: SubscriptionStatus {
        entitlementSnapshot.status
    }

    var canAccessAIFeatures: Bool {
        entitlementSnapshot.canUsePaidAI
    }

    var currentPlanDisplayText: String {
        if currentPlan == .free {
            return currentPlan.displayName
        }
        return "\(currentPlan.displayName) • \(currentStatus.displayName)"
    }

    var aiAccessSummaryText: String {
        if canAccessAIFeatures {
            return "Included with your \(currentPlan.displayName) plan"
        }
        return "Upgrade to Trai Pro to unlock AI coaching, food analysis, and personalized plans."
    }

    var quotaSummaryText: String {
        guard let remaining = quotaSnapshot.remainingUnits(for: currentPlan),
              let limit = quotaSnapshot.effectiveUnitLimit(for: currentPlan) else {
            return "Unlimited during current development entitlement"
        }
        if quotaSnapshot.bonusUnits > 0 {
            return "\(remaining) of \(limit) AI units remaining this period (\(quotaSnapshot.bonusUnits) bonus)"
        }
        return "\(remaining) of \(limit) AI units remaining this period"
    }

    var nextResetDate: Date {
        quotaSnapshot.periodEnd
    }

    func refreshStateIfNeeded(now: Date = Date()) {
        if now >= quotaSnapshot.periodEnd {
            quotaSnapshot = Self.defaultQuotaSnapshot(now: now)
            persistQuotaSnapshot()
        }
    }

    func accessDecision(for feature: AIFeature, now: Date = Date()) -> AIAccessDecision {
        refreshStateIfNeeded(now: now)

        if currentPlan == .developer {
            return AIAccessDecision(isAllowed: true, reason: nil)
        }

        guard entitlementSnapshot.canUsePaidAI else {
            if currentPlan == .free {
                return AIAccessDecision(
                    isAllowed: false,
                    reason: "Trai Pro unlocks chat coaching, food analysis, and personalized plans."
                )
            }
            return AIAccessDecision(
                isAllowed: false,
                reason: "Your subscription is \(currentStatus.displayName.lowercased()). Renew or restore purchases to keep using AI features."
            )
        }

        guard let remaining = quotaSnapshot.remainingUnits(for: currentPlan) else {
            return AIAccessDecision(isAllowed: true, reason: nil)
        }

        if remaining < feature.costUnits {
            return AIAccessDecision(
                isAllowed: false,
                reason: "AI is temporarily unavailable for this account right now. Please try again later."
            )
        }

        return AIAccessDecision(isAllowed: true, reason: nil)
    }

    func recordSuccessfulAIRequest(_ feature: AIFeature, at now: Date = Date()) {
        refreshStateIfNeeded(now: now)
        quotaSnapshot.usedUnits += feature.costUnits
        quotaSnapshot.featureUsageCounts[feature.rawValue, default: 0] += 1
        quotaSnapshot.lastUpdatedAt = now
        persistQuotaSnapshot()
    }

    func applyRemoteState(
        entitlementSnapshot: EntitlementSnapshot,
        quotaSnapshot: AIQuotaSnapshot? = nil,
        transportMode: AITransportMode? = nil
    ) {
        self.entitlementSnapshot = entitlementSnapshot
        if let quotaSnapshot {
            self.quotaSnapshot = quotaSnapshot
        }
        if let transportMode {
            aiTransportMode = transportMode
            defaults.set(transportMode.rawValue, forKey: DefaultsKey.transportMode)
        }
        persistEntitlementSnapshot()
        persistQuotaSnapshot()
    }

    #if DEBUG
    func setDebugPlan(_ plan: SubscriptionPlan, status: SubscriptionStatus = .active) {
        let now = Date()
        entitlementSnapshot = EntitlementSnapshot(
            plan: plan,
            status: status,
            sourceDescription: "debug-local",
            renewalDate: nil,
            lastValidatedAt: now
        )
        persistEntitlementSnapshot()
        refreshStateIfNeeded(now: now)
    }

    func resetQuotaForDebug() {
        quotaSnapshot = Self.defaultQuotaSnapshot(now: Date())
        persistQuotaSnapshot()
    }
    #endif

    private func persistEntitlementSnapshot() {
        Self.encode(entitlementSnapshot, forKey: DefaultsKey.entitlementSnapshot, using: defaults, encoder: encoder)
    }

    private func persistQuotaSnapshot() {
        Self.encode(quotaSnapshot, forKey: DefaultsKey.quotaSnapshot, using: defaults, encoder: encoder)
    }

    private static func defaultEntitlement(now: Date) -> EntitlementSnapshot {
        #if DEBUG
        let defaultPlan: SubscriptionPlan = .developer
        #else
        let defaultPlan: SubscriptionPlan = .free
        #endif

        return EntitlementSnapshot(
            plan: defaultPlan,
            status: .active,
            sourceDescription: "local-default",
            renewalDate: nil,
            lastValidatedAt: now
        )
    }

    private static func defaultQuotaSnapshot(now: Date, calendar: Calendar = .current) -> AIQuotaSnapshot {
        let periodStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? now
        return AIQuotaSnapshot(
            periodStart: periodStart,
            periodEnd: periodEnd,
            usedUnits: 0,
            bonusUnits: 0,
            featureUsageCounts: [:],
            lastUpdatedAt: now
        )
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        using defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(
        _ value: T,
        forKey key: String,
        using defaults: UserDefaults,
        encoder: JSONEncoder
    ) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
