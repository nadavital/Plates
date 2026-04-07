import Foundation

enum SubscriptionPlan: String, Codable, CaseIterable, Identifiable {
    case developer
    case free
    case pro

    static let allCases: [SubscriptionPlan] = [.developer, .free, .pro]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .developer: "Developer"
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    var monthlyAIUnits: Int? {
        switch self {
        case .developer:
            nil
        case .free:
            0
        case .pro:
            1200
        }
    }

    var includesUnlimitedAI: Bool {
        monthlyAIUnits == nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let plan = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown subscription plan: \(rawValue)"
            )
        }

        self = plan
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SubscriptionStatus: String, Codable, CaseIterable {
    case active
    case trial
    case gracePeriod
    case billingRetry
    case expired
    case refunded
    case revoked

    var displayName: String {
        switch self {
        case .active: "Active"
        case .trial: "Trial"
        case .gracePeriod: "Grace Period"
        case .billingRetry: "Billing Retry"
        case .expired: "Expired"
        case .refunded: "Refunded"
        case .revoked: "Revoked"
        }
    }

    var isEntitledToPaidFeatures: Bool {
        switch self {
        case .active, .trial, .gracePeriod:
            true
        case .billingRetry, .expired, .refunded, .revoked:
            false
        }
    }
}

enum AITransportMode: String, Codable, CaseIterable {
    case directGemini
    case backendProxy

    var displayName: String {
        switch self {
        case .directGemini: "Direct Gemini"
        case .backendProxy: "Backend Proxy"
        }
    }
}

enum AIFeature: String, Codable, CaseIterable, Identifiable {
    case coachChat
    case agentCoachChat
    case agentToolFollowUp
    case foodPhotoAnalysis
    case foodRefinement
    case nutritionPlanGeneration
    case nutritionPlanRefinement
    case workoutPlanGeneration
    case workoutPlanRefinement
    case exerciseAnalysis
    case exercisePhotoAnalysis
    case memoryExtraction
    case nutritionAdvice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coachChat: "Coach Chat"
        case .agentCoachChat: "Agent Coach Chat"
        case .agentToolFollowUp: "Agent Tool Follow-up"
        case .foodPhotoAnalysis: "Food Photo Analysis"
        case .foodRefinement: "Food Refinement"
        case .nutritionPlanGeneration: "Nutrition Plan Generation"
        case .nutritionPlanRefinement: "Nutrition Plan Refinement"
        case .workoutPlanGeneration: "Workout Plan Generation"
        case .workoutPlanRefinement: "Workout Plan Refinement"
        case .exerciseAnalysis: "Exercise Analysis"
        case .exercisePhotoAnalysis: "Exercise Photo Analysis"
        case .memoryExtraction: "Memory Extraction"
        case .nutritionAdvice: "Nutrition Advice"
        }
    }

    var costUnits: Int {
        switch self {
        case .coachChat:
            1
        case .agentCoachChat:
            3
        case .agentToolFollowUp:
            1
        case .foodPhotoAnalysis:
            6
        case .foodRefinement:
            2
        case .nutritionPlanGeneration:
            8
        case .nutritionPlanRefinement:
            4
        case .workoutPlanGeneration:
            8
        case .workoutPlanRefinement:
            4
        case .exerciseAnalysis:
            2
        case .exercisePhotoAnalysis:
            5
        case .memoryExtraction:
            2
        case .nutritionAdvice:
            2
        }
    }
}

struct EntitlementSnapshot: Codable, Equatable {
    var plan: SubscriptionPlan
    var status: SubscriptionStatus
    var sourceDescription: String
    var renewalDate: Date?
    var lastValidatedAt: Date

    var canUsePaidAI: Bool {
        if plan == .developer {
            return true
        }
        guard plan != .free else {
            return false
        }
        return status.isEntitledToPaidFeatures
    }
}

struct AIQuotaSnapshot: Codable, Equatable {
    var periodStart: Date
    var periodEnd: Date
    var usedUnits: Int
    var bonusUnits: Int
    var featureUsageCounts: [String: Int]
    var lastUpdatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case periodStart
        case periodEnd
        case usedUnits
        case bonusUnits
        case featureUsageCounts
        case lastUpdatedAt
    }

    init(
        periodStart: Date,
        periodEnd: Date,
        usedUnits: Int,
        bonusUnits: Int = 0,
        featureUsageCounts: [String: Int],
        lastUpdatedAt: Date
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.usedUnits = usedUnits
        self.bonusUnits = bonusUnits
        self.featureUsageCounts = featureUsageCounts
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periodStart = try container.decode(Date.self, forKey: .periodStart)
        periodEnd = try container.decode(Date.self, forKey: .periodEnd)
        usedUnits = try container.decode(Int.self, forKey: .usedUnits)
        bonusUnits = try container.decodeIfPresent(Int.self, forKey: .bonusUnits) ?? 0
        featureUsageCounts = try container.decode([String: Int].self, forKey: .featureUsageCounts)
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
    }

    func effectiveUnitLimit(for plan: SubscriptionPlan) -> Int? {
        guard let limit = plan.monthlyAIUnits else { return nil }
        return max(limit + bonusUnits, 0)
    }

    func remainingUnits(for plan: SubscriptionPlan) -> Int? {
        guard let limit = effectiveUnitLimit(for: plan) else { return nil }
        return max(limit - usedUnits, 0)
    }

    func utilizationRatio(for plan: SubscriptionPlan) -> Double? {
        guard let limit = effectiveUnitLimit(for: plan), limit > 0 else { return nil }
        return min(Double(usedUnits) / Double(limit), 1.0)
    }
}

struct AIAccessDecision: Equatable {
    var isAllowed: Bool
    var reason: String?
}
