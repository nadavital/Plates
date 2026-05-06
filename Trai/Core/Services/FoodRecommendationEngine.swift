import CryptoKit
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

struct FoodRecommendationCandidate: Sendable, Equatable {
    let habit: FoodHabit
    let source: FoodRecommendationCandidateSource
    let features: FoodRecommendationFeatures
    let suggestedEntry: SuggestedFoodEntry
}

enum FoodRecommendationCandidateSource: String, Sendable {
    case repeatStaple
    case timeContext
    case sessionCompletion
    case semanticVariant
    case recentRepeated
    case recentCompleteMeal
}

struct FoodRecommendationResult: Sendable, Equatable {
    let suggestions: [FoodSuggestion]
    let debugReport: FoodRecommendationDebugReport
}

struct FoodRecommendationDebugReport: Sendable, Equatable {
    let observationCount: Int
    let habitCount: Int
    let candidateCountBySource: [FoodRecommendationCandidateSource: Int]
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowUsefulnessCount: Int
    let finalShownTitles: [String]
}

struct FoodRecommendationEngine {
    private let observationBuilder = FoodObservationBuilder()
    private let habitBuilder = FoodHabitBuilder()
    private let ranker = FoodRecommendationRanker()

    func recommendations(for request: FoodRecommendationRequest) async throws -> FoodRecommendationResult {
        recommendationsSync(for: request)
    }

    func recommendationsSync(for request: FoodRecommendationRequest) -> FoodRecommendationResult {
        guard request.limit > 0 else {
            return FoodRecommendationResult(
                suggestions: [],
                debugReport: FoodRecommendationDebugReport(
                    observationCount: 0,
                    habitCount: 0,
                    candidateCountBySource: [:],
                    suppressedOneOffCount: 0,
                    suppressedAlreadyTodayCount: 0,
                    suppressedNegativeFeedbackCount: 0,
                    suppressedLowUsefulnessCount: 0,
                    finalShownTitles: []
                )
            )
        }

        let observations = observationBuilder
            .observations(from: request.entries)
            .filter { $0.loggedAt < request.targetDate }
        let habits = habitBuilder.habits(from: observations, memories: request.memories)
        let context = FoodRecommendationContext(
            now: request.now,
            targetDate: request.targetDate,
            sessionID: request.sessionID,
            limit: request.limit,
            observations: observations,
            memories: request.memories
        )
        let candidates = FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context)
        let ranked = ranker.rank(candidates, context: context)
        let suggestions = ranked.prefix(request.limit).map { candidate in
            FoodSuggestion(
                memoryID: suggestionID(for: candidate.habit),
                title: candidate.suggestedEntry.name,
                subtitle: subtitle(for: candidate),
                detail: "\(Int(candidate.suggestedEntry.proteinGrams.rounded()))g protein • \(candidate.suggestedEntry.calories) cal",
                emoji: candidate.suggestedEntry.emoji ?? "🍽️",
                relevanceScore: ranker.score(candidate.features),
                suggestedEntry: candidate.suggestedEntry
            )
        }
        let rankerDiagnostics = ranker.diagnostics(for: candidates, context: context)

        return FoodRecommendationResult(
            suggestions: suggestions,
            debugReport: FoodRecommendationDebugReport(
                observationCount: observations.count,
                habitCount: habits.count,
                candidateCountBySource: Dictionary(grouping: candidates, by: \.source).mapValues(\.count),
                suppressedOneOffCount: rankerDiagnostics.suppressedOneOffCount,
                suppressedAlreadyTodayCount: rankerDiagnostics.suppressedAlreadyTodayCount,
                suppressedNegativeFeedbackCount: rankerDiagnostics.suppressedNegativeFeedbackCount,
                suppressedLowUsefulnessCount: rankerDiagnostics.suppressedLowUsefulnessCount,
                finalShownTitles: suggestions.map(\.title)
            )
        )
    }

    private func suggestionID(for habit: FoodHabit) -> UUID {
        let linkedIDs = habit.observations.compactMap(\.linkedMemoryID)
        guard !linkedIDs.isEmpty else { return habit.stableUUID }
        return Dictionary(grouping: linkedIDs, by: { $0 })
            .max {
                if $0.value.count != $1.value.count {
                    return $0.value.count < $1.value.count
                }
                return $0.key.uuidString < $1.key.uuidString
            }?
            .key ?? habit.stableUUID
    }

    private func subtitle(for candidate: FoodRecommendationCandidate) -> String {
        switch candidate.source {
        case .repeatStaple:
            return "Usual staple"
        case .timeContext:
            return "Common around this time"
        case .sessionCompletion:
            return "Often logged together"
        case .semanticVariant:
            return "Similar to past logs"
        case .recentRepeated:
            return "Recent repeat"
        case .recentCompleteMeal:
            return "Recently logged"
        }
    }
}

extension FoodHabit {
    var stableUUID: UUID {
        let digest = SHA256.hash(data: Data(id.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
