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
}

struct FoodSuggestionDebugSummary: Sendable {
    let bucket: MealTimeBucket
    let totalMemories: Int
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
    let finalEligibleCount: Int
    let shownSuggestionTitles: [String]
}

private struct FoodSuggestionContext {
    let now: Date
    let bucket: MealTimeBucket
    let sessionID: UUID?
    let sessionEntries: [FoodEntry]
    let todaysEntries: [FoodEntry]
    let recentEntries: [FoodEntry]
}

private struct FoodSuggestionTimingContext {
    let bucket: MealTimeBucket
    let bucketSupport: Double
    let hourWindowSupport: Double
    let dayTypeSupport: Double
    let dominantBucket: MealTimeBucket?
    let dominantBucketShare: Double
    let dominantHourWindowShare: Double
    let isStronglyTimeBound: Bool
}

private struct FoodSuggestionCandidate {
    let memory: FoodMemory
    let suggestion: FoodSuggestion
    let context: FoodSuggestionTimingContext
    let retrievalScore: Double
    let cooccurrenceScore: Double
    let bundleScore: Double
    let orderingScore: Double
}

private struct FoodSuggestionRetrievedMemory {
    let memory: FoodMemory
    let context: FoodSuggestionTimingContext
    let retrievalScore: Double
    let cooccurrenceScore: Double
    let bundleScore: Double
    let orderingScore: Double
    let completionPenalty: Double
}

private struct FoodSuggestionSessionGroup {
    let memoryIDs: Set<UUID>
    let orderedMemoryIDs: [UUID]
    let itemCount: Int
    let lastLoggedAt: Date
}

private struct FoodSuggestionSessionSupport {
    let cooccurrence: [UUID: Double]
    let bundle: [UUID: Double]
    let ordering: [UUID: Double]
    let completionConfidence: Double
}

private struct FoodSuggestionRepeatProfile {
    let distinctDays: Int
    let daysWithMultipleUses: Int
    let maxUsesInDay: Int
    let averageUsesPerDay: Double
    let medianRepeatGapMinutes: Double?
}

private enum FoodSuggestionRetrievalFailureReason {
    case negativeFeedback
    case stale
    case timing
    case insufficientHistory
}

private enum FoodSuggestionCameraFailureReason {
    case negativeFeedback
    case stale
    case timing
}

struct FoodSuggestionService {
    private let matcher = FoodMemoryMatcher()
    private let normalizationService = FoodNormalizationService()
    private let historyWindowDays = 120

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

        let memories = try modelContext.fetch(
            FetchDescriptor<FoodMemory>(
                sortBy: [SortDescriptor(\FoodMemory.updatedAt, order: .reverse)]
            )
        )
        guard !memories.isEmpty else { return [] }

