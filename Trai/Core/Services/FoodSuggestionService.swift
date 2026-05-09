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
        let completedSuggestions = completedSuggestions(
            engineSuggestions: suggestions,
            memories: memories,
            entries: entries,
            now: now,
            targetDate: referenceDate,
            sessionId: sessionId,
            limit: limit
        )
        try recordOutcomes(.shown, for: completedSuggestions.map(\.memoryID), at: now, modelContext: modelContext)
        return completedSuggestions
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

    private func completedSuggestions(
        engineSuggestions: [FoodSuggestion],
        memories: [FoodMemory],
        entries: [FoodEntry],
        now: Date,
        targetDate: Date,
        sessionId: UUID?,
        limit: Int
    ) -> [FoodSuggestion] {
        guard limit > 0 else { return [] }
        let linkedMemoryIDs = Set(entries.compactMap { $0.foodMemoryIdString.flatMap(UUID.init(uuidString:)) })
        let directSuggestions = sessionId == nil
            ? memories
                .filter { !linkedMemoryIDs.contains($0.id) }
                .compactMap { directSuggestion(from: $0, now: now, targetDate: targetDate, existingEntries: entries) }
            : []
        let merged = deduplicatedSuggestions(engineSuggestions + directSuggestions)
            .filter { sessionId != nil || isStandaloneSuggestion($0) }
            .sorted {
                if $0.relevanceScore != $1.relevanceScore {
                    return $0.relevanceScore > $1.relevanceScore
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        return Array(merged.prefix(limit))
    }

    private func directSuggestion(
        from memory: FoodMemory,
        now: Date,
        targetDate: Date,
        existingEntries: [FoodEntry]
    ) -> FoodSuggestion? {
        guard memory.status == .confirmed else { return nil }
        guard hasSufficientEvidence(memory) else { return nil }
        guard !hasRecentNegativeFeedback(memory, now: now) else { return nil }
        guard !isStale(memory, targetDate: targetDate) || hasPositiveFeedback(memory) else { return nil }
        guard !alreadyLogged(memory, targetDate: targetDate, entries: existingEntries) else { return nil }

        let timeSupport = memoryTimeSupport(memory, targetDate: targetDate)
        let bucketSupport = memoryBucketSupport(memory, targetDate: targetDate)
        let strongHabit = isStrongUsefulHabit(memory)
        let shouldShow = timeSupport >= 0.20
            || bucketSupport >= 0.12
            || strongHabit
            || hasPositiveFeedback(memory)
        guard shouldShow else { return nil }

        let entry = suggestedEntry(from: memory)
        let score = directSuggestionScore(
            memory: memory,
            targetDate: targetDate,
            timeSupport: timeSupport,
            bucketSupport: bucketSupport
        )
        return FoodSuggestion(
            memoryID: memory.id,
            title: memory.displayName,
            subtitle: directSuggestionSubtitle(targetDate: targetDate, timeSupport: timeSupport, bucketSupport: bucketSupport),
            detail: "\(Int(entry.proteinGrams.rounded()))g protein • \(entry.calories) cal",
            emoji: memory.emoji ?? "🍽️",
            relevanceScore: score,
            suggestedEntry: entry
        )
    }

    private func deduplicatedSuggestions(_ suggestions: [FoodSuggestion]) -> [FoodSuggestion] {
        suggestions.reduce(into: [FoodSuggestion]()) { output, suggestion in
            if let existingIndex = output.firstIndex(where: { suggestionsOverlap($0, suggestion) }) {
                if suggestion.relevanceScore > output[existingIndex].relevanceScore {
                    output[existingIndex] = suggestion
                }
            } else {
                output.append(suggestion)
            }
        }
    }

    private func suggestionsOverlap(_ lhs: FoodSuggestion, _ rhs: FoodSuggestion) -> Bool {
        guard lhs.memoryID != rhs.memoryID else { return true }
        let lhsComponents = canonicalComponentSet(from: lhs.suggestedEntry.components)
        let rhsComponents = canonicalComponentSet(from: rhs.suggestedEntry.components)
        if !lhsComponents.isEmpty, lhsComponents == rhsComponents {
            return true
        }
        let lhsTitle = normalizationService.normalizeFoodName(lhs.title)
        let rhsTitle = normalizationService.normalizeFoodName(rhs.title)
        return !lhsTitle.isEmpty && lhsTitle == rhsTitle
    }

    private func isStandaloneSuggestion(_ suggestion: FoodSuggestion) -> Bool {
        let isCarbSide = !suggestion.suggestedEntry.components.isEmpty
            && suggestion.suggestedEntry.components.allSatisfy { $0.role == FoodComponentRole.carb.rawValue }
            && suggestion.suggestedEntry.proteinGrams < 14
        return !isCarbSide
    }

    private func hasSufficientEvidence(_ memory: FoodMemory) -> Bool {
        memory.observationCount >= 2
            || memory.confirmedReuseCount > 0
            || hasPositiveFeedback(memory)
    }

    private func hasPositiveFeedback(_ memory: FoodMemory) -> Bool {
        let stats = memory.suggestionStats
        return (stats?.timesAccepted ?? 0) > 0 || (stats?.timesRefined ?? 0) > 0
    }

    private func hasRecentNegativeFeedback(_ memory: FoodMemory, now: Date) -> Bool {
        guard let stats = memory.suggestionStats else { return false }
        if stats.timesShown >= 4, stats.timesAccepted == 0, stats.timesDismissed == 0 {
            return true
        }
        guard stats.timesDismissed > stats.timesAccepted else { return false }
        guard let lastDismissedAt = stats.lastDismissedAt else { return stats.timesDismissed >= 3 }
        let hours = Calendar.current.dateComponents([.hour], from: lastDismissedAt, to: now).hour ?? 999
        return hours < 12
    }

    private func isStale(_ memory: FoodMemory, targetDate: Date) -> Bool {
        let days = Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: targetDate).day ?? 999
        return days > 45
    }

    private func alreadyLogged(_ memory: FoodMemory, targetDate: Date, entries: [FoodEntry]) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: targetDate)
        let memoryComponents = Set(memory.components.map { normalizationService.normalizeComponentName($0.normalizedName) }.filter { !$0.isEmpty })
        return entries.contains { entry in
            guard entry.loggedAt >= startOfDay, entry.loggedAt < targetDate else { return false }
            if entry.foodMemoryIdString == memory.id.uuidString {
                return true
            }
            let entryName = normalizationService.normalizeFoodName(entry.name)
            if !entryName.isEmpty, entryName == memory.primaryNormalizedName {
                return true
            }
            if entry.acceptedSnapshot == nil,
               !entryName.isEmpty,
               !memory.primaryNormalizedName.isEmpty,
               (entryName.contains(memory.primaryNormalizedName) || memory.primaryNormalizedName.contains(entryName)),
               nutritionLooksSimilar(entry: entry, memory: memory) {
                return true
            }
            guard let snapshot = entry.acceptedSnapshot, !memoryComponents.isEmpty else { return false }
            let entryComponents = Set(snapshot.components.map { normalizationService.normalizeComponentName($0.displayName) }.filter { !$0.isEmpty })
            return entryComponents == memoryComponents
        }
    }

    private func memoryTimeSupport(_ memory: FoodMemory, targetDate: Date) -> Double {
        guard let profile = memory.timeProfile else { return 0 }
        let hour = Calendar.current.component(.hour, from: targetDate)
        let weights = [0: 1.0, 1: 0.75, 2: 0.45, 3: 0.20]
        let total = max(profile.hourCounts.reduce(0, +), memory.observationCount, 1)
        let weighted = weights.reduce(0.0) { partial, item in
            let offset = item.key
            let weight = item.value
            if offset == 0 {
                return partial + Double(hourCount(profile.hourCounts, at: hour)) * weight
            }
            let before = (hour - offset + 24) % 24
            let after = (hour + offset) % 24
            return partial
                + Double(hourCount(profile.hourCounts, at: before)) * weight
                + Double(hourCount(profile.hourCounts, at: after)) * weight
        }
        return min(weighted / Double(total), 1)
    }

    private func hourCount(_ counts: [Int], at index: Int) -> Int {
        counts.indices.contains(index) ? counts[index] : 0
    }

    private func memoryBucketSupport(_ memory: FoodMemory, targetDate: Date) -> Double {
        let bucket = normalizationService.mealTimeBucket(for: targetDate)
        let explicitSupport = Double(memory.timeProfile?.bucketCounts[bucket.rawValue] ?? 0) / Double(max(memory.observationCount, 1))
        let nameSupport = normalizationService.normalizeFoodName(memory.displayName).contains(bucket.rawValue) ? 0.35 : 0
        return max(explicitSupport, nameSupport)
    }

    private func isStrongUsefulHabit(_ memory: FoodMemory) -> Bool {
        let nutrition = memory.nutritionProfile
        let calories = nutrition?.medianCalories ?? memory.components.map(\.typicalCalories).reduce(0, +)
        let protein = nutrition?.medianProteinGrams ?? memory.components.map(\.typicalProteinGrams).reduce(0, +)
        let isLiquidOnly = !memory.components.isEmpty && memory.components.allSatisfy { $0.role == .drink }
        let substantial = !isLiquidOnly && (calories >= 320 || protein >= 22 || memory.components.count >= 2)
        return substantial
            && memory.observationCount >= 6
            && memory.confirmedReuseCount >= 4
            && memory.confidenceScore >= 0.9
    }

    private func directSuggestionScore(
        memory: FoodMemory,
        targetDate: Date,
        timeSupport: Double,
        bucketSupport: Double
    ) -> Double {
        let days = Double(max(Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: targetDate).day ?? 0, 0))
        let recency = max(0, 1 - min(days / 45.0, 1))
        let repetition = min(Double(max(memory.observationCount, memory.confirmedReuseCount + 1)) / 8.0, 1)
        let confidence = min(max(memory.confidenceScore, 0), 1)
        let feedback = hasPositiveFeedback(memory) ? 0.12 : 0
        return min(
            0.30 * max(timeSupport, bucketSupport)
                + 0.22 * repetition
                + 0.18 * recency
                + 0.18 * confidence
                + feedback,
            1
        )
    }

    private func nutritionLooksSimilar(entry: FoodEntry, memory: FoodMemory) -> Bool {
        guard let nutrition = memory.nutritionProfile else { return false }
        return abs(Double(entry.calories - nutrition.medianCalories)) <= max(Double(nutrition.medianCalories) * 0.35, 80)
            && abs(entry.proteinGrams - nutrition.medianProteinGrams) <= max(nutrition.medianProteinGrams * 0.45, 10)
            && abs(entry.carbsGrams - nutrition.medianCarbsGrams) <= max(nutrition.medianCarbsGrams * 0.45, 12)
            && abs(entry.fatGrams - nutrition.medianFatGrams) <= max(nutrition.medianFatGrams * 0.45, 8)
    }

    private func directSuggestionSubtitle(targetDate: Date, timeSupport: Double, bucketSupport: Double) -> String {
        if timeSupport >= 0.20 || bucketSupport >= 0.20 {
            return "Common around \(normalizationService.mealTimeBucket(for: targetDate).rawValue)"
        }
        return "Remembered food"
    }

    private func suggestedEntry(from memory: FoodMemory) -> SuggestedFoodEntry {
        let nutrition = memory.nutritionProfile
        let components = memory.components.map { component in
            SuggestedFoodComponent(
                id: normalizationService.normalizeComponentName(component.normalizedName),
                displayName: component.normalizedName,
                role: component.role.rawValue,
                calories: component.typicalCalories,
                proteinGrams: component.typicalProteinGrams,
                carbsGrams: component.typicalCarbsGrams,
                fatGrams: component.typicalFatGrams,
                confidence: "medium"
            )
        }
        return SuggestedFoodEntry(
            id: memory.id.uuidString,
            name: memory.displayName,
            calories: nutrition?.medianCalories ?? components.map(\.calories).reduce(0, +),
            proteinGrams: nutrition?.medianProteinGrams ?? components.map(\.proteinGrams).reduce(0, +),
            carbsGrams: nutrition?.medianCarbsGrams ?? components.map(\.carbsGrams).reduce(0, +),
            fatGrams: nutrition?.medianFatGrams ?? components.map(\.fatGrams).reduce(0, +),
            fiberGrams: nutrition?.medianFiberGrams,
            sugarGrams: nutrition?.medianSugarGrams,
            servingSize: memory.servingProfile?.commonServingText,
            emoji: memory.emoji,
            components: components,
            mealKind: nil,
            notes: nil,
            confidence: memory.confidenceScore >= 0.9 ? "high" : "medium",
            schemaVersion: 2
        )
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
