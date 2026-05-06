import Foundation

struct FoodPatternSuggestion: Identifiable, Sendable, Equatable {
    let id: String
    let pattern: FoodPattern
    let source: FoodPatternSuggestionSource
    let score: Double
    let features: FoodPatternRankingFeatures
    let provenance: FoodPatternSuggestionProvenance
    let suggestedEntry: SuggestedFoodEntry
}

enum FoodPatternSuggestionSource: String, Sendable {
    case likelyNow
    case continueSession
    case recentAgain
}

struct FoodPatternSuggestionProvenance: Sendable, Equatable {
    let patternID: String
    let sourceObservationIDs: [UUID]
    let sourceEntryIDs: [UUID]
    let sourceTitles: [String]
    let sourceLoggedAt: [Date]
    let matchedCurrentSessionEntryIDs: [UUID]
    let reasonCodes: [String]
}

struct FoodPatternRankingFeatures: Sendable, Equatable {
    let repetition: Double
    let recency: Double
    let timeSupport: Double
    let dayTypeSupport: Double
    let sessionSupport: Double
    let patternConfidence: Double
    let practicalUtility: Double
    let positiveFeedback: Double
    let negativeFeedbackPenalty: Double
    let sourceBoost: Double
}

struct FoodPatternRecommendationResult: Sendable, Equatable {
    let suggestions: [FoodPatternSuggestion]
    let debugReport: FoodPatternRecommendationDebugReport
}

struct FoodPatternRecommendationDebugReport: Sendable, Equatable {
    let observationCount: Int
    let patternCount: Int
    let eligiblePatternCount: Int
    let candidateCountBySource: [FoodPatternSuggestionSource: Int]
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowConfidenceCount: Int
    let finalShownTitles: [String]
    let provenanceByTitle: [String: FoodPatternSuggestionProvenance]
}

struct FoodPatternRecommendationEngine {
    private let observationBuilder = FoodObservationBuilder()
    private let patternBuilder = FoodPatternBuilder()
    private let ranker = FoodPatternRanker()

    func recommendationsSync(for request: FoodRecommendationRequest) -> FoodPatternRecommendationResult {
        guard request.limit > 0 else {
            return FoodPatternRecommendationResult(suggestions: [], debugReport: emptyDebugReport())
        }

        let observations = observationBuilder
            .observations(from: request.entries)
            .filter { $0.loggedAt < request.targetDate }
        let patterns = patternBuilder.patterns(from: observations, memories: request.memories)
        let context = FoodPatternRecommendationContext(
            now: request.now,
            targetDate: request.targetDate,
            sessionID: request.sessionID,
            limit: request.limit,
            observations: observations
        )
        let candidates = buildCandidates(patterns: patterns, context: context)
        let ranked = ranker.rank(candidates, context: context)
        let diagnostics = ranker.diagnostics(for: candidates, context: context)

        return FoodPatternRecommendationResult(
            suggestions: Array(ranked.prefix(request.limit)),
            debugReport: FoodPatternRecommendationDebugReport(
                observationCount: observations.count,
                patternCount: patterns.count,
                eligiblePatternCount: Set(candidates.map(\.pattern.id)).count,
                candidateCountBySource: Dictionary(grouping: candidates, by: \.source).mapValues(\.count),
                suppressedOneOffCount: diagnostics.suppressedOneOffCount,
                suppressedAlreadyTodayCount: diagnostics.suppressedAlreadyTodayCount,
                suppressedNegativeFeedbackCount: diagnostics.suppressedNegativeFeedbackCount,
                suppressedLowConfidenceCount: diagnostics.suppressedLowConfidenceCount,
                finalShownTitles: ranked.prefix(request.limit).map(\.suggestedEntry.name),
                provenanceByTitle: ranked.prefix(request.limit).reduce(into: [:]) { output, suggestion in
                    output[suggestion.suggestedEntry.name] = suggestion.provenance
                }
            )
        )
    }

    private func buildCandidates(
        patterns: [FoodPattern],
        context: FoodPatternRecommendationContext
    ) -> [FoodPatternSuggestion] {
        var candidates: [FoodPatternSuggestion] = []
        for pattern in patterns {
            if qualifiesForRepeatedSuggestion(pattern) {
                candidates.append(candidate(pattern: pattern, source: .likelyNow, sourceBoost: 0.08, context: context))
            }

            if qualifiesForRecentSuggestion(pattern, targetDate: context.targetDate) {
                candidates.append(candidate(pattern: pattern, source: .recentAgain, sourceBoost: 0.04, context: context))
            }

            let support = FoodPatternRanker.sessionSupport(for: pattern, context: context)
            if support > 0 {
                candidates.append(candidate(pattern: pattern, source: .continueSession, sourceBoost: min(0.18, support * 0.18), context: context))
            }
        }
        return candidates
    }

    private func qualifiesForRepeatedSuggestion(_ pattern: FoodPattern) -> Bool {
        pattern.distinctDays >= 2
            && pattern.observationCount >= 2
            || pattern.feedbackProfile.timesAccepted > 0
            || pattern.feedbackProfile.timesRefined > 0
    }

