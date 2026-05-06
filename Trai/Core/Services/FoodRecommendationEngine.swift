import Foundation

struct FoodRecommendationRequest: @unchecked Sendable {
    let now: Date
    let targetDate: Date
    let sessionID: UUID?
    let limit: Int
    let entries: [FoodEntry]
    let memories: [FoodMemory]
}

struct FoodRecommendationContext: @unchecked Sendable {
    let now: Date
    let targetDate: Date
    let sessionID: UUID?
    let limit: Int
    let observations: [FoodObservation]
    let currentSessionObservations: [FoodObservation]
    let todayObservations: [FoodObservation]
    let recentObservations: [FoodObservation]
    let memories: [FoodMemory]

    init(
        now: Date,
        targetDate: Date,
        sessionID: UUID?,
        limit: Int,
        observations: [FoodObservation],
        memories: [FoodMemory]
    ) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: targetDate)
        let recentStart = calendar.date(byAdding: .day, value: -30, to: startOfDay) ?? startOfDay

        self.now = now
        self.targetDate = targetDate
        self.sessionID = sessionID
        self.limit = limit
        self.observations = observations
        self.currentSessionObservations = observations.filter {
            $0.sessionID == sessionID && sessionID != nil && $0.loggedAt < targetDate
        }
        self.todayObservations = observations.filter { $0.loggedAt >= startOfDay && $0.loggedAt < targetDate }
        self.recentObservations = observations.filter { $0.loggedAt >= recentStart && $0.loggedAt < targetDate }
        self.memories = memories
    }
}

enum FoodRecommendationSource: String, Sendable {
    case likelyNow
    case continueSession
    case recentAgain
}

struct FoodRecommendationResult: Sendable, Equatable {
    let suggestions: [FoodSuggestion]
    let debugReport: FoodRecommendationDebugReport
}

struct FoodRecommendationDebugReport: Sendable, Equatable {
    let observationCount: Int
    let patternCount: Int
    let candidateCountBySource: [FoodRecommendationSource: Int]
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowConfidenceCount: Int
    let finalShownTitles: [String]
}

struct FoodRecommendationEngine {
    private let patternEngine = FoodPatternRecommendationEngine()

    func recommendations(for request: FoodRecommendationRequest) async throws -> FoodRecommendationResult {
        recommendationsSync(for: request)
    }

    func recommendationsSync(for request: FoodRecommendationRequest) -> FoodRecommendationResult {
        let patternResult = patternEngine.recommendationsSync(for: request)
        let suggestions = patternResult.suggestions.map { suggestion in
            FoodSuggestion(
                memoryID: suggestionID(for: suggestion.pattern),
                title: suggestion.suggestedEntry.name,
                subtitle: subtitle(for: suggestion),
                detail: "\(Int(suggestion.suggestedEntry.proteinGrams.rounded()))g protein • \(suggestion.suggestedEntry.calories) cal",
                emoji: suggestion.suggestedEntry.emoji ?? "🍽️",
                relevanceScore: suggestion.score,
                suggestedEntry: suggestion.suggestedEntry
            )
        }

        return FoodRecommendationResult(
            suggestions: suggestions,
            debugReport: FoodRecommendationDebugReport(
                observationCount: patternResult.debugReport.observationCount,
                patternCount: patternResult.debugReport.patternCount,
                candidateCountBySource: recommendationCandidateCounts(from: patternResult.debugReport.candidateCountBySource),
                suppressedOneOffCount: patternResult.debugReport.suppressedOneOffCount,
                suppressedAlreadyTodayCount: patternResult.debugReport.suppressedAlreadyTodayCount,
                suppressedNegativeFeedbackCount: patternResult.debugReport.suppressedNegativeFeedbackCount,
                suppressedLowConfidenceCount: patternResult.debugReport.suppressedLowConfidenceCount,
                finalShownTitles: suggestions.map(\.title)
            )
        )
    }

    private func suggestionID(for pattern: FoodPattern) -> UUID {
        let linkedIDs = pattern.observations.compactMap(\.linkedMemoryID)
        guard !linkedIDs.isEmpty else { return pattern.stableUUID }
        return Dictionary(grouping: linkedIDs, by: { $0 })
            .max {
                if $0.value.count != $1.value.count {
                    return $0.value.count < $1.value.count
                }
                return $0.key.uuidString < $1.key.uuidString
            }?
            .key ?? pattern.stableUUID
    }

    private func subtitle(for suggestion: FoodPatternSuggestion) -> String {
        switch suggestion.source {
        case .likelyNow:
            return "Common around this time"
        case .continueSession:
            return "Often logged together"
        case .recentAgain:
            return "Recent repeat"
        }
    }

    private func recommendationCandidateCounts(
        from counts: [FoodPatternSuggestionSource: Int]
    ) -> [FoodRecommendationSource: Int] {
        var output: [FoodRecommendationSource: Int] = [:]
        output[.likelyNow] = counts[.likelyNow]
        output[.continueSession] = counts[.continueSession]
        output[.recentAgain] = counts[.recentAgain]
        return output.filter { $0.value > 0 }
    }
}
