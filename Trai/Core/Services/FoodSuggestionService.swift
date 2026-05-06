import Foundation
import SwiftData

struct FoodSuggestion: Identifiable, Sendable, Equatable {
    let memoryID: UUID
    let title: String
    let subtitle: String
    let detail: String
    let emoji: String
    let relevanceScore: Double
    let suggestedEntry: SuggestedFoodEntry

    var id: UUID { memoryID }

    func replacingMemoryID(_ memoryID: UUID) -> FoodSuggestion {
        FoodSuggestion(
            memoryID: memoryID,
            title: title,
            subtitle: subtitle,
            detail: detail,
            emoji: emoji,
            relevanceScore: relevanceScore,
            suggestedEntry: suggestedEntry
        )
    }
}

struct FoodSuggestionDebugSummary: Sendable {
    let totalMemories: Int
    let totalObservations: Int
    let patternCount: Int
    let candidateCountBySource: [String: Int]
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let retrievedCandidateCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowConfidenceCount: Int
    let finalEligibleCount: Int
    let shownSuggestionTitles: [String]
}

struct FoodSuggestionService {
    private let matcher = FoodMemoryMatcher()
    private let normalizationService = FoodNormalizationService()

    @MainActor
    func cameraSuggestions(
        limit: Int,
        now: Date = .now,
        targetDate: Date? = nil,
        sessionId: UUID? = nil,
        modelContext: ModelContext
    ) throws -> [FoodSuggestion] {
        guard limit > 0 else { return [] }
        let referenceDate = targetDate ?? now
        let memories = try fetchMemories(modelContext: modelContext)
        let entries = try fetchEntries(modelContext: modelContext)

        let engineResult = FoodRecommendationEngine().recommendationsSync(
            for: FoodRecommendationRequest(
                now: now,
                targetDate: referenceDate,
                sessionID: sessionId,
                limit: limit,
                entries: entries,
                memories: memories
            )
        )
        let suggestions = try materializedEngineSuggestions(
            engineResult.suggestions,
            memories: memories
        )
        try recordOutcomes(.shown, for: suggestions.map(\.memoryID), at: now, modelContext: modelContext)
        return suggestions
    }

    @MainActor
    func recordOutcome(
        _ outcome: FoodSuggestionOutcome,
        for memoryID: UUID,
        at: Date = .now,
        modelContext: ModelContext
    ) throws {
        try recordOutcomes(outcome, for: [memoryID], at: at, modelContext: modelContext)
    }

    @MainActor
    func recordOutcome(
        _ outcome: FoodSuggestionOutcome,
        for memoryIDs: [UUID],
        at: Date = .now,
        modelContext: ModelContext
    ) throws {
        try recordOutcomes(outcome, for: memoryIDs, at: at, modelContext: modelContext)
    }

    @MainActor
    func reconcileShownSuggestions(
        _ shownMemoryIDs: [UUID],
        preferredMemoryID: UUID?,
        with savedSnapshot: AcceptedFoodSnapshot,
        isRefined: Bool,
        modelContext: ModelContext
    ) throws {
        let uniqueShownIDs = Array(Set(shownMemoryIDs))
        guard !uniqueShownIDs.isEmpty else { return }

        let shownIDSet = Set(uniqueShownIDs)
        let memories = try modelContext.fetch(FetchDescriptor<FoodMemory>())
        let shownMemories = memories.filter { shownIDSet.contains($0.id) }
        guard !shownMemories.isEmpty else { return }

        var matchedMemoryIDs = shownMemories.compactMap { memory in
            matcher.matches(memory: memory, snapshot: savedSnapshot) ? memory.id : nil
        }

        if matchedMemoryIDs.isEmpty,
           let preferredMemoryID,
           shownIDSet.contains(preferredMemoryID),
           !isRefined {
            matchedMemoryIDs = [preferredMemoryID]
        }

        guard !matchedMemoryIDs.isEmpty else { return }

        try recordOutcomes(
            isRefined ? .refined : .accepted,
            for: matchedMemoryIDs,
            at: savedSnapshot.loggedAt,
            modelContext: modelContext
        )

        if matchedMemoryIDs.count > 1 {
            _ = try FoodMemoryService().consolidateDuplicateMemories(
                memoryIDs: matchedMemoryIDs,
                modelContext: modelContext
            )
        }
    }

