import Foundation
import SwiftData

@Model
final class FoodMemory {
    var id: UUID = UUID()
    var kindRaw: String = FoodMemoryKind.food.rawValue
    var statusRaw: String = FoodMemoryStatus.candidate.rawValue
    var displayName: String = ""
    var emoji: String?
    var primaryNormalizedName: String = ""
    var aliasesData: Data?
    var nutritionProfileData: Data?
    var servingProfileData: Data?
    var timeProfileData: Data?
    var componentsData: Data?
    var fingerprintsData: Data?
    var representativeEntryIdsData: Data?
    var qualitySignalsData: Data?
    var suggestionStatsData: Data?
    var repeatPatternData: Data?
    var matchStatsData: Data?
    var observationCount: Int = 0
    var confirmedReuseCount: Int = 0
    var confidenceScore: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastObservedAt: Date = Date()
    var retiredAt: Date?

    init() {}
}

extension FoodMemory {
    private static let coder = JSONCoder()

    var kind: FoodMemoryKind {
        get { FoodMemoryKind(rawValue: kindRaw) ?? .food }
        set { kindRaw = newValue.rawValue }
    }

    var status: FoodMemoryStatus {
        get { FoodMemoryStatus(rawValue: statusRaw) ?? .candidate }
        set { statusRaw = newValue.rawValue }
    }

    var aliases: [FoodMemoryAlias] {
        get { Self.coder.decode([FoodMemoryAlias].self, from: aliasesData) ?? [] }
        set { aliasesData = Self.coder.encode(newValue) }
    }

    var nutritionProfile: FoodMemoryNutritionProfile? {
        get { Self.coder.decode(FoodMemoryNutritionProfile.self, from: nutritionProfileData) }
        set { nutritionProfileData = Self.coder.encode(newValue) }
    }

    var servingProfile: FoodMemoryServingProfile? {
        get { Self.coder.decode(FoodMemoryServingProfile.self, from: servingProfileData) }
        set { servingProfileData = Self.coder.encode(newValue) }
    }

    var timeProfile: FoodMemoryTimeProfile? {
        get { Self.coder.decode(FoodMemoryTimeProfile.self, from: timeProfileData) }
        set { timeProfileData = Self.coder.encode(newValue) }
    }

    var components: [FoodMemoryComponentSummary] {
        get { Self.coder.decode([FoodMemoryComponentSummary].self, from: componentsData) ?? [] }
        set { componentsData = Self.coder.encode(newValue) }
    }

    var fingerprints: [FoodMemoryFingerprint] {
        get { Self.coder.decode([FoodMemoryFingerprint].self, from: fingerprintsData) ?? [] }
        set { fingerprintsData = Self.coder.encode(newValue) }
    }

    var representativeEntryIds: [String] {
        get { Self.coder.decode([String].self, from: representativeEntryIdsData) ?? [] }
        set { representativeEntryIdsData = Self.coder.encode(newValue) }
    }

    var qualitySignals: FoodMemoryQualitySignals? {
        get { Self.coder.decode(FoodMemoryQualitySignals.self, from: qualitySignalsData) }
        set { qualitySignalsData = Self.coder.encode(newValue) }
    }

    var suggestionStats: FoodMemorySuggestionStats? {
        get { Self.coder.decode(FoodMemorySuggestionStats.self, from: suggestionStatsData) }
        set { suggestionStatsData = Self.coder.encode(newValue) }
    }

    var repeatPattern: FoodMemoryRepeatPattern? {
        get { Self.coder.decode(FoodMemoryRepeatPattern.self, from: repeatPatternData) }
        set { repeatPatternData = Self.coder.encode(newValue) }
    }

    var matchStats: FoodMemoryMatchStats? {
        get { Self.coder.decode(FoodMemoryMatchStats.self, from: matchStatsData) }
        set { matchStatsData = Self.coder.encode(newValue) }
    }
}

private struct JSONCoder {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? encoder.encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
