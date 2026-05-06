import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationCandidateTests: XCTestCase {
    func testRepeatStapleGeneratorRequiresMultipleDays() {
        let repeatedHabit = habits(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, components: chickenRiceComponents()),
            entry("Katz Pastrami Sandwich", day: 3, components: pastramiComponents())
        ])
        let context = context(habits: repeatedHabit)

        let candidates = RepeatStapleFoodCandidateGenerator().candidates(habits: repeatedHabit, context: context)

        XCTAssertTrue(candidates.contains { $0.habit.representativeTitle == "Chicken Rice Bowl" })
        XCTAssertFalse(candidates.contains { $0.habit.representativeTitle == "Katz Pastrami Sandwich" })
    }

    func testTimeContextGeneratorUsesContinuousHourWindow() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, hour: 12, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, hour: 12, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, hour: 13, components: chickenRiceComponents())
        ])

        let lunchCandidates = TimeContextFoodCandidateGenerator().candidates(habits: habits, context: context(habits: habits, targetHour: 12))
        let lateCandidates = TimeContextFoodCandidateGenerator().candidates(habits: habits, context: context(habits: habits, targetHour: 23))

        XCTAssertFalse(lunchCandidates.isEmpty)
        XCTAssertTrue(lateCandidates.isEmpty)
    }

    func testSessionCompletionGeneratorUsesCurrentSessionAnchors() {
        let sessionID = UUID()
        let entries = [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(
                name: "Chicken",
                loggedAt: FoodRecommendationTestSupport.day(3),
                components: [FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 220, protein: 38, carbs: 0, fat: 5)],
            sessionID: sessionID
        )
        ]
        let observations = FoodObservationBuilder().observations(from: entries)
        let habits = FoodHabitBuilder().habits(from: observations)
        let context = FoodRecommendationContext(
            now: FoodRecommendationTestSupport.day(3),
            targetDate: FoodRecommendationTestSupport.day(3, hour: 13),
            sessionID: sessionID,
            limit: 3,
            observations: observations,
            memories: []
        )

        let candidates = SessionCompletionFoodCandidateGenerator().candidates(habits: habits, context: context)

        XCTAssertTrue(candidates.contains { $0.habit.signature.canonicalComponents == ["chicken", "rice"] })
    }

    func testSemanticVariantGeneratorUsesEmbeddingAsSupportNotSoleSignal() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Salad", day: 2, calories: 250, protein: 38, carbs: 10, fat: 8, components: chickenSaladComponents())
        ])
        let context = context(habits: habits)

        let candidates = SemanticVariantFoodCandidateGenerator().candidates(habits: habits, context: context)

        XCTAssertTrue(candidates.contains { $0.habit.signature.canonicalComponents == ["chicken", "rice"] })
        XCTAssertFalse(candidates.contains { $0.habit.signature.canonicalComponents == ["chicken", "salad"] })
    }

    func testRecentRepeatedGeneratorRejectsSingleRecentObservation() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, components: chickenRiceComponents()),
            entry("Katz Pastrami Sandwich", day: 2, components: pastramiComponents())
        ])
        let context = context(habits: habits, targetDay: 3)

        let candidates = RecentRepeatedFoodCandidateGenerator().candidates(habits: habits, context: context)

        XCTAssertTrue(candidates.contains { $0.habit.representativeTitle == "Chicken Rice Bowl" })
        XCTAssertFalse(candidates.contains { $0.habit.representativeTitle == "Katz Pastrami Sandwich" })
    }

    func testRecentRepeatedGeneratorAllowsSingleRecentMorningBeverageRepeat() {
        let habits = habits(from: [
            entry("Latte", day: 2, hour: 10, calories: 150, protein: 8, carbs: 12, fat: 5, components: latteComponents())
        ])

        let morningCandidates = RecentRepeatedFoodCandidateGenerator().candidates(
            habits: habits,
            context: context(habits: habits, targetDay: 3, targetHour: 8)
        )
        let lunchCandidates = RecentRepeatedFoodCandidateGenerator().candidates(
            habits: habits,
            context: context(habits: habits, targetDay: 3, targetHour: 12)
        )

        XCTAssertTrue(morningCandidates.contains { $0.habit.representativeTitle == "Latte" })
        XCTAssertTrue(lunchCandidates.isEmpty)
    }

    func testRecentCompleteMealGeneratorAllowsObservedEditableMealFallback() {
        let habits = habits(from: [
            entry("Chicken Curry With Rice", day: 2, hour: 19, calories: 720, protein: 42, carbs: 82, fat: 24, components: chickenCurryRiceComponents()),
            entry("Latte", day: 2, hour: 8, calories: 150, protein: 8, carbs: 12, fat: 5, components: latteComponents())
        ])
        let context = context(habits: habits, targetDay: 3, targetHour: 19)

        let candidates = RecentCompleteMealFoodCandidateGenerator().candidates(habits: habits, context: context)

        XCTAssertTrue(candidates.contains { $0.habit.representativeTitle == "Chicken Curry With Rice" })
        XCTAssertFalse(candidates.contains { $0.habit.representativeTitle == "Latte" })
    }

    private func entry(
        _ name: String,
        day: Int,
        hour: Int = 12,
        calories: Int = 620,
        protein: Double = 42,
        carbs: Double = 58,
        fat: Double = 16,
        components: [AcceptedFoodComponent]
    ) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day, hour: hour),
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            components: components
        )
    }

    private func habits(from entries: [FoodEntry]) -> [FoodHabit] {
        FoodHabitBuilder().habits(from: FoodObservationBuilder().observations(from: entries))
    }

    private func context(habits: [FoodHabit], targetDay: Int = 3, targetHour: Int = 12) -> FoodRecommendationContext {
        FoodRecommendationContext(
            now: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            targetDate: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            sessionID: nil,
            limit: 3,
            observations: habits.flatMap(\.observations),
            memories: []
        )
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }

    private func chickenSaladComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("salad", role: .vegetable, calories: 80, protein: 3, carbs: 10, fat: 2)
        ]
    }

    private func pastramiComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("pastrami", role: .protein, calories: 420, protein: 30, carbs: 0, fat: 30),
            FoodRecommendationTestSupport.component("rye bread", role: .carb, calories: 220, protein: 6, carbs: 40, fat: 3)
        ]
    }

    private func latteComponents() -> [AcceptedFoodComponent] {
        [FoodRecommendationTestSupport.component("latte", role: .drink, calories: 150, protein: 8, carbs: 12, fat: 5)]
    }

    private func chickenCurryRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken curry", role: .protein, calories: 360, protein: 38, carbs: 10, fat: 18),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 260, protein: 5, carbs: 58, fat: 1),
            FoodRecommendationTestSupport.component("curry sauce", role: .sauce, calories: 100, protein: 1, carbs: 14, fat: 5)
        ]
    }
}