    @MainActor
    func debugCameraSuggestions(
        limit: Int = 3,
        now: Date = .now,
        targetDate: Date? = nil,
        sessionId: UUID? = nil,
        modelContext: ModelContext
    ) throws -> FoodSuggestionDebugSummary {
        let referenceDate = targetDate ?? now
        guard limit > 0 else {
            return emptyDebugSummary()
        }

        let memories = try fetchMemories(modelContext: modelContext)
        let entries = try fetchEntries(modelContext: modelContext)
        let engineDebugReport = FoodRecommendationEngine().recommendationsSync(
            for: FoodRecommendationRequest(
                now: now,
                targetDate: referenceDate,
                sessionID: sessionId,
                limit: limit,
                entries: entries,
                memories: memories
            )
        ).debugReport

        return FoodSuggestionDebugSummary(
            totalMemories: memories.count,
            totalObservations: engineDebugReport.observationCount,
            patternCount: engineDebugReport.patternCount,
            candidateCountBySource: engineDebugReport.candidateCountBySource.reduce(into: [String: Int]()) {
                $0[$1.key.rawValue] = $1.value
            },
            suppressedOneOffCount: engineDebugReport.suppressedOneOffCount,
            suppressedAlreadyTodayCount: engineDebugReport.suppressedAlreadyTodayCount,
            retrievedCandidateCount: engineDebugReport.candidateCountBySource.values.reduce(0, +),
            suppressedNegativeFeedbackCount: engineDebugReport.suppressedNegativeFeedbackCount,
            suppressedLowConfidenceCount: engineDebugReport.suppressedLowConfidenceCount,
            finalEligibleCount: engineDebugReport.finalShownTitles.count,
            shownSuggestionTitles: engineDebugReport.finalShownTitles
        )
    }

    @MainActor
    private func fetchMemories(modelContext: ModelContext) throws -> [FoodMemory] {
        try modelContext.fetch(
            FetchDescriptor<FoodMemory>(
                sortBy: [SortDescriptor(\FoodMemory.updatedAt, order: .reverse)]
            )
        )
    }

    @MainActor
    private func fetchEntries(modelContext: ModelContext) throws -> [FoodEntry] {
        try modelContext.fetch(
            FetchDescriptor<FoodEntry>(
                sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
            )
        )
    }

    @MainActor
    private func materializedEngineSuggestions(
        _ suggestions: [FoodSuggestion],
        memories: [FoodMemory]
    ) throws -> [FoodSuggestion] {
        guard !suggestions.isEmpty else { return [] }

        return suggestions.map { suggestion in
            guard !memories.contains(where: { $0.id == suggestion.memoryID }),
                  let existingMemory = memories.first(where: { memoryMatches($0, suggestion: suggestion) })
            else {
                return suggestion
            }
            return suggestion.replacingMemoryID(existingMemory.id)
        }
    }

    private func memoryMatches(_ memory: FoodMemory, suggestion: FoodSuggestion) -> Bool {
        let memoryComponents = Set(
            memory.components
                .map { normalizationService.normalizeComponentName($0.normalizedName) }
                .filter { !$0.isEmpty }
        )
        let suggestionComponents = canonicalComponentSet(from: suggestion.suggestedEntry.components)
        if !memoryComponents.isEmpty, !suggestionComponents.isEmpty, memoryComponents == suggestionComponents {
            return nutritionLooksCompatible(memory: memory, suggestion: suggestion)
        }

        let normalizedSuggestionTitle = normalizationService.normalizeFoodName(suggestion.title)
        return !normalizedSuggestionTitle.isEmpty
            && Set(memory.aliases.map(\.normalizedName)).union([memory.primaryNormalizedName]).contains(normalizedSuggestionTitle)
            && nutritionLooksCompatible(memory: memory, suggestion: suggestion)
    }