        let entries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(
                sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
            )
        )

        let context = makeContext(now: referenceDate, entries: entries, sessionID: sessionId)
        let retrievedMemories = retrieveCandidateMemories(from: memories, context: context, limit: limit)
        let rankedCandidates = retrievedMemories
            .compactMap { candidate(for: $0, context: context) }
            .sorted {
                if $0.suggestion.relevanceScore != $1.suggestion.relevanceScore {
                    return $0.suggestion.relevanceScore > $1.suggestion.relevanceScore
                }
                return $0.suggestion.suggestedEntry.proteinGrams > $1.suggestion.suggestedEntry.proteinGrams
            }

        let dedupedCandidates = deduplicate(rankedCandidates)
        let filteredCandidates = dedupedCandidates.filter {
            !shouldSuppressBecauseAlreadySatisfiedToday(memory: $0.memory, context: context)
        }
        let selectedCandidates = Array(filteredCandidates.prefix(limit))
        try recordOutcomes(.shown, for: selectedCandidates.map(\.memory.id), at: now, modelContext: modelContext)
        return selectedCandidates.map(\.suggestion)
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
        guard limit > 0 else {
            return FoodSuggestionDebugSummary(
                bucket: normalizationService.mealTimeBucket(for: targetDate ?? now),
                totalMemories: 0,
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
                finalEligibleCount: 0,
                shownSuggestionTitles: []
            )
        }

        let referenceDate = targetDate ?? now
        let memories = try modelContext.fetch(
            FetchDescriptor<FoodMemory>(
                sortBy: [SortDescriptor(\FoodMemory.updatedAt, order: .reverse)]
            )
        )
        let entries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(
                sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
            )
        )
        let context = makeContext(now: referenceDate, entries: entries, sessionID: sessionId)
        let sessionSupport = sessionSupportScores(memories: memories, context: context)

        var baseEligibleMemories = 0
        var filteredAlreadySatisfiedToday = 0
        var filteredNegativeFeedback = 0
        var filteredStale = 0
        var filteredRetrievalTiming = 0
        var filteredRetrievalHistory = 0
        var filteredLikelyCompletedSession = 0
        var filteredLowRetrievalScore = 0
        var filteredFinalEligibility = 0
        var filteredLowFinalScore = 0
        var retrieved: [FoodSuggestionRetrievedMemory] = []

        for memory in memories {
            guard baseSuggestionEligibility(memory) else { continue }
            baseEligibleMemories += 1

            let timingContext = suggestionContext(for: memory, targetBucket: context.bucket, now: context.now)

            if shouldSuppressBecauseAlreadySatisfiedToday(memory: memory, context: context) {
                filteredAlreadySatisfiedToday += 1
                continue
            }

            if let failureReason = retrievalEligibilityFailureReason(
                memory: memory,
                context: context,
                timingContext: timingContext
            ) {
                switch failureReason {
                case .negativeFeedback:
                    filteredNegativeFeedback += 1
                case .stale:
                    filteredStale += 1
                case .timing:
                    filteredRetrievalTiming += 1
                case .insufficientHistory:
                    filteredRetrievalHistory += 1
                }
                continue
            }

            let cooccurrenceScore = min(max(sessionSupport.cooccurrence[memory.id] ?? 0, 0), 1)
            let bundleScore = min(max(sessionSupport.bundle[memory.id] ?? 0, 0), 1)
            let orderingScore = min(max(sessionSupport.ordering[memory.id] ?? 0, 0), 1)
            if shouldSuppressForLikelyCompletedSession(
                completionConfidence: sessionSupport.completionConfidence,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore
            ) {
                filteredLikelyCompletedSession += 1
                continue
            }

            let completionPenalty = sessionCompletionPenalty(
                completionConfidence: sessionSupport.completionConfidence,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore
            )
            let retrievalScore = retrievalScore(
                for: memory,
                timingContext: timingContext,
                now: context.now,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore,
                completionPenalty: completionPenalty
            )
            guard retrievalScore >= minimumRetrievalScore(
                for: memory,
                timingContext: timingContext,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore,
                completionPenalty: completionPenalty
            ) else {
                filteredLowRetrievalScore += 1
                continue
            }

            retrieved.append(
                FoodSuggestionRetrievedMemory(
                    memory: memory,
                    context: timingContext,
                    retrievalScore: retrievalScore,
                    cooccurrenceScore: cooccurrenceScore,
                    bundleScore: bundleScore,
                    orderingScore: orderingScore,
                    completionPenalty: completionPenalty
                )
            )
        }

        let retrievedCandidates = Array(
            retrieved
                .sorted(by: isHigherPriorityRetrieval)
                .prefix(candidatePoolSize(for: limit))
        )

        var finalCandidates: [FoodSuggestionCandidate] = []

        for retrievedMemory in retrievedCandidates {
            if let failureReason = cameraEligibilityFailureReason(
                memory: retrievedMemory.memory,
                context: retrievedMemory.context,
                retrievalScore: retrievedMemory.retrievalScore,
                sessionAffinity: sessionAffinity(for: retrievedMemory),
                now: context.now
            ) {
                switch failureReason {
                case .negativeFeedback:
                    filteredNegativeFeedback += 1
                case .stale:
                    filteredStale += 1
                case .timing:
                    filteredFinalEligibility += 1
                }
                continue
            }

            let suggestionScore = cameraSuggestionScore(
                for: retrievedMemory.memory,
                context: retrievedMemory.context,
                retrievalScore: retrievedMemory.retrievalScore,
                cooccurrenceScore: retrievedMemory.cooccurrenceScore,
                bundleScore: retrievedMemory.bundleScore,
                orderingScore: retrievedMemory.orderingScore,
                completionPenalty: retrievedMemory.completionPenalty,
                now: context.now
            )
            guard suggestionScore >= minimumCameraSuggestionScore(
                for: retrievedMemory.memory,
                context: retrievedMemory.context,
                retrievalScore: retrievedMemory.retrievalScore,
                cooccurrenceScore: retrievedMemory.cooccurrenceScore,
                bundleScore: retrievedMemory.bundleScore,
                orderingScore: retrievedMemory.orderingScore
            ) else {
                filteredLowFinalScore += 1
                continue
            }

            if let candidate = candidate(for: retrievedMemory, context: context) {
                finalCandidates.append(candidate)
            }
        }

        let dedupedCandidates = deduplicate(
            finalCandidates.sorted {
                if $0.suggestion.relevanceScore != $1.suggestion.relevanceScore {
                    return $0.suggestion.relevanceScore > $1.suggestion.relevanceScore
                }
                return $0.suggestion.suggestedEntry.proteinGrams > $1.suggestion.suggestedEntry.proteinGrams
            }
        )
        let selectedCandidates = Array(
            dedupedCandidates.filter {
                !shouldSuppressBecauseAlreadySatisfiedToday(memory: $0.memory, context: context)
            }
            .prefix(limit)
        )

        return FoodSuggestionDebugSummary(
            bucket: context.bucket,
            totalMemories: memories.count,
            baseEligibleMemories: baseEligibleMemories,
            structuredMemories: memories.filter { ($0.qualitySignals?.proportionWithStructuredComponents ?? 0) > 0 }.count,
            bucketAlignedMemories: memories.filter {
                suggestionContext(for: $0, targetBucket: context.bucket, now: context.now).dominantBucket == context.bucket
                || memoryMealTimeBucket(for: $0) == context.bucket
            }.count,
            filteredAlreadySatisfiedToday: filteredAlreadySatisfiedToday,
            filteredNegativeFeedback: filteredNegativeFeedback,
            filteredStale: filteredStale,
            filteredRetrievalTiming: filteredRetrievalTiming,
            filteredRetrievalHistory: filteredRetrievalHistory,
            filteredLikelyCompletedSession: filteredLikelyCompletedSession,
            filteredLowRetrievalScore: filteredLowRetrievalScore,
            retrievedCandidateCount: retrievedCandidates.count,
            filteredFinalEligibility: filteredFinalEligibility,
            filteredLowFinalScore: filteredLowFinalScore,
            finalEligibleCount: selectedCandidates.count,
            shownSuggestionTitles: selectedCandidates.map(\.suggestion.title)
        )
    }

    private func makeContext(now: Date, entries: [FoodEntry], sessionID: UUID?) -> FoodSuggestionContext {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let historyWindowStart = calendar.date(byAdding: .day, value: -historyWindowDays, to: startOfToday) ?? startOfToday

        return FoodSuggestionContext(
            now: now,
            bucket: normalizationService.mealTimeBucket(for: now),
            sessionID: sessionID,
            sessionEntries: entries.filter { $0.sessionId == sessionID },
            todaysEntries: entries.filter { $0.loggedAt >= startOfToday && $0.loggedAt < endOfToday },
            recentEntries: entries.filter { $0.loggedAt >= historyWindowStart }
        )
    }

    private func candidate(
        for retrievedMemory: FoodSuggestionRetrievedMemory,
        context: FoodSuggestionContext
    ) -> FoodSuggestionCandidate? {
        let memory = retrievedMemory.memory
        let timingContext = retrievedMemory.context

        guard memory.status != .retired else { return nil }
        guard memory.observationCount >= 2 || memory.status == .confirmed || memory.confirmedReuseCount >= 1 else {
            return nil
        }
        guard let nutrition = memory.nutritionProfile else { return nil }

        let normalizedTitle = memory.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }

        let sessionAffinity = sessionAffinity(for: retrievedMemory)
        guard cameraEligibilityFailureReason(
            memory: memory,
            context: timingContext,
            retrievalScore: retrievedMemory.retrievalScore,
            sessionAffinity: sessionAffinity,
            now: context.now
        ) == nil else {
            return nil
        }

        let suggestionScore = cameraSuggestionScore(
            for: memory,
            context: timingContext,
            retrievalScore: retrievedMemory.retrievalScore,
            cooccurrenceScore: retrievedMemory.cooccurrenceScore,
            bundleScore: retrievedMemory.bundleScore,
            orderingScore: retrievedMemory.orderingScore,
            completionPenalty: retrievedMemory.completionPenalty,
            now: context.now
        )
        guard suggestionScore >= minimumCameraSuggestionScore(
            for: memory,
            context: timingContext,
            retrievalScore: retrievedMemory.retrievalScore,
            cooccurrenceScore: retrievedMemory.cooccurrenceScore,
            bundleScore: retrievedMemory.bundleScore,
            orderingScore: retrievedMemory.orderingScore
        ) else { return nil }

        let suggestionEmoji = memory.emoji?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? memory.emoji
            : "🍽️"
        let suggestedEntry = SuggestedFoodEntry(
            name: memory.displayName,
            calories: nutrition.medianCalories,
            proteinGrams: nutrition.medianProteinGrams,
            carbsGrams: nutrition.medianCarbsGrams,
            fatGrams: nutrition.medianFatGrams,
            fiberGrams: nutrition.medianFiberGrams,
            sugarGrams: nutrition.medianSugarGrams,
            servingSize: memory.servingProfile?.commonServingText,
            emoji: suggestionEmoji,
            components: suggestedComponents(from: memory),
            mealKind: memory.kind.rawValue,
            notes: "Built from foods you've logged before.",
            confidence: memory.status == .confirmed || memory.confidenceScore >= 0.85 ? "high" : "medium",
            schemaVersion: 2
        )

        return FoodSuggestionCandidate(
            memory: memory,
            suggestion: FoodSuggestion(
                memoryID: memory.id,
                title: memory.displayName,
                subtitle: contextualSubtitle(for: memory, context: timingContext),
                detail: "\(Int(nutrition.medianProteinGrams.rounded()))g protein • \(nutrition.medianCalories) cal",
                emoji: suggestionEmoji ?? "🍽️",
                relevanceScore: suggestionScore,
                suggestedEntry: suggestedEntry
            ),
            context: timingContext,
            retrievalScore: retrievedMemory.retrievalScore,
            cooccurrenceScore: retrievedMemory.cooccurrenceScore,
            bundleScore: retrievedMemory.bundleScore,
            orderingScore: retrievedMemory.orderingScore
        )
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

    private func retrieveCandidateMemories(
        from memories: [FoodMemory],
        context: FoodSuggestionContext,
        limit: Int
    ) -> [FoodSuggestionRetrievedMemory] {
        let sessionSupport = sessionSupportScores(memories: memories, context: context)
        let retrieved = memories.compactMap { memory -> FoodSuggestionRetrievedMemory? in
            guard baseSuggestionEligibility(memory) else { return nil }

            let timingContext = suggestionContext(for: memory, targetBucket: context.bucket, now: context.now)
            guard passesRetrievalEligibility(memory: memory, context: context, timingContext: timingContext) else {
                return nil
            }

            guard !shouldSuppressBecauseAlreadySatisfiedToday(memory: memory, context: context) else {
                return nil
            }

            let cooccurrenceScore = min(max(sessionSupport.cooccurrence[memory.id] ?? 0, 0), 1)
            let bundleScore = min(max(sessionSupport.bundle[memory.id] ?? 0, 0), 1)
            let orderingScore = min(max(sessionSupport.ordering[memory.id] ?? 0, 0), 1)
            if shouldSuppressForLikelyCompletedSession(
                completionConfidence: sessionSupport.completionConfidence,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore
            ) {
                return nil
            }

            let completionPenalty = sessionCompletionPenalty(
                completionConfidence: sessionSupport.completionConfidence,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore
            )
            let retrievalScore = retrievalScore(
                for: memory,
                timingContext: timingContext,
                now: context.now,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore,
                completionPenalty: completionPenalty
            )
            guard retrievalScore >= minimumRetrievalScore(
                for: memory,
                timingContext: timingContext,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore,
                completionPenalty: completionPenalty
            ) else {
                return nil
            }

            return FoodSuggestionRetrievedMemory(
                memory: memory,
                context: timingContext,
                retrievalScore: retrievalScore,
                cooccurrenceScore: cooccurrenceScore,
                bundleScore: bundleScore,
                orderingScore: orderingScore,
                completionPenalty: completionPenalty
            )
        }

        return retrieved
            .sorted(by: isHigherPriorityRetrieval)
            .prefix(candidatePoolSize(for: limit))
            .map { $0 }
    }

    private func deduplicate(_ candidates: [FoodSuggestionCandidate]) -> [FoodSuggestionCandidate] {
        var kept: [FoodSuggestionCandidate] = []

        for candidate in candidates {
            let isDuplicate = kept.contains { existing in
                matcher.representsSameHabit(existing.memory, candidate.memory)
            }
            if !isDuplicate {
                kept.append(candidate)
            }
        }

        return kept
    }
    private func shouldSuppressBecauseAlreadySatisfiedToday(
        memory: FoodMemory,
        context: FoodSuggestionContext
    ) -> Bool {
        let todaysMatches = context.todaysEntries.filter { matcher.matches(entry: $0, memory: memory) }
        guard !todaysMatches.isEmpty else { return false }

        let historyMatches = context.recentEntries.filter { entry in
            guard !Calendar.current.isDate(entry.loggedAt, inSameDayAs: context.now) else { return false }
            return matcher.matches(entry: entry, memory: memory)
        }
        let repeatProfile = repeatProfile(for: memory, fallbackEntries: historyMatches)
        let allowedSameDayUses = allowedSameDayUses(for: repeatProfile)

        guard todaysMatches.count < allowedSameDayUses else { return true }

        guard let medianRepeatGapMinutes = repeatProfile.medianRepeatGapMinutes,
              let lastLoggedAt = todaysMatches.map(\.loggedAt).max() else {
            return false
        }

        let minutesSinceLastLog = context.now.timeIntervalSince(lastLoggedAt) / 60
        let requiredGapMinutes = max(30, medianRepeatGapMinutes * 0.6)
        return minutesSinceLastLog < requiredGapMinutes
    }

    private func baseSuggestionEligibility(_ memory: FoodMemory) -> Bool {
        guard memory.status != .retired else { return false }
        guard memory.observationCount >= 2 || memory.status == .confirmed || memory.confirmedReuseCount >= 1 else {
            return false
        }
        guard memory.nutritionProfile != nil else { return false }
        return !memory.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func retrievalEligibilityFailureReason(
        memory: FoodMemory,
        context: FoodSuggestionContext,
        timingContext: FoodSuggestionTimingContext
    ) -> FoodSuggestionRetrievalFailureReason? {
        let distinctDays = memory.qualitySignals?.distinctObservationDays ?? memory.observationCount
        let hasStrongHabitHistory =
            memory.status == .confirmed ||
            distinctDays >= 5 ||
            memory.confirmedReuseCount >= 4 ||
            memory.confidenceScore >= 0.9

        if shouldSuppressForNegativeFeedback(memory: memory, now: context.now) {
            return .negativeFeedback
        }

        let daysSinceObserved = max(
            0,
            Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: context.now).day ?? 0
        )
        if daysSinceObserved > stalenessWindowDays(for: memory) {
            return .stale
        }

        if timingContext.isStronglyTimeBound {
            if !hasStrongHabitHistory,
               timingContext.hourWindowSupport < 0.04,
               timingContext.bucketSupport < 0.10 {
                return .timing
            }

            if let dominantBucket = timingContext.dominantBucket,
               dominantBucket != context.bucket,
               !isAdjacentMealBucket(dominantBucket, context.bucket),
               timingContext.dominantBucketShare >= 0.88,
               timingContext.bucketSupport < (hasStrongHabitHistory ? 0.06 : 0.10),
               timingContext.hourWindowSupport < (hasStrongHabitHistory ? 0.04 : 0.08) {
                return .timing
            }
        }

        if distinctDays < 2 && daysSinceObserved > 14 {
            return .insufficientHistory
        }

        return nil
    }

    private func passesRetrievalEligibility(
        memory: FoodMemory,
        context: FoodSuggestionContext,
        timingContext: FoodSuggestionTimingContext
    ) -> Bool {
        retrievalEligibilityFailureReason(
            memory: memory,
            context: context,
            timingContext: timingContext
        ) == nil
    }

    private func retrievalScore(
        for memory: FoodMemory,
        timingContext: FoodSuggestionTimingContext,
        now: Date,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double,
        completionPenalty: Double
    ) -> Double {
        let observationScore = min(Double(memory.observationCount) / 6, 1)
        let reuseScore = min(Double(memory.confirmedReuseCount) / 5, 1)
        let confidenceScore = min(max(memory.confidenceScore, 0), 1)
        let statusScore = memory.status == .confirmed ? 1.0 : 0.52
        let qualitySignals = memory.qualitySignals
        let qualityScore = min(
            max(
                ((qualitySignals?.proportionWithStructuredComponents ?? 0) * 0.55) +
                (min(Double(qualitySignals?.distinctObservationDays ?? 0), 6) / 6 * 0.25) +
                ((qualitySignals?.repeatedTimeBucketScore ?? 0) * 0.20),
                0
            ),
            1
        )

        let suggestionStats = memory.suggestionStats
        let interactionScore =
            (acceptanceScore(for: suggestionStats) * 0.6) +
            (tapScore(for: suggestionStats) * 0.4)
        let daysSinceObserved = max(
            0,
            Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: now).day ?? 0
        )
        let recencyWindow = max(stalenessWindowDays(for: memory), 1)
        let recencyScore = max(0, 1 - (Double(daysSinceObserved) / Double(recencyWindow)))
        let habitStrength = min(
            max(
                (observationScore * 0.35) +
                (reuseScore * 0.30) +
                (confidenceScore * 0.20) +
                (statusScore * 0.15),
                0
            ),
            1
        )

        return
            (timingContext.hourWindowSupport * 0.24) +
            (timingContext.bucketSupport * 0.22) +
            (timingContext.dayTypeSupport * 0.08) +
            (habitStrength * 0.16) +
            (qualityScore * 0.08) +
            (recencyScore * 0.08) +
            (interactionScore * 0.06) +
            (cooccurrenceScore * 0.08) +
            (bundleScore * 0.12) +
            (orderingScore * 0.10) -
            (completionPenalty * 0.18)
    }

    private func minimumRetrievalScore(
        for memory: FoodMemory,
        timingContext: FoodSuggestionTimingContext,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double,
        completionPenalty: Double
    ) -> Double {
        if bundleScore >= 0.5 {
            return 0.26
        }
        if orderingScore >= 0.55 {
            return 0.28
        }
        if bundleScore >= 0.35 {
            return 0.30
        }
        if completionPenalty >= 0.5 {
            return 0.46
        }
        let distinctDays = memory.qualitySignals?.distinctObservationDays ?? memory.observationCount
        if cooccurrenceScore >= 0.45 {
            return 0.30
        }
        if timingContext.isStronglyTimeBound {
            return 0.48
        }
        if memory.status == .confirmed && distinctDays >= 4 {
            return 0.34
        }
        return 0.40
    }

    private func stalenessWindowDays(for memory: FoodMemory) -> Int {
        let distinctDays = memory.qualitySignals?.distinctObservationDays ?? memory.observationCount
        let acceptedSuggestions = memory.suggestionStats?.timesAccepted ?? 0

        if acceptedSuggestions >= 2 {
            return 150
        }
        if memory.confirmedReuseCount >= 6 || distinctDays >= 6 {
            return 90
        }
        if memory.status == .confirmed {
            return 60
        }
        return 30
    }

    private func candidatePoolSize(for limit: Int) -> Int {
        min(max(limit * 4, 12), 24)
    }

    private func isHigherPriorityRetrieval(
        _ lhs: FoodSuggestionRetrievedMemory,
        _ rhs: FoodSuggestionRetrievedMemory
    ) -> Bool {
        if lhs.retrievalScore != rhs.retrievalScore {
            return lhs.retrievalScore > rhs.retrievalScore
        }
        if lhs.bundleScore != rhs.bundleScore {
            return lhs.bundleScore > rhs.bundleScore
        }
        if lhs.orderingScore != rhs.orderingScore {
            return lhs.orderingScore > rhs.orderingScore
        }
        if lhs.cooccurrenceScore != rhs.cooccurrenceScore {
            return lhs.cooccurrenceScore > rhs.cooccurrenceScore
        }
        if lhs.memory.observationCount != rhs.memory.observationCount {
            return lhs.memory.observationCount > rhs.memory.observationCount
        }
        if lhs.memory.confirmedReuseCount != rhs.memory.confirmedReuseCount {
            return lhs.memory.confirmedReuseCount > rhs.memory.confirmedReuseCount
        }
        return lhs.memory.updatedAt > rhs.memory.updatedAt
    }

    private func sessionSupportScores(
        memories: [FoodMemory],
        context: FoodSuggestionContext
    ) -> FoodSuggestionSessionSupport {
        guard let sessionID = context.sessionID else {
            return FoodSuggestionSessionSupport(
                cooccurrence: [:],
                bundle: [:],
                ordering: [:],
                completionConfidence: 0
            )
        }
        let anchorEntries = context.sessionEntries.filter { $0.sessionId == sessionID }
        guard !anchorEntries.isEmpty else {
            return FoodSuggestionSessionSupport(
                cooccurrence: [:],
                bundle: [:],
                ordering: [:],
                completionConfidence: 0
            )
        }

        let memoriesByID = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
        let sortedMemories = memories.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .confirmed
            }
            if lhs.observationCount != rhs.observationCount {
                return lhs.observationCount > rhs.observationCount
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let orderedAnchorMemoryIDs = orderedResolvedMemoryIDs(
            for: anchorEntries,
            memoriesByID: memoriesByID,
            sortedMemories: sortedMemories
        )
        let anchorMemoryIDs = Set(orderedAnchorMemoryIDs)
        guard !anchorMemoryIDs.isEmpty else {
            return FoodSuggestionSessionSupport(
                cooccurrence: [:],
                bundle: [:],
                ordering: [:],
                completionConfidence: 0
            )
        }

        let historicalSessions = historicalSessionGroups(
            from: context.recentEntries,
            excluding: sessionID,
            memoriesByID: memoriesByID,
            sortedMemories: sortedMemories
        )
        let calendar = Calendar.current
        var scores: [UUID: Double] = [:]

        for sessionGroup in historicalSessions {
            let sessionMemoryIDs = sessionGroup.memoryIDs
            let sharedAnchors = anchorMemoryIDs.intersection(sessionMemoryIDs)
            guard !sharedAnchors.isEmpty else { continue }

            let otherMemoryIDs = sessionMemoryIDs.subtracting(anchorMemoryIDs)
            guard !otherMemoryIDs.isEmpty else { continue }

            let daysSinceSession = max(
                0,
                calendar.dateComponents([.day], from: sessionGroup.lastLoggedAt, to: context.now).day ?? 0
            )
            let recencyWeight = max(0.2, 1 - (Double(daysSinceSession) / Double(historyWindowDays)))
            let overlapWeight = min(Double(sharedAnchors.count) / Double(max(anchorMemoryIDs.count, 1)), 1)
            let sessionWeight = max(0.3, (recencyWeight * 0.65) + (overlapWeight * 0.35))

            for memoryID in otherMemoryIDs {
                scores[memoryID, default: 0] += sessionWeight
            }
        }

        return FoodSuggestionSessionSupport(
            cooccurrence: scores.mapValues { min($0, 1) },
            bundle: bundleSupportScores(
                anchorMemoryIDs: anchorMemoryIDs,
                historicalSessions: historicalSessions,
                now: context.now
            ),
            ordering: orderingSupportScores(
                orderedAnchorMemoryIDs: orderedAnchorMemoryIDs,
                historicalSessions: historicalSessions,
                now: context.now
            ),
            completionConfidence: sessionCompletionConfidence(
                orderedAnchorMemoryIDs: orderedAnchorMemoryIDs,
                historicalSessions: historicalSessions,
                now: context.now
            )
        )
    }

    private func historicalSessionGroups(
        from entries: [FoodEntry],
        excluding excludedSessionID: UUID,
        memoriesByID: [UUID: FoodMemory],
        sortedMemories: [FoodMemory]
    ) -> [FoodSuggestionSessionGroup] {
        Dictionary(grouping: entries) { $0.sessionId }
            .compactMap { sessionID, sessionEntries in
                guard let sessionID, sessionID != excludedSessionID else { return nil }
                guard sessionEntries.count > 1 else { return nil }

                let memoryIDs = Set(
                    sessionEntries.compactMap {
                        resolvedMemoryID(for: $0, memoriesByID: memoriesByID, sortedMemories: sortedMemories)
                    }
                )
                guard memoryIDs.count > 1 else { return nil }
                let orderedMemoryIDs = orderedResolvedMemoryIDs(
                    for: sessionEntries,
                    memoriesByID: memoriesByID,
                    sortedMemories: sortedMemories
                )
                guard orderedMemoryIDs.count > 1 else { return nil }

                return FoodSuggestionSessionGroup(
                    memoryIDs: memoryIDs,
                    orderedMemoryIDs: orderedMemoryIDs,
                    itemCount: orderedMemoryIDs.count,
                    lastLoggedAt: sessionEntries.map(\.loggedAt).max() ?? .distantPast
                )
            }
    }

    private func orderedResolvedMemoryIDs(
        for entries: [FoodEntry],
        memoriesByID: [UUID: FoodMemory],
        sortedMemories: [FoodMemory]
    ) -> [UUID] {
        let orderedEntries = entries.sorted { lhs, rhs in
            if lhs.sessionOrder != rhs.sessionOrder {
                return lhs.sessionOrder < rhs.sessionOrder
            }
            if lhs.loggedAt != rhs.loggedAt {
                return lhs.loggedAt < rhs.loggedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var seen: Set<UUID> = []
        var orderedMemoryIDs: [UUID] = []

        for entry in orderedEntries {
            guard let memoryID = resolvedMemoryID(for: entry, memoriesByID: memoriesByID, sortedMemories: sortedMemories) else {
                continue
            }
            if seen.insert(memoryID).inserted {
                orderedMemoryIDs.append(memoryID)
            }
        }

        return orderedMemoryIDs
    }

    private func bundleSupportScores(
        anchorMemoryIDs: Set<UUID>,
        historicalSessions: [FoodSuggestionSessionGroup],
        now: Date
    ) -> [UUID: Double] {
        guard anchorMemoryIDs.count >= 2 else { return [:] }

        struct BundleAccumulator {
            let extraMemoryIDs: Set<UUID>
            var totalWeight: Double
            var occurrences: Int
        }

        let calendar = Calendar.current
        var accumulators: [String: BundleAccumulator] = [:]

        for sessionGroup in historicalSessions {
            guard anchorMemoryIDs.isSubset(of: sessionGroup.memoryIDs) else { continue }

            let extraMemoryIDs = sessionGroup.memoryIDs.subtracting(anchorMemoryIDs)
            guard !extraMemoryIDs.isEmpty else { continue }
            guard extraMemoryIDs.count <= 2 else { continue }

            let daysSinceSession = max(
                0,
                calendar.dateComponents([.day], from: sessionGroup.lastLoggedAt, to: now).day ?? 0
            )
            let recencyWeight = max(0.25, 1 - (Double(daysSinceSession) / Double(historyWindowDays)))
            let compactnessWeight = extraMemoryIDs.count == 1 ? 1.0 : 0.84
            let sessionWeight = max(0.35, (recencyWeight * 0.75) + (compactnessWeight * 0.25))
            let key = extraMemoryIDs.map(\.uuidString).sorted().joined(separator: "|")

            if var existing = accumulators[key] {
                existing.totalWeight += sessionWeight
                existing.occurrences += 1
                accumulators[key] = existing
            } else {
                accumulators[key] = BundleAccumulator(
                    extraMemoryIDs: extraMemoryIDs,
                    totalWeight: sessionWeight,
                    occurrences: 1
                )
            }
        }

        var bundleScores: [UUID: Double] = [:]

        for accumulator in accumulators.values {
            guard accumulator.occurrences >= 2 || accumulator.totalWeight >= 1.35 else { continue }

            let recurrenceScore = min(Double(accumulator.occurrences) / 3, 1)
            let averageSessionWeight = accumulator.totalWeight / Double(max(accumulator.occurrences, 1))
            let bundleStrength = min(
                max((averageSessionWeight * 0.55) + (recurrenceScore * 0.45), 0),
                1
            )

            for memoryID in accumulator.extraMemoryIDs {
                bundleScores[memoryID] = max(bundleScores[memoryID] ?? 0, bundleStrength)
            }
        }

        return bundleScores
    }

    private func orderingSupportScores(
        orderedAnchorMemoryIDs: [UUID],
        historicalSessions: [FoodSuggestionSessionGroup],
        now: Date
    ) -> [UUID: Double] {
        guard !orderedAnchorMemoryIDs.isEmpty else { return [:] }

        let calendar = Calendar.current
        var scores: [UUID: Double] = [:]

        for sessionGroup in historicalSessions {
            guard sessionGroup.orderedMemoryIDs.starts(with: orderedAnchorMemoryIDs) else { continue }
            guard sessionGroup.orderedMemoryIDs.count > orderedAnchorMemoryIDs.count else { continue }

            let nextMemoryID = sessionGroup.orderedMemoryIDs[orderedAnchorMemoryIDs.count]
            let remainingItemCount = sessionGroup.itemCount - orderedAnchorMemoryIDs.count
            let daysSinceSession = max(
                0,
                calendar.dateComponents([.day], from: sessionGroup.lastLoggedAt, to: now).day ?? 0
            )
            let recencyWeight = max(0.25, 1 - (Double(daysSinceSession) / Double(historyWindowDays)))
            let immediacyWeight = remainingItemCount == 1 ? 1.0 : 0.72
            let sessionWeight = max(0.35, (recencyWeight * 0.7) + (immediacyWeight * 0.3))
            scores[nextMemoryID, default: 0] += sessionWeight
        }

        return scores.mapValues { min($0, 1) }
    }

    private func sessionCompletionConfidence(
        orderedAnchorMemoryIDs: [UUID],
        historicalSessions: [FoodSuggestionSessionGroup],
        now: Date
    ) -> Double {
        guard orderedAnchorMemoryIDs.count >= 2 else { return 0 }

        let calendar = Calendar.current
        var exactWeight: Double = 0
        var totalWeight: Double = 0
        var matchingSessions = 0

        for sessionGroup in historicalSessions where sessionGroup.orderedMemoryIDs.starts(with: orderedAnchorMemoryIDs) {
            let daysSinceSession = max(
                0,
                calendar.dateComponents([.day], from: sessionGroup.lastLoggedAt, to: now).day ?? 0
            )
            let recencyWeight = max(0.25, 1 - (Double(daysSinceSession) / Double(historyWindowDays)))
            totalWeight += recencyWeight
            matchingSessions += 1

            if sessionGroup.itemCount == orderedAnchorMemoryIDs.count {
                exactWeight += recencyWeight
            }
        }

        guard matchingSessions >= 2, totalWeight > 0 else { return 0 }
        return min(max(exactWeight / totalWeight, 0), 1)
    }

    private func sessionCompletionPenalty(
        completionConfidence: Double,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double
    ) -> Double {
        let sessionAffinity = max(cooccurrenceScore, bundleScore, orderingScore)
        return min(max(completionConfidence * max(0, 1 - (sessionAffinity * 1.15)), 0), 1)
    }

    private func shouldSuppressForLikelyCompletedSession(
        completionConfidence: Double,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double
    ) -> Bool {
        let sessionAffinity = max(cooccurrenceScore, bundleScore, orderingScore)
        if completionConfidence >= 0.82 && sessionAffinity < 0.18 {
            return true
        }
        if completionConfidence >= 0.68 && sessionAffinity < 0.08 {
            return true
        }
        return false
    }

    private func resolvedMemoryID(
        for entry: FoodEntry,
        memoriesByID: [UUID: FoodMemory],
        sortedMemories: [FoodMemory]
    ) -> UUID? {
        if let memoryIDString = entry.foodMemoryIdString,
           let memoryID = UUID(uuidString: memoryIDString),
           memoriesByID[memoryID] != nil {
            return memoryID
        }

        return sortedMemories.first(where: { matcher.matches(entry: entry, memory: $0) })?.id
    }

    private func repeatProfile(
        for memory: FoodMemory,
        fallbackEntries: [FoodEntry]
    ) -> FoodSuggestionRepeatProfile {
        if let repeatPattern = memory.repeatPattern {
            return FoodSuggestionRepeatProfile(
                distinctDays: repeatPattern.distinctConsumptionDays,
                daysWithMultipleUses: repeatPattern.daysWithMultipleUses,
                maxUsesInDay: repeatPattern.maxUsesInDay,
                averageUsesPerDay: repeatPattern.averageUsesPerDay,
                medianRepeatGapMinutes: repeatPattern.averageRepeatGapMinutes
            )
        }

        return repeatProfile(for: fallbackEntries)
    }

    private func allowedSameDayUses(for profile: FoodSuggestionRepeatProfile) -> Int {
        guard profile.distinctDays >= 3 else { return 1 }

        let repeatRate = profile.distinctDays > 0
            ? Double(profile.daysWithMultipleUses) / Double(profile.distinctDays)
            : 0

        if repeatRate < 0.2 {
            return 1
        }

        if profile.averageUsesPerDay >= 2.4 || profile.daysWithMultipleUses >= 4 {
            return max(2, min(profile.maxUsesInDay, 3))
        }

        if repeatRate >= 0.4 {
            return 2
        }

        return 1
    }

    private func repeatProfile(for entries: [FoodEntry]) -> FoodSuggestionRepeatProfile {
        guard !entries.isEmpty else {
            return FoodSuggestionRepeatProfile(
                distinctDays: 0,
                daysWithMultipleUses: 0,
                maxUsesInDay: 1,
                averageUsesPerDay: 0,
                medianRepeatGapMinutes: nil
            )
        }

        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.loggedAt) }
        let usesPerDay = groupedByDay.values.map(\.count)
        let daysWithMultipleUses = usesPerDay.filter { $0 > 1 }.count

        var repeatGaps: [Double] = []
        for dayEntries in groupedByDay.values {
            let sortedEntries = dayEntries.sorted { $0.loggedAt < $1.loggedAt }
            guard sortedEntries.count > 1 else { continue }
            for pair in zip(sortedEntries, sortedEntries.dropFirst()) {
                repeatGaps.append(pair.1.loggedAt.timeIntervalSince(pair.0.loggedAt) / 60)
            }
        }

        let medianGapMinutes: Double?
        if repeatGaps.isEmpty {
            medianGapMinutes = nil
        } else {
            let sortedGaps = repeatGaps.sorted()
            medianGapMinutes = sortedGaps[sortedGaps.count / 2]
        }

        return FoodSuggestionRepeatProfile(
            distinctDays: groupedByDay.count,
            daysWithMultipleUses: daysWithMultipleUses,
            maxUsesInDay: usesPerDay.max() ?? 1,
            averageUsesPerDay: Double(entries.count) / Double(max(groupedByDay.count, 1)),
            medianRepeatGapMinutes: medianGapMinutes
        )
    }

    private func memoryMealTimeBucket(for memory: FoodMemory) -> MealTimeBucket? {
        if let dominantBucket = memory.timeProfile.flatMap(dominantBucket(in:)) {
            return dominantBucket
        }
        return memory.fingerprints
            .first(where: { $0.type == .mealTimeBucket })
            .flatMap { MealTimeBucket(rawValue: $0.value) }
    }

    private func suggestedComponents(from memory: FoodMemory) -> [SuggestedFoodComponent] {
        memory.components.map { component in
            SuggestedFoodComponent(
                id: component.normalizedName,
                displayName: displayName(forNormalizedComponent: component.normalizedName),
                role: component.role.rawValue,
                quantity: nil,
                unit: nil,
                calories: component.typicalCalories,
                proteinGrams: component.typicalProteinGrams,
                carbsGrams: component.typicalCarbsGrams,
                fatGrams: component.typicalFatGrams,
                confidence: memory.status == .confirmed ? "high" : "medium"
            )
        }
    }

    private func displayName(forNormalizedComponent normalizedName: String) -> String {
        normalizedName
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func mealLabel(for bucket: MealTimeBucket) -> String {
        switch bucket {
        case .breakfast:
            return "Usually mornings"
        case .lunch:
            return "Usually at lunch"
        case .dinner:
            return "Usually at dinner"
        case .lateNight:
            return "Usually late at night"
        case .snack:
            return "Usually as a snack"
        }
    }

    private func contextualSubtitle(
        for memory: FoodMemory,
        context: FoodSuggestionTimingContext
    ) -> String {
        let dayTypeLabel = dayTypeLabel(for: memory.timeProfile)
        let mealLabel = mealLabel(for: context.bucket)

        if let dayTypeLabel {
            return "\(dayTypeLabel) • \(mealLabel.lowercased())"
        }
        return mealLabel
    }

    private func cameraEligibilityFailureReason(
        memory: FoodMemory,
        context: FoodSuggestionTimingContext,
        retrievalScore: Double,
        sessionAffinity: Double,
        now: Date
    ) -> FoodSuggestionCameraFailureReason? {
        let distinctDays = memory.qualitySignals?.distinctObservationDays ?? memory.observationCount
        let hasStrongHabitHistory =
            memory.status == .confirmed ||
            distinctDays >= 5 ||
            memory.confirmedReuseCount >= 4 ||
            memory.confidenceScore >= 0.9

        if shouldSuppressForNegativeFeedback(memory: memory, now: now) {
            return .negativeFeedback
        }

        let daysSinceObserved = max(0, Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: now).day ?? 0)
        if daysSinceObserved > 45, memory.confirmedReuseCount == 0 {
            return .stale
        }

        let hasStrongRescueSignal = retrievalScore >= 0.54 || sessionAffinity >= 0.28 || hasStrongHabitHistory
        guard memory.timeProfile != nil else {
            return (memory.status == .confirmed || memory.observationCount >= 3) ? nil : .timing
        }

        if context.isStronglyTimeBound {
            let minimumHourSupport = hasStrongRescueSignal ? 0.04 : 0.08
            let minimumBucketSupport = hasStrongRescueSignal ? 0.08 : 0.14
            if context.hourWindowSupport < minimumHourSupport && context.bucketSupport < minimumBucketSupport {
                return .timing
            }

            if let dominantBucket = context.dominantBucket,
               dominantBucket != context.bucket,
               !isAdjacentMealBucket(dominantBucket, context.bucket),
               context.dominantBucketShare >= (hasStrongRescueSignal ? 0.9 : 0.78),
               context.bucketSupport < (hasStrongRescueSignal ? 0.06 : 0.14),
               context.hourWindowSupport < (hasStrongRescueSignal ? 0.04 : 0.08) {
                return .timing
            }

            if context.dominantHourWindowShare >= 0.72 && context.hourWindowSupport < (hasStrongRescueSignal ? 0.04 : 0.08) {
                return .timing
            }
        }

        if context.bucket == .lateNight,
           context.dominantBucket == .breakfast,
           context.bucketSupport < (hasStrongRescueSignal ? 0.08 : 0.16),
           context.hourWindowSupport < (hasStrongRescueSignal ? 0.04 : 0.08) {
            return .timing
        }

        let finalHourSupport = hasStrongRescueSignal ? 0.03 : 0.06
        let finalBucketSupport = hasStrongRescueSignal ? 0.07 : 0.12
        return context.hourWindowSupport >= finalHourSupport || context.bucketSupport >= finalBucketSupport || !context.isStronglyTimeBound
            ? nil
            : .timing
    }

    private func cameraSuggestionScore(
        for memory: FoodMemory,
        context: FoodSuggestionTimingContext,
        retrievalScore: Double,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double,
        completionPenalty: Double,
        now: Date
    ) -> Double {
        let confidenceScore = min(max(memory.confidenceScore, 0), 1)
        let observationScore = min(Double(memory.observationCount) / 5, 1)
        let reuseScore = min(Double(memory.confirmedReuseCount) / 4, 1)
        let qualitySignals = memory.qualitySignals
        let suggestionStats = memory.suggestionStats
        let structuredScore = min(max(qualitySignals?.proportionWithStructuredComponents ?? 0, 0), 1)
        let timeConsistencyScore = min(max(qualitySignals?.repeatedTimeBucketScore ?? 0, 0), 1)
        let tapScore = tapScore(for: suggestionStats)
        let acceptanceScore = acceptanceScore(for: suggestionStats)
        let dismissalPenalty = dismissalPenalty(for: suggestionStats)
        let ignoredPenalty = ignoredPenalty(for: suggestionStats)
        let refinementPenalty = refinementPenalty(for: suggestionStats)

        let daysSinceObserved = max(0, Calendar.current.dateComponents([.day], from: memory.lastObservedAt, to: now).day ?? 0)
        let recencyScore = max(0, 1 - min(Double(daysSinceObserved), 21) / 21)
        let statusBonus = memory.status == .confirmed ? 1.0 : 0.58

        return
            (context.hourWindowSupport * 0.22) +
            (context.bucketSupport * 0.14) +
            (context.dayTypeSupport * 0.06) +
            (confidenceScore * 0.12) +
            (observationScore * 0.12) +
            (reuseScore * 0.09) +
            (acceptanceScore * 0.04) +
            (tapScore * 0.03) +
            (structuredScore * 0.08) +
            (timeConsistencyScore * 0.04) +
            (recencyScore * 0.03) +
            (statusBonus * 0.02) -
            (completionPenalty * 0.05) +
            (retrievalScore * 0.12) +
            (cooccurrenceScore * 0.04) +
            (bundleScore * 0.06) +
            (orderingScore * 0.05) -
            (dismissalPenalty * 0.05) -
            (ignoredPenalty * 0.05) -
            (refinementPenalty * 0.04)
    }

    private func minimumCameraSuggestionScore(
        for memory: FoodMemory,
        context: FoodSuggestionTimingContext,
        retrievalScore: Double,
        cooccurrenceScore: Double,
        bundleScore: Double,
        orderingScore: Double
    ) -> Double {
        var threshold = 0.60
        let structuredShare = memory.qualitySignals?.proportionWithStructuredComponents ?? 0
        let distinctDays = memory.qualitySignals?.distinctObservationDays ?? memory.observationCount
        let sessionAffinity = max(cooccurrenceScore, bundleScore, orderingScore)

        if memory.status == .confirmed && distinctDays >= 4 {
            threshold -= 0.03
        }
        if structuredShare >= 0.7 {
            threshold -= 0.02
        }
        if retrievalScore >= 0.62 {
            threshold -= 0.03
        }
        if memory.confirmedReuseCount >= 4 || memory.confidenceScore >= 0.9 {
            threshold -= 0.02
        }
        if bundleScore >= 0.4 || orderingScore >= 0.45 {
            threshold -= 0.05
        } else if sessionAffinity >= 0.3 {
            threshold -= 0.03
        }
        if context.isStronglyTimeBound && context.hourWindowSupport < 0.04 && context.bucketSupport < 0.08 {
            threshold += 0.03
        }

        return min(max(threshold, 0.5), 0.68)
    }

    private func suggestionContext(
        for memory: FoodMemory,
        targetBucket: MealTimeBucket,
        now: Date
    ) -> FoodSuggestionTimingContext {
        guard let timeProfile = memory.timeProfile else {
            let fallbackBucket = memoryMealTimeBucket(for: memory) ?? targetBucket
            let bucketSupport: Double
            switch (fallbackBucket, targetBucket) {
            case let (bucket, target) where bucket == target:
                bucketSupport = 1
            case (.lateNight, .dinner), (.dinner, .lateNight):
                bucketSupport = 0.42
            default:
                bucketSupport = 0.14
            }

            return FoodSuggestionTimingContext(
                bucket: fallbackBucket,
                bucketSupport: bucketSupport,
                hourWindowSupport: bucketSupport,
                dayTypeSupport: 0.5,
                dominantBucket: fallbackBucket,
                dominantBucketShare: bucketSupport,
                dominantHourWindowShare: bucketSupport,
                isStronglyTimeBound: false
            )
        }

        let totalObservations = max(1, timeProfile.hourCounts.reduce(0, +))
        let targetHour = Calendar.current.component(.hour, from: now)
        let targetDayTypeIsWeekend = Calendar.current.isDateInWeekend(now)
        let targetBucketSupport = support(for: targetBucket, in: timeProfile, totalObservations: totalObservations)
        let targetHourSupport = hourWindowSupport(for: targetHour, in: timeProfile, totalObservations: totalObservations)
        let dominantBucket = dominantBucket(in: timeProfile)
        let dominantBucketShare = dominantBucket.flatMap {
            timeProfile.bucketCounts[$0.rawValue]
        }.map { Double($0) / Double(totalObservations) } ?? 0
        let dominantHourWindowShare = dominantHourWindowSupport(in: timeProfile, totalObservations: totalObservations)

        return FoodSuggestionTimingContext(
            bucket: targetBucketSupport > 0.12 ? targetBucket : (dominantBucket ?? targetBucket),
            bucketSupport: targetBucketSupport,
            hourWindowSupport: targetHourSupport,
            dayTypeSupport: dayTypeSupport(forWeekend: targetDayTypeIsWeekend, in: timeProfile, totalObservations: totalObservations),
            dominantBucket: dominantBucket,
            dominantBucketShare: dominantBucketShare,
            dominantHourWindowShare: dominantHourWindowShare,
            isStronglyTimeBound: dominantBucketShare >= 0.68 || dominantHourWindowShare >= 0.58
        )
    }

    private func support(
        for bucket: MealTimeBucket,
        in profile: FoodMemoryTimeProfile,
        totalObservations: Int
    ) -> Double {
        Double(profile.bucketCounts[bucket.rawValue, default: 0]) / Double(totalObservations)
    }

    private func hourWindowSupport(
        for hour: Int,
        in profile: FoodMemoryTimeProfile,
        totalObservations: Int
    ) -> Double {
        guard !profile.hourCounts.isEmpty else { return 0 }

        let indexes = [-1, 0, 1].map { offset in
            (hour + offset + 24) % 24
        }
        let count = indexes.reduce(0) { partialResult, index in
            partialResult + profile.hourCounts[index]
        }
        return Double(count) / Double(totalObservations)
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

    private func dominantHourWindowSupport(
        in profile: FoodMemoryTimeProfile,
        totalObservations: Int
    ) -> Double {
        guard !profile.hourCounts.isEmpty else { return 0 }
        var bestCount = 0
        for hour in 0..<24 {
            let windowCount = [-1, 0, 1].reduce(0) { partialResult, offset in
                partialResult + profile.hourCounts[(hour + offset + 24) % 24]
            }
            bestCount = max(bestCount, windowCount)
        }
        return Double(bestCount) / Double(totalObservations)
    }

    private func dayTypeSupport(
        forWeekend isWeekend: Bool,
        in profile: FoodMemoryTimeProfile,
        totalObservations: Int
    ) -> Double {
        let count = isWeekend ? profile.weekendCount : profile.weekdayCount
        return Double(count) / Double(totalObservations)
    }

    private func dayTypeLabel(for profile: FoodMemoryTimeProfile?) -> String? {
        guard let profile else { return nil }
        let total = max(1, profile.weekdayCount + profile.weekendCount)
        let weekdayShare = Double(profile.weekdayCount) / Double(total)
        let weekendShare = Double(profile.weekendCount) / Double(total)

        if weekdayShare >= 0.72 {
            return "Usually weekdays"
        }
        if weekendShare >= 0.72 {
            return "Usually weekends"
        }
        return nil
    }

    private func isAdjacentMealBucket(_ lhs: MealTimeBucket, _ rhs: MealTimeBucket) -> Bool {
        switch (lhs, rhs) {
        case (.dinner, .lateNight), (.lateNight, .dinner),
             (.breakfast, .snack), (.snack, .breakfast),
             (.lunch, .snack), (.snack, .lunch),
             (.dinner, .snack), (.snack, .dinner):
            return true
        default:
            return false
        }
    }

    private func shouldSuppressForNegativeFeedback(memory: FoodMemory, now: Date) -> Bool {
        guard let stats = memory.suggestionStats else { return false }

        if isRepeatedlyDismissedWithoutEngagement(stats) {
            return true
        }

        guard let lastDismissedAt = stats.lastDismissedAt else { return false }
        let hoursSinceLastDismissal = now.timeIntervalSince(lastDismissedAt) / 3600
        let cooldownHours = stats.timesDismissed >= 3 ? 24.0 : 6.0
        return hoursSinceLastDismissal < cooldownHours
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

    private func tapScore(for stats: FoodMemorySuggestionStats?) -> Double {
        guard let stats else { return 0.5 }
        guard stats.timesShown >= 3 else { return 0.5 }
        return min(Double(stats.timesTapped) / Double(max(stats.timesShown, 1)), 1)
    }

    private func acceptanceScore(for stats: FoodMemorySuggestionStats?) -> Double {
        guard let stats else { return 0.5 }
        guard stats.timesShown >= 3 else { return 0.5 }

        if stats.timesTapped > 0 {
            return min(Double(stats.timesAccepted) / Double(stats.timesTapped), 1)
        }

        return min(Double(stats.timesAccepted) / Double(max(stats.timesShown, 1)), 1)
    }

    private func dismissalPenalty(for stats: FoodMemorySuggestionStats?) -> Double {
        guard let stats else { return 0 }
        guard stats.timesShown >= 3 else { return 0 }
        return min(Double(stats.timesDismissed) / Double(max(stats.timesShown, 1)), 1)
    }

    private func ignoredPenalty(for stats: FoodMemorySuggestionStats?) -> Double {
        guard let stats else { return 0 }
        guard stats.timesShown >= 3 else { return 0 }

        let engagedShows = max(stats.timesTapped, stats.timesAccepted)
        let ignoredShows = max(stats.timesShown - engagedShows, 0)
        return min(Double(ignoredShows) / 6, 1)
    }

    private func isRepeatedlyDismissedWithoutEngagement(_ stats: FoodMemorySuggestionStats) -> Bool {
        guard stats.timesTapped == 0, stats.timesAccepted == 0 else { return false }
        return stats.timesDismissed >= 3
    }

    private func refinementPenalty(for stats: FoodMemorySuggestionStats?) -> Double {
        guard let stats else { return 0 }
        guard stats.timesAccepted >= 2 else { return 0 }
        return min(Double(stats.timesRefined) / Double(max(stats.timesAccepted, 1)), 1)
    }

    private func sessionAffinity(for retrievedMemory: FoodSuggestionRetrievedMemory) -> Double {
        max(retrievedMemory.cooccurrenceScore, retrievedMemory.bundleScore, retrievedMemory.orderingScore)
    }
}
