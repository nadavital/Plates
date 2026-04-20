import Foundation

enum FoodMemoryKind: String, Codable, Sendable {
    case food
    case meal
}

enum FoodMemoryStatus: String, Codable, Sendable {
    case candidate
    case confirmed
    case retired
    case merged
}

enum FoodMemoryResolutionState: String, Codable, Sendable {
    case unresolved
    case queued
    case matched
    case createdCandidate
    case rejected
}

enum AcceptedFoodSource: String, Codable, Sendable {
    case camera
    case photo
    case description
    case manual
    case memorySuggestion
    case chat
    case appIntent
    case imported
}

enum FoodAnalysisConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

enum MealTimeBucket: String, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case lateNight
    case snack
}

enum FoodComponentRole: String, Codable, Sendable {
    case protein
    case carb
    case fat
    case vegetable
    case fruit
    case sauce
    case drink
    case mixed
    case other
}

enum FoodComponentSource: String, Codable, Sendable {
    case ai
    case user
    case derived
}

enum LoggedFoodComponentStatus: String, Codable, Sendable {
    case active
    case removed
}

struct AcceptedFoodSnapshot: Codable, Sendable {
    let version: Int
    let source: AcceptedFoodSource
    let kind: FoodMemoryKind
    let displayName: String
    let emoji: String?
    let normalizedDisplayName: String
    let nameAliases: [String]
    let mealLabel: String?
    let servingText: String?
    let servingQuantity: Double?
    let servingUnit: String?
    let totalCalories: Int
    let totalProteinGrams: Double
    let totalCarbsGrams: Double
    let totalFatGrams: Double
    let totalFiberGrams: Double?
    let totalSugarGrams: Double?
    let components: [AcceptedFoodComponent]
    let notes: String?
    let confidence: FoodAnalysisConfidence?
    let loggedAt: Date
    let mealTimeBucket: MealTimeBucket
    let weekdayBucket: Int
    let userEditedFields: [String]
    let wasUserEdited: Bool

    private enum CodingKeys: String, CodingKey {
        case version
        case source
        case kind
        case displayName
        case emoji
        case normalizedDisplayName
        case nameAliases
        case mealLabel
        case servingText
        case servingQuantity
        case servingUnit
        case totalCalories
        case totalProteinGrams
        case totalCarbsGrams
        case totalFatGrams
        case totalFiberGrams
        case totalSugarGrams
        case components
        case notes
        case confidence
        case loggedAt
        case mealTimeBucket
        case weekdayBucket
        case userEditedFields
        case wasUserEdited
    }