    private func qualifiesForRecentSuggestion(_ pattern: FoodPattern, targetDate: Date) -> Bool {
        guard qualifiesForRepeatedSuggestion(pattern) else { return false }
        let daysSinceLast = Calendar.current.dateComponents([.day], from: pattern.lastObservedAt, to: targetDate).day ?? 999
        return daysSinceLast >= 0 && daysSinceLast <= 14
    }

    private func candidate(
        pattern: FoodPattern,
        source: FoodPatternSuggestionSource,
        sourceBoost: Double,
        context: FoodPatternRecommendationContext
    ) -> FoodPatternSuggestion {
        let features = ranker.features(for: pattern, sourceBoost: sourceBoost, context: context)
        return FoodPatternSuggestion(
            id: "\(pattern.id)|\(source.rawValue)",
            pattern: pattern,
            source: source,
            score: ranker.score(features),
            features: features,
            provenance: provenance(for: pattern, source: source, context: context),
            suggestedEntry: suggestedEntry(for: pattern)
        )
    }

    private func provenance(
        for pattern: FoodPattern,
        source: FoodPatternSuggestionSource,
        context: FoodPatternRecommendationContext
    ) -> FoodPatternSuggestionProvenance {
        let currentSessionMatches = context.currentSessionObservations.filter { current in
            let currentComponents = Set(current.components.map(\.canonicalName).filter { !$0.isEmpty })
            let patternComponents = Set(pattern.componentProfile.map(\.canonicalName).filter { !$0.isEmpty })
            return !currentComponents.isEmpty && currentComponents.isSubset(of: patternComponents)
        }
        var reasonCodes: [String] = []
        if pattern.distinctDays >= 2 { reasonCodes.append("repeated-history") }
        if FoodPatternRanker.timeSupport(for: pattern, targetDate: context.targetDate) > 0.35 { reasonCodes.append("time-match") }
        if !currentSessionMatches.isEmpty { reasonCodes.append("session-cooccurrence") }
        if pattern.feedbackProfile.timesAccepted > 0 || pattern.feedbackProfile.timesRefined > 0 { reasonCodes.append("accepted-feedback") }
        if source == .recentAgain { reasonCodes.append("recent-repeat") }

        return FoodPatternSuggestionProvenance(
            patternID: pattern.id,
            sourceObservationIDs: pattern.observations.map(\.id),
            sourceEntryIDs: pattern.observations.map(\.entryID),
            sourceTitles: pattern.observations.map(\.displayName),
            sourceLoggedAt: pattern.observations.map(\.loggedAt),
            matchedCurrentSessionEntryIDs: currentSessionMatches.map(\.entryID),
            reasonCodes: reasonCodes
        )
    }

    private func suggestedEntry(for pattern: FoodPattern) -> SuggestedFoodEntry {
        SuggestedFoodEntry(
            id: pattern.id,
            name: pattern.canonicalTitle,
            calories: pattern.nutritionProfile.medianCalories,
            proteinGrams: pattern.nutritionProfile.medianProteinGrams,
            carbsGrams: pattern.nutritionProfile.medianCarbsGrams,
            fatGrams: pattern.nutritionProfile.medianFatGrams,
            fiberGrams: pattern.nutritionProfile.medianFiberGrams,
            sugarGrams: pattern.nutritionProfile.medianSugarGrams,
            servingSize: pattern.servingProfile?.commonServingText,
            emoji: pattern.emoji,
            components: pattern.componentProfile.map {
                SuggestedFoodComponent(
                    id: $0.id,
                    displayName: $0.displayName,
                    role: $0.role.rawValue,
                    calories: $0.medianCalories,
                    proteinGrams: $0.medianProteinGrams,
                    carbsGrams: $0.medianCarbsGrams,
                    fatGrams: $0.medianFatGrams,
                    confidence: "medium"
                )
            },
            mealKind: nil,
            notes: nil,
            confidence: pattern.distinctDays >= 3 ? "high" : "medium",
            schemaVersion: 2
        )
    }

    private func emptyDebugReport() -> FoodPatternRecommendationDebugReport {
        FoodPatternRecommendationDebugReport(
            observationCount: 0,
            patternCount: 0,
            eligiblePatternCount: 0,
            candidateCountBySource: [:],
            suppressedOneOffCount: 0,
            suppressedAlreadyTodayCount: 0,
            suppressedNegativeFeedbackCount: 0,
            suppressedLowConfidenceCount: 0,
            finalShownTitles: [],
            provenanceByTitle: [:]
        )
    }
}

struct FoodPatternRecommendationContext: Sendable, Equatable {
    let now: Date
    let targetDate: Date
    let sessionID: UUID?
    let limit: Int
    let observations: [FoodObservation]
    let currentSessionObservations: [FoodObservation]
    let todayObservations: [FoodObservation]

    init(now: Date, targetDate: Date, sessionID: UUID?, limit: Int, observations: [FoodObservation]) {
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        self.now = now
        self.targetDate = targetDate
        self.sessionID = sessionID
        self.limit = limit
        self.observations = observations
        self.currentSessionObservations = observations.filter {
            $0.sessionID == sessionID && sessionID != nil && $0.loggedAt < targetDate
        }
        self.todayObservations = observations.filter { $0.loggedAt >= startOfDay && $0.loggedAt < targetDate }
    }
}
