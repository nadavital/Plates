import XCTest
@testable import Trai

@MainActor
final class FoodPatternIdentityTests: XCTestCase {
    func testClustersAcceptedNameVariantsWithCompatibleStructure() {
        let observations = FoodObservationBuilder().observations(from: [
            entry("Chicken curry with rice", day: 0),
            entry("Curry rice bowl", day: 1),
            entry("Homemade chicken curry + jasmine rice", day: 2)
        ])

        let patterns = FoodPatternBuilder().patterns(from: observations)

        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.distinctDays, 3)
        XCTAssertEqual(Set(patterns.first?.aliases.map(\.displayName) ?? []), Set([
            "Chicken curry with rice",
            "Curry rice bowl",
            "Homemade chicken curry + jasmine rice"
        ]))
        XCTAssertEqual(patterns.first?.identityEvidence.representativeEntryIDs.count, 3)
    }

    func testDoesNotMergeSameComponentsWhenMacrosAreIncompatible() {
        let observations = FoodObservationBuilder().observations(from: [
            entry("Chicken and rice", day: 0, calories: 450, protein: 36, carbs: 48, fat: 8),
            entry("Large chicken and rice platter", day: 1, calories: 1200, protein: 78, carbs: 150, fat: 38)
        ])

        let patterns = FoodPatternBuilder().patterns(from: observations)

        XCTAssertEqual(patterns.count, 2)
    }

    func testEmbeddingCannotOverrideMacroIncompatibility() {
        let observations = FoodObservationBuilder().observations(from: [
            entry("Chicken and rice", day: 0, calories: 450, protein: 36, carbs: 48, fat: 8),
            entry("Chicken rice bowl", day: 1, calories: 1200, protein: 78, carbs: 150, fat: 38)
        ])
        let score = FoodPatternIdentityScorer().identityScore(
            observations[0],
            observations[1],
            embeddingSimilarity: 0.99
        )

        XCTAssertFalse(score.shouldMerge)
    }

    private func entry(
        _ name: String,
        day: Int,
        calories: Int = 680,
        protein: Double = 42,
        carbs: Double = 82,
        fat: Double = 18
    ) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day),
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            components: [
                FoodRecommendationTestSupport.component("chicken curry", role: .protein, calories: 360, protein: 38, carbs: 10, fat: 14),
                FoodRecommendationTestSupport.component("rice", role: .carb, calories: 260, protein: 5, carbs: 58, fat: 1),
                FoodRecommendationTestSupport.component("curry sauce", role: .sauce, calories: 60, protein: 1, carbs: 14, fat: 3)
            ]
        )
    }
}