    init(
        version: Int,
        source: AcceptedFoodSource,
        kind: FoodMemoryKind,
        displayName: String,
        emoji: String? = nil,
        normalizedDisplayName: String,
        nameAliases: [String],
        mealLabel: String?,
        servingText: String?,
        servingQuantity: Double?,
        servingUnit: String?,
        totalCalories: Int,
        totalProteinGrams: Double,
        totalCarbsGrams: Double,
        totalFatGrams: Double,
        totalFiberGrams: Double?,
        totalSugarGrams: Double?,
        components: [AcceptedFoodComponent],
        notes: String?,
        confidence: FoodAnalysisConfidence?,
        loggedAt: Date,
        mealTimeBucket: MealTimeBucket,
        weekdayBucket: Int,
        userEditedFields: [String],
        wasUserEdited: Bool
    ) {
        self.version = version
        self.source = source
        self.kind = kind
        self.displayName = displayName
        self.emoji = emoji?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.normalizedDisplayName = normalizedDisplayName
        self.nameAliases = nameAliases.isEmpty ? [normalizedDisplayName].filter { !$0.isEmpty } : nameAliases
        self.mealLabel = mealLabel
        self.servingText = servingText
        self.servingQuantity = servingQuantity
        self.servingUnit = servingUnit
        self.totalCalories = totalCalories
        self.totalProteinGrams = totalProteinGrams
        self.totalCarbsGrams = totalCarbsGrams
        self.totalFatGrams = totalFatGrams
        self.totalFiberGrams = totalFiberGrams
        self.totalSugarGrams = totalSugarGrams
        self.components = components
        self.notes = notes
        self.confidence = confidence
        self.loggedAt = loggedAt
        self.mealTimeBucket = mealTimeBucket
        self.weekdayBucket = weekdayBucket
        self.userEditedFields = userEditedFields
        self.wasUserEdited = wasUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        source = try container.decode(AcceptedFoodSource.self, forKey: .source)
        kind = try container.decode(FoodMemoryKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        normalizedDisplayName = try container.decode(String.self, forKey: .normalizedDisplayName)
        let decodedAliases = try container.decodeIfPresent([String].self, forKey: .nameAliases) ?? []
        nameAliases = decodedAliases.isEmpty ? [normalizedDisplayName].filter { !$0.isEmpty } : decodedAliases
        mealLabel = try container.decodeIfPresent(String.self, forKey: .mealLabel)
        servingText = try container.decodeIfPresent(String.self, forKey: .servingText)
        servingQuantity = try container.decodeIfPresent(Double.self, forKey: .servingQuantity)
        servingUnit = try container.decodeIfPresent(String.self, forKey: .servingUnit)
        totalCalories = try container.decode(Int.self, forKey: .totalCalories)
        totalProteinGrams = try container.decode(Double.self, forKey: .totalProteinGrams)
        totalCarbsGrams = try container.decode(Double.self, forKey: .totalCarbsGrams)
        totalFatGrams = try container.decode(Double.self, forKey: .totalFatGrams)
        totalFiberGrams = try container.decodeIfPresent(Double.self, forKey: .totalFiberGrams)
        totalSugarGrams = try container.decodeIfPresent(Double.self, forKey: .totalSugarGrams)
        components = try container.decode([AcceptedFoodComponent].self, forKey: .components)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        confidence = try container.decodeIfPresent(FoodAnalysisConfidence.self, forKey: .confidence)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        mealTimeBucket = try container.decode(MealTimeBucket.self, forKey: .mealTimeBucket)
        weekdayBucket = try container.decode(Int.self, forKey: .weekdayBucket)
        userEditedFields = try container.decodeIfPresent([String].self, forKey: .userEditedFields) ?? []
        wasUserEdited = try container.decodeIfPresent(Bool.self, forKey: .wasUserEdited) ?? false
    }
}

struct AcceptedFoodComponent: Codable, Sendable, Hashable {
    let id: String
    let displayName: String
    let normalizedName: String
    let role: FoodComponentRole
    let quantity: Double?
    let unit: String?
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let preparation: String?
    let confidence: FoodAnalysisConfidence?
    let source: FoodComponentSource
}

struct LoggedFoodComponent: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let originalComponentID: String?
    var displayName: String
    var normalizedName: String
    var role: FoodComponentRole
    var quantity: Double?
    var unit: String?
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double?
    var sugarGrams: Double?
    var preparation: String?
    var confidence: FoodAnalysisConfidence?
    var source: FoodComponentSource
    var fractionOfOriginal: Double
    var status: LoggedFoodComponentStatus

    var isActive: Bool {
        status == .active && fractionOfOriginal > 0
    }

    var effectiveCalories: Double {
        Double(calories) * clampedFraction
    }

    var effectiveProteinGrams: Double {
        proteinGrams * clampedFraction
    }

    var effectiveCarbsGrams: Double {
        carbsGrams * clampedFraction
    }

    var effectiveFatGrams: Double {
        fatGrams * clampedFraction
    }

    var effectiveFiberGrams: Double? {
        guard let fiberGrams else { return nil }
        return fiberGrams * clampedFraction
    }

    var effectiveSugarGrams: Double? {
        guard let sugarGrams else { return nil }
        return sugarGrams * clampedFraction
    }

    private var clampedFraction: Double {
        guard status == .active else { return 0 }
        return max(fractionOfOriginal, 0)
    }

    init(
        id: String,
        originalComponentID: String? = nil,
        displayName: String,
        normalizedName: String,
        role: FoodComponentRole,
        quantity: Double?,
        unit: String?,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double?,
        sugarGrams: Double?,
        preparation: String?,
        confidence: FoodAnalysisConfidence?,
        source: FoodComponentSource,
        fractionOfOriginal: Double = 1,
        status: LoggedFoodComponentStatus = .active
    ) {
        self.id = id
        self.originalComponentID = originalComponentID ?? id
        self.displayName = displayName
        self.normalizedName = normalizedName
        self.role = role
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.preparation = preparation
        self.confidence = confidence
        self.source = source
        self.fractionOfOriginal = fractionOfOriginal
        self.status = status
    }
}