    private func canonicalComponentSet(from components: [SuggestedFoodComponent]) -> Set<String> {
        Set(components.map { normalizationService.normalizeComponentName($0.displayName) }.filter { !$0.isEmpty })
    }

    private func nutritionLooksCompatible(memory: FoodMemory, suggestion: FoodSuggestion) -> Bool {
        guard let nutrition = memory.nutritionProfile else { return true }
        return nutritionLooksCompatible(
            calories: nutrition.medianCalories,
            protein: nutrition.medianProteinGrams,
            carbs: nutrition.medianCarbsGrams,
            fat: nutrition.medianFatGrams,
            suggestion: suggestion
        )
    }

    private func nutritionLooksCompatible(
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        suggestion: FoodSuggestion
    ) -> Bool {
        let suggestedEntry = suggestion.suggestedEntry
        return abs(Double(calories - suggestedEntry.calories)) <= max(Double(suggestedEntry.calories) * 0.4, 120)
            && abs(protein - suggestedEntry.proteinGrams) <= max(suggestedEntry.proteinGrams * 0.5, 12)
            && abs(carbs - suggestedEntry.carbsGrams) <= max(suggestedEntry.carbsGrams * 0.5, 18)
            && abs(fat - suggestedEntry.fatGrams) <= max(suggestedEntry.fatGrams * 0.5, 10)
    }

    private func recordOutcomes(
        _ outcome: FoodSuggestionOutcome,
        for memoryIDs: [UUID],
        at: Date,
        modelContext: ModelContext
    ) throws {
        let ids = Set(memoryIDs)
        guard !ids.isEmpty else { return }

        let memories = try modelContext.fetch(FetchDescriptor<FoodMemory>())
        var didChange = false

        for memory in memories where ids.contains(memory.id) {
            memory.suggestionStats = updatedSuggestionStats(
                existing: memory.suggestionStats,
                outcome: outcome,
                at: at
            )
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }

    private func updatedSuggestionStats(
        existing: FoodMemorySuggestionStats?,
        outcome: FoodSuggestionOutcome,
        at: Date
    ) -> FoodMemorySuggestionStats {
        var timesShown = existing?.timesShown ?? 0
        var timesTapped = existing?.timesTapped ?? 0
        var timesAccepted = existing?.timesAccepted ?? 0
        var timesDismissed = existing?.timesDismissed ?? 0
        var timesRefined = existing?.timesRefined ?? 0
        var lastShownAt = existing?.lastShownAt
        var lastTappedAt = existing?.lastTappedAt
        var lastAcceptedAt = existing?.lastAcceptedAt
        var lastDismissedAt = existing?.lastDismissedAt
        var lastRefinedAt = existing?.lastRefinedAt

        switch outcome {
        case .shown:
            timesShown += 1
            lastShownAt = at
        case .tapped:
            timesTapped += 1
            lastTappedAt = at
        case .accepted:
            timesAccepted += 1
            lastAcceptedAt = at
        case .refined:
            timesAccepted += 1
            timesRefined += 1
            lastAcceptedAt = at
            lastRefinedAt = at
        case .dismissed:
            timesDismissed += 1
            lastDismissedAt = at
        }

        return FoodMemorySuggestionStats(
            timesShown: timesShown,
            timesTapped: timesTapped,
            timesAccepted: timesAccepted,
            timesDismissed: timesDismissed,
            timesRefined: timesRefined,
            lastShownAt: lastShownAt,
            lastTappedAt: lastTappedAt,
            lastAcceptedAt: lastAcceptedAt,
            lastDismissedAt: lastDismissedAt,
            lastRefinedAt: lastRefinedAt
        )
    }

    private func emptyDebugSummary() -> FoodSuggestionDebugSummary {
        FoodSuggestionDebugSummary(
            totalMemories: 0,
            totalObservations: 0,
            patternCount: 0,
            candidateCountBySource: [:],
            suppressedOneOffCount: 0,
            suppressedAlreadyTodayCount: 0,
            retrievedCandidateCount: 0,
            suppressedNegativeFeedbackCount: 0,
            suppressedLowConfidenceCount: 0,
            finalEligibleCount: 0,
            shownSuggestionTitles: []
        )
    }
}
