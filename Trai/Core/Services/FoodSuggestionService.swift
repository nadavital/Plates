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
    let bucket: MealTimeBucket
    let totalMemories: Int
    let totalObservations: Int
    let habitCount: Int
    let candidateCountBySource: [String: Int]
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let baseEligibleMemories: Int
    let structuredMemories: Int
    let bucketAlignedMemories: Int
    let filteredAlreadySatisfiedToday: Int
    let filteredNegativeFeedback: Int
    let filteredStale: Int
    let filteredRetrievalTiming: Int
    let filteredRetrievalHistory: Int
    let filteredLikelyCompletedSession: Int
    let filteredLowRetrievalScore: Int
    let retrievedCandidateCount: Int
    let filteredFinalEligibility: Int
    let filteredLowFinalScore: Int
    let suppressedLowUsefulnessCount: Int
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
            entries: entries,
            memories: memories,
            at: referenceDate,
            modelContext: modelContext
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
        let bucket = normalizationService.mealTimeBucket(for: referenceDate)
        guard limit > 0 else {
            return emptyDebugSummary(bucket: bucket)
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
            bucket: bucket,
            totalMemories: memories.count,
            totalObservations: engineDebugReport.observationCount,
            habitCount: engineDebugReport.habitCount,
            candidateCountBySource: engineDebugReport.candidateCountBySource.reduce(into: [String: Int]()) {
                $0[$1.key.rawValue] = $1.value
            },
            suppressedOneOffCount: engineDebugReport.suppressedOneOffCount,
            suppressedAlreadyTodayCount: engineDebugReport.suppressedAlreadyTodayCount,
            baseEligibleMemories: memories.filter(baseDebugEligibility).count,
            structuredMemories: memories.filter { ($0.qualitySignals?.proportionWithStructuredComponents ?? 0) > 0 }.count,
            bucketAlignedMemories: bucketAlignedMemoryCount(memories: memories, bucket: bucket),
            filteredAlreadySatisfiedToday: engineDebugReport.suppressedAlreadyTodayCount,
            filteredNegativeFeedback: 0,
            filteredStale: 0,
            filteredRetrievalTiming: 0,
            filteredRetrievalHistory: 0,
            filteredLikelyCompletedSession: 0,
            filteredLowRetrievalScore: 0,
            retrievedCandidateCount: engineDebugReport.candidateCountBySource.values.reduce(0, +),
            filteredFinalEligibility: 0,
            filteredLowFinalScore: 0,
            suppressedLowUsefulnessCount: engineDebugReport.suppressedLowUsefulnessCount,
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
        entries: [FoodEntry],
        memories: [FoodMemory],
        at targetDate: Date,
        modelContext: ModelContext
    ) throws -> [FoodSuggestion] {
        guard !suggestions.isEmpty else { return [] }
        var didChange = false
        var workingMemories = memories
        var output: [FoodSuggestion] = []

        for suggestion in suggestions {
            if workingMemories.contains(where: { $0.id == suggestion.memoryID }) {
                output.append(suggestion)
                continue
            }

            let matchingEntries = entries.filter {
                $0.loggedAt < targetDate && entryMatches($0, suggestion: suggestion)
            }

            if let existingMemory = workingMemories.first(where: { memoryMatches($0, suggestion: suggestion) }) {
                if link(entries: matchingEntries, to: existingMemory) {
                    didChange = true
                }
                output.append(suggestion.replacingMemoryID(existingMemory.id))
                continue
            }

            let memory = materializedMemory(from: suggestion, matchingEntries: matchingEntries, targetDate: targetDate)
            modelContext.insert(memory)
            workingMemories.append(memory)
            if link(entries: matchingEntries, to: memory) {
                didChange = true
            }
            didChange = true
            output.append(suggestion.replacingMemoryID(memory.id))
        }

        if didChange {
            try modelContext.save()
        }
        return output
    }

    private func entryMatches(_ entry: FoodEntry, suggestion: FoodSuggestion) -> Bool {
        guard let snapshot = entry.acceptedSnapshot else { return false }
        let entryComponents = canonicalComponentSet(from: snapshot.components)
        let suggestionComponents = canonicalComponentSet(from: suggestion.suggestedEntry.components)
        if !entryComponents.isEmpty, !suggestionComponents.isEmpty, entryComponents == suggestionComponents {
            return nutritionLooksCompatible(snapshot: snapshot, suggestion: suggestion)
        }

        return normalizationService.normalizeFoodName(snapshot.displayName) == normalizationService.normalizeFoodName(suggestion.title)
            && nutritionLooksCompatible(snapshot: snapshot, suggestion: suggestion)
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

    private func link(entries: [FoodEntry], to memory: FoodMemory) -> Bool {
        var didChange = false
        let memoryIDString = memory.id.uuidString
        for entry in entries where entry.foodMemoryIdString != memoryIDString {
            entry.foodMemoryIdString = memoryIDString
            entry.foodMemoryNeedsResolution = false
            entry.foodMemoryResolutionState = .matched
            entry.foodMemoryMatchConfidence = max(entry.foodMemoryMatchConfidence, 0.86)
            entry.foodMemoryResolvedAt = .now
            didChange = true
        }
        return didChange
    }

    private func materializedMemory(
        from suggestion: FoodSuggestion,
        matchingEntries: [FoodEntry],
        targetDate: Date
    ) -> FoodMemory {
        let entryCount = max(matchingEntries.count, 1)
        let normalizedTitle = normalizationService.normalizeFoodName(suggestion.title)
        let memory = FoodMemory()
        memory.kind = FoodMemoryKind(rawValue: suggestion.suggestedEntry.mealKind ?? "") ?? (suggestion.suggestedEntry.components.count > 1 ? .meal : .food)
        memory.status = entryCount >= 2 ? .confirmed : .candidate
        memory.displayName = suggestion.title
        memory.emoji = suggestion.emoji
        memory.primaryNormalizedName = normalizedTitle
        memory.aliases = [
            FoodMemoryAlias(
                normalizedName: normalizedTitle,
                displayName: suggestion.title,
                observationCount: entryCount,
                wasUserEdited: false
            )
        ]
        memory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: suggestion.suggestedEntry.calories,
            medianProteinGrams: suggestion.suggestedEntry.proteinGrams,
            medianCarbsGrams: suggestion.suggestedEntry.carbsGrams,
            medianFatGrams: suggestion.suggestedEntry.fatGrams,
            medianFiberGrams: suggestion.suggestedEntry.fiberGrams,
            medianSugarGrams: suggestion.suggestedEntry.sugarGrams,
            lowerCaloriesBound: suggestion.suggestedEntry.calories,
            upperCaloriesBound: suggestion.suggestedEntry.calories,
            lowerProteinBound: suggestion.suggestedEntry.proteinGrams,
            upperProteinBound: suggestion.suggestedEntry.proteinGrams
        )
        memory.servingProfile = FoodMemoryServingProfile(
            commonServingText: suggestion.suggestedEntry.servingSize,
            commonQuantity: nil,
            commonUnit: nil,
            quantityVariance: nil
        )
        memory.components = suggestion.suggestedEntry.components.map { component in
            FoodMemoryComponentSummary(
                normalizedName: normalizationService.normalizeComponentName(component.displayName),
                role: component.role.flatMap(FoodComponentRole.init(rawValue:)) ?? .other,
                observationCount: entryCount,
                typicalCalories: component.calories,
                typicalProteinGrams: component.proteinGrams,
                typicalCarbsGrams: component.carbsGrams,
                typicalFatGrams: component.fatGrams
            )
        }
        memory.fingerprints = materializedFingerprints(for: suggestion, normalizedTitle: normalizedTitle)
        memory.representativeEntryIds = matchingEntries.map { $0.id.uuidString }
        memory.timeProfile = materializedTimeProfile(from: matchingEntries, fallbackDate: targetDate)
        memory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: suggestion.suggestedEntry.components.isEmpty ? 0 : 1,
            distinctObservationDays: Set(matchingEntries.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count,
            repeatedTimeBucketScore: 1
        )
        memory.observationCount = entryCount
        memory.confirmedReuseCount = max(0, entryCount - 1)
        memory.confidenceScore = max(suggestion.relevanceScore, 0.86)
        memory.lastObservedAt = matchingEntries.map(\.loggedAt).max() ?? targetDate
        return memory
    }

    private func materializedFingerprints(for suggestion: FoodSuggestion, normalizedTitle: String) -> [FoodMemoryFingerprint] {
        let components = suggestion.suggestedEntry.components
            .map { normalizationService.normalizeComponentName($0.displayName) }
            .filter { !$0.isEmpty }
            .sorted()
        let roles = suggestion.suggestedEntry.components.compactMap(\.role).sorted()
        return [
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: normalizedTitle),
            FoodMemoryFingerprint(version: 1, type: .componentSet, value: components.joined(separator: "|")),
            FoodMemoryFingerprint(version: 1, type: .componentRoleSet, value: roles.joined(separator: "|")),
            FoodMemoryFingerprint(version: 1, type: .coarseMacroBucket, value: coarseMacroBucket(for: suggestion.suggestedEntry))
        ].filter { !$0.value.isEmpty }
    }

    private func materializedTimeProfile(from entries: [FoodEntry], fallbackDate: Date) -> FoodMemoryTimeProfile {
        let dates = entries.map(\.loggedAt).isEmpty ? [fallbackDate] : entries.map(\.loggedAt)
        var hourCounts = Array(repeating: 0, count: 24)
        var bucketCounts: [String: Int] = [:]
        var weekdayCount = 0
        var weekendCount = 0

        for date in dates {
            let components = Calendar.current.dateComponents([.hour, .weekday], from: date)
            if let hour = components.hour, hour >= 0, hour < 24 {
                hourCounts[hour] += 1
            }
            bucketCounts[normalizationService.mealTimeBucket(for: date).rawValue, default: 0] += 1
            if components.weekday == 1 || components.weekday == 7 {
                weekendCount += 1
            } else {
                weekdayCount += 1
            }
        }

        return FoodMemoryTimeProfile(
            hourCounts: hourCounts,
            bucketCounts: bucketCounts,
            weekdayCount: weekdayCount,
            weekendCount: weekendCount
        )
    }

    private func canonicalComponentSet(from components: [AcceptedFoodComponent]) -> Set<String> {
        Set(components.map { normalizationService.normalizeComponentName($0.displayName) }.filter { !$0.isEmpty })
    }

    private func canonicalComponentSet(from components: [SuggestedFoodComponent]) -> Set<String> {
        Set(components.map { normalizationService.normalizeComponentName($0.displayName) }.filter { !$0.isEmpty })
    }

    private func nutritionLooksCompatible(snapshot: AcceptedFoodSnapshot, suggestion: FoodSuggestion) -> Bool {
        nutritionLooksCompatible(
            calories: snapshot.totalCalories,
            protein: snapshot.totalProteinGrams,
            carbs: snapshot.totalCarbsGrams,
            fat: snapshot.totalFatGrams,
            suggestion: suggestion
        )
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

    private func coarseMacroBucket(for entry: SuggestedFoodEntry) -> String {
        [
            "cal:\(Int((Double(entry.calories) / 100).rounded() * 100))",
            "p:\(Int((entry.proteinGrams / 10).rounded() * 10))",
            "c:\(Int((entry.carbsGrams / 10).rounded() * 10))",
            "f:\(Int((entry.fatGrams / 5).rounded() * 5))"
        ].joined(separator: "|")
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

    private func emptyDebugSummary(bucket: MealTimeBucket) -> FoodSuggestionDebugSummary {
        FoodSuggestionDebugSummary(
            bucket: bucket,
            totalMemories: 0,
            totalObservations: 0,
            habitCount: 0,
            candidateCountBySource: [:],
            suppressedOneOffCount: 0,
            suppressedAlreadyTodayCount: 0,
            baseEligibleMemories: 0,
            structuredMemories: 0,
            bucketAlignedMemories: 0,
            filteredAlreadySatisfiedToday: 0,
            filteredNegativeFeedback: 0,
            filteredStale: 0,
            filteredRetrievalTiming: 0,
            filteredRetrievalHistory: 0,
            filteredLikelyCompletedSession: 0,
            filteredLowRetrievalScore: 0,
            retrievedCandidateCount: 0,
            filteredFinalEligibility: 0,
            filteredLowFinalScore: 0,
            suppressedLowUsefulnessCount: 0,
            finalEligibleCount: 0,
            shownSuggestionTitles: []
        )
    }

    private func baseDebugEligibility(_ memory: FoodMemory) -> Bool {
        memory.status != .retired
            && memory.nutritionProfile != nil
            && !memory.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bucketAlignedMemoryCount(memories: [FoodMemory], bucket: MealTimeBucket) -> Int {
        memories.filter { memory in
            guard let timeProfile = memory.timeProfile else { return false }
            return dominantBucket(in: timeProfile) == bucket
        }.count
    }

    private func dominantBucket(in profile: FoodMemoryTimeProfile) -> MealTimeBucket? {
        profile.bucketCounts
            .max { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.key > rhs.key
            }
            .flatMap { MealTimeBucket(rawValue: $0.key) }
    }
}