extension LoggedFoodComponent {
    init(component: AcceptedFoodComponent) {
        self.init(
            id: component.id,
            originalComponentID: component.id,
            displayName: component.displayName,
            normalizedName: component.normalizedName,
            role: component.role,
            quantity: component.quantity,
            unit: component.unit,
            calories: component.calories,
            proteinGrams: component.proteinGrams,
            carbsGrams: component.carbsGrams,
            fatGrams: component.fatGrams,
            fiberGrams: component.fiberGrams,
            sugarGrams: component.sugarGrams,
            preparation: component.preparation,
            confidence: component.confidence,
            source: component.source
        )
    }
}

struct FoodMemoryAlias: Codable, Sendable, Hashable {
    let normalizedName: String
    let displayName: String
    let observationCount: Int
    let wasUserEdited: Bool
}

struct FoodMemoryNutritionProfile: Codable, Sendable {
    let medianCalories: Int
    let medianProteinGrams: Double
    let medianCarbsGrams: Double
    let medianFatGrams: Double
    let medianFiberGrams: Double?
    let medianSugarGrams: Double?
    let lowerCaloriesBound: Int
    let upperCaloriesBound: Int
    let lowerProteinBound: Double
    let upperProteinBound: Double
}

struct FoodMemoryServingProfile: Codable, Sendable {
    let commonServingText: String?
    let commonQuantity: Double?
    let commonUnit: String?
    let quantityVariance: Double?
}

struct FoodMemoryTimeProfile: Codable, Sendable {
    let hourCounts: [Int]
    let bucketCounts: [String: Int]
    let weekdayCount: Int
    let weekendCount: Int

    init(
        hourCounts: [Int],
        bucketCounts: [String: Int],
        weekdayCount: Int,
        weekendCount: Int
    ) {
        var normalizedHourCounts = Array(hourCounts.prefix(24))
        if normalizedHourCounts.count < 24 {
            normalizedHourCounts.append(contentsOf: repeatElement(0, count: 24 - normalizedHourCounts.count))
        }

        self.hourCounts = normalizedHourCounts
        self.bucketCounts = bucketCounts
        self.weekdayCount = weekdayCount
        self.weekendCount = weekendCount
    }
}

struct FoodMemoryComponentSummary: Codable, Sendable, Hashable {
    let normalizedName: String
    let role: FoodComponentRole
    let observationCount: Int
    let typicalCalories: Int
    let typicalProteinGrams: Double
    let typicalCarbsGrams: Double
    let typicalFatGrams: Double
}

struct FoodMemoryFingerprint: Codable, Sendable, Hashable {
    let version: Int
    let type: FingerprintType
    let value: String
}

enum FingerprintType: String, Codable, Sendable {
    case normalizedName
    case roundedMacroSignature
    case coarseMacroBucket
    case componentSet
    case componentRoleSet
    case servingSignature
    case mealTimeBucket
}

struct FoodMemoryQualitySignals: Codable, Sendable {
    let proportionUserEdited: Double
    let proportionWithStructuredComponents: Double
    let distinctObservationDays: Int
    let repeatedTimeBucketScore: Double
}

enum FoodSuggestionOutcome: String, Codable, Sendable {
    case shown
    case tapped
    case accepted
    case refined
    case dismissed
}

struct FoodMemorySuggestionStats: Codable, Sendable {
    let timesShown: Int
    let timesTapped: Int
    let timesAccepted: Int
    let timesDismissed: Int
    let timesRefined: Int
    let lastShownAt: Date?
    let lastTappedAt: Date?
    let lastAcceptedAt: Date?
    let lastDismissedAt: Date?
    let lastRefinedAt: Date?
}

struct FoodMemoryRepeatPattern: Codable, Sendable {
    let distinctConsumptionDays: Int
    let daysWithMultipleUses: Int
    let maxUsesInDay: Int
    let averageUsesPerDay: Double
    let averageRepeatGapMinutes: Double?
    let repeatGapObservationCount: Int
    let currentDayUseCount: Int
    let currentDayAnchor: Date
    let lastConsumptionAt: Date
}

struct FoodMemoryMatchStats: Codable, Sendable {
    let acceptedMatches: Int
    let rejectedMatches: Int
    let ambiguousMatches: Int
    let lastResolverVersion: Int
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
