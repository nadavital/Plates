import SwiftData
import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationDeviceDebugTests: XCTestCase {
    func testLocalDeviceFoodRecommendationReplayWhenArmed() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["TRAI_DEBUG_FOOD_RECOMMENDATION_REPLAY"] == "1" else {
            throw XCTSkip("Set TRAI_DEBUG_FOOD_RECOMMENDATION_REPLAY=1 to run simulator replay diagnostics.")
        }
        #endif

        let entries = [
            entry("Chicken Rice Bowl", day: 0),
            entry("Chicken Rice Bowl", day: 1),
            entry("Chicken Rice Bowl", day: 2),
            entry("Greek Yogurt Bowl", day: 0, hour: 8, components: yogurtComponents()),
            entry("Greek Yogurt Bowl", day: 1, hour: 8, components: yogurtComponents()),
            entry("Salmon Rice Bowl", day: 0, hour: 19, components: salmonRiceComponents()),
            entry("Salmon Rice Bowl", day: 1, hour: 19, components: salmonRiceComponents())
        ]
        let metrics = try await FoodRecommendationEvaluator().evaluate(
            entries: entries,
            memories: [],
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 5)
        )
        let observations = FoodObservationBuilder().observations(from: entries)
        let patterns = FoodPatternBuilder().patterns(from: observations)
        let dinner = FoodRecommendationEngine().recommendationsSync(
            for: FoodRecommendationRequest(
                now: FoodRecommendationTestSupport.day(3, hour: 19),
                targetDate: FoodRecommendationTestSupport.day(3, hour: 19),
                sessionID: nil,
                limit: 3,
                entries: entries,
                memories: []
            )
        )

        print(
            """
            Food recommendation replay:
            observations=\(observations.count) patterns=\(patterns.count) cases=\(metrics.evaluatedCases)
            newHitAt3=\(metrics.hitAt3) newMRR=\(metrics.meanReciprocalRank)
            oneOffFalsePositiveRate=\(metrics.oneOffFalsePositiveRate) beverageDominationRate=\(metrics.beverageDominationRate) completeMealCoverageRate=\(metrics.completeMealCoverageRate)
            dinner_19 shown=\(dinner.suggestions.map(\.title).joined(separator: " | "))
            """
        )

        XCTAssertGreaterThan(metrics.evaluatedCases, 0)
    }

    private func entry(
        _ name: String,
        day: Int,
        hour: Int = 12,
        components: [AcceptedFoodComponent]? = nil
    ) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day, hour: hour),
            components: components ?? chickenRiceComponents()
        )
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }

    private func yogurtComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("greek yogurt", role: .protein, calories: 180, protein: 24, carbs: 10, fat: 2),
            FoodRecommendationTestSupport.component("berries", role: .fruit, calories: 60, protein: 1, carbs: 15, fat: 0)
        ]
    }

    private func salmonRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("salmon", role: .protein, calories: 320, protein: 32, carbs: 0, fat: 20),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }
}
