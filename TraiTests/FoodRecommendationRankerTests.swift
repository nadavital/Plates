import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationRankerTests: XCTestCase {
    func testRankerPrefersRepeatedCompleteMealOverRecentOneOff() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, components: chickenRiceComponents()),
            entry("Katz Pastrami Sandwich", day: 3, components: pastramiComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 4)
        let candidates = FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context)

        let ranked = FoodRecommendationRanker().rank(candidates, context: context)

        XCTAssertEqual(ranked.first?.habit.representativeTitle, "Chicken Rice Bowl")
        XCTAssertFalse(ranked.contains { $0.habit.representativeTitle == "Katz Pastrami Sandwich" })
    }

    func testRankerCapsBeverageDominance() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, components: chickenRiceComponents()),
            entry("Latte", day: 0, calories: 150, protein: 8, carbs: 12, fat: 5, components: latteComponents()),
            entry("Latte", day: 1, calories: 150, protein: 8, carbs: 12, fat: 5, components: latteComponents()),
            entry("Cappuccino", day: 0, calories: 110, protein: 6, carbs: 9, fat: 4, components: cappuccinoComponents()),
            entry("Cappuccino", day: 1, calories: 110, protein: 6, carbs: 9, fat: 4, components: cappuccinoComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 3)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        let beverageCount = ranked.prefix(3).filter { $0.habit.componentProfile.contains { $0.role == .drink } }.count
        XCTAssertLessThanOrEqual(beverageCount, 1)
    }

    func testRankerSuppressesAlreadyLoggedToday() {
        let observations = FoodObservationBuilder().observations(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 3, hour: 8, components: chickenRiceComponents())
        ])
        let habits = FoodHabitBuilder().habits(from: observations)
        let context = context(observations: observations, targetDay: 3)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        XCTAssertFalse(ranked.contains { $0.habit.representativeTitle == "Chicken Rice Bowl" })
    }

    func testRankerAllowsLegitimateSameDayRepeats() {
        let observations = FoodObservationBuilder().observations(from: [
            entry("Protein Shake", day: 0, hour: 8, calories: 260, protein: 32, carbs: 12, fat: 5, components: shakeComponents()),
            entry("Protein Shake", day: 0, hour: 15, calories: 260, protein: 32, carbs: 12, fat: 5, components: shakeComponents()),
            entry("Protein Shake", day: 1, hour: 8, calories: 260, protein: 32, carbs: 12, fat: 5, components: shakeComponents()),
            entry("Protein Shake", day: 1, hour: 15, calories: 260, protein: 32, carbs: 12, fat: 5, components: shakeComponents()),
            entry("Protein Shake", day: 3, hour: 8, calories: 260, protein: 32, carbs: 12, fat: 5, components: shakeComponents())
        ])
        let habits = FoodHabitBuilder().habits(from: observations)
        let context = context(observations: observations, targetDay: 3, targetHour: 15)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        XCTAssertTrue(ranked.contains { $0.habit.representativeTitle == "Protein Shake" })
    }

    func testRankerSuppressesRepeatedlyIgnoredSuggestion() {
        let memoryID = UUID()
        let ignored = entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents())
        ignored.foodMemoryIdString = memoryID.uuidString
        let repeated = entry("Chicken Rice Bowl", day: 1, components: chickenRiceComponents())
        repeated.foodMemoryIdString = memoryID.uuidString
        let memory = FoodMemory()
        memory.id = memoryID
        memory.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 5,
            timesTapped: 0,
            timesAccepted: 0,
            timesDismissed: 3,
            timesRefined: 0,
            lastShownAt: FoodRecommendationTestSupport.day(2),
            lastTappedAt: nil,
            lastAcceptedAt: nil,
            lastDismissedAt: FoodRecommendationTestSupport.day(2),
            lastRefinedAt: nil
        )
        let observations = FoodObservationBuilder().observations(from: [ignored, repeated])
        let habits = FoodHabitBuilder().habits(from: observations, memories: [memory])
        let context = context(observations: observations, memories: [memory], targetDay: 2, targetHour: 2)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankerSuppressesLowUtilitySnackAwayFromSupportedTime() {
        let habits = habits(from: [
            entry("Protein Bar", day: 0, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Protein Bar", day: 1, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Protein Bar", day: 2, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Protein Bar", day: 3, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Chicken Rice Bowl", day: 0, hour: 12, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, hour: 12, components: chickenRiceComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 4, targetHour: 12)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        XCTAssertEqual(ranked.first?.habit.representativeTitle, "Chicken Rice Bowl")
        XCTAssertFalse(ranked.contains { $0.habit.representativeTitle == "Protein Bar" })
    }

    func testRankerAllowsSingleRecentMorningBeverageRepeat() {
        let habits = habits(from: [
            entry("Latte", day: 2, hour: 8, calories: 150, protein: 8, carbs: 12, fat: 5, components: latteComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 3, targetHour: 8)

        let ranked = FoodRecommendationRanker().rank(
            FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context),
            context: context
        )

        XCTAssertTrue(ranked.contains { $0.habit.representativeTitle == "Latte" })
    }

    func testRankerUsesRecentCompleteMealInsteadOfBlankOrSnackOnlyFallback() {
        let habits = habits(from: [
            entry("Chicken Curry With Rice", day: 3, hour: 19, calories: 720, protein: 42, carbs: 82, fat: 24, components: chickenCurryRiceComponents()),
            entry("Protein Bar", day: 0, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Protein Bar", day: 1, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents()),
            entry("Protein Bar", day: 2, hour: 15, calories: 220, protein: 20, carbs: 22, fat: 7, components: proteinBarComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 4, targetHour: 19)

        let ranked = FoodRecommendationRanker().rank(
            FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context),
            context: context
        )

        XCTAssertEqual(ranked.first?.habit.representativeTitle, "Chicken Curry With Rice")
    }

    func testRankerDeduplicatesEquivalentHabits() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, components: chickenRiceComponents()),
            entry("Grilled Chicken With Rice", day: 1, components: chickenRiceComponents()),
            entry("Chicken Rice", day: 2, components: chickenRiceComponents())
        ])
        let context = context(observations: habits.flatMap(\.observations), targetDay: 3)

        let ranked = FoodRecommendationRanker().rank(FoodRecommendationCandidateGeneratorSet().candidates(habits: habits, context: context), context: context)

        XCTAssertEqual(ranked.filter { $0.habit.signature.canonicalComponents == ["chicken", "rice"] }.count, 1)
    }

    func testSuggestedEntryUsesMedianAcceptedMacrosAndCommonComponents() {
        let habits = habits(from: [
            entry("Chicken Rice Bowl", day: 0, calories: 500, protein: 40, carbs: 50, fat: 10, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 1, calories: 620, protein: 42, carbs: 58, fat: 16, components: chickenRiceComponents()),
            entry("Chicken Rice Bowl", day: 2, calories: 700, protein: 44, carbs: 70, fat: 20, components: chickenRiceComponents())
        ])

        let suggestedEntry = FoodRecommendationFeatureBuilder.suggestedEntry(for: habits[0])

        XCTAssertEqual(suggestedEntry.calories, 620)
        XCTAssertEqual(suggestedEntry.proteinGrams, 42)
        XCTAssertEqual(Set(suggestedEntry.components.map(\.displayName)), Set(["Chicken", "Rice"]))
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

    private func context(
        observations: [FoodObservation],
        memories: [FoodMemory] = [],
        targetDay: Int,
        targetHour: Int = 12
    ) -> FoodRecommendationContext {
        FoodRecommendationContext(
            now: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            targetDate: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            sessionID: nil,
            limit: 3,
            observations: observations,
            memories: memories
        )
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
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

    private func cappuccinoComponents() -> [AcceptedFoodComponent] {
        [FoodRecommendationTestSupport.component("cappuccino", role: .drink, calories: 110, protein: 6, carbs: 9, fat: 4)]
    }

    private func shakeComponents() -> [AcceptedFoodComponent] {
        [FoodRecommendationTestSupport.component("protein shake", role: .drink, calories: 260, protein: 32, carbs: 12, fat: 5)]
    }

    private func proteinBarComponents() -> [AcceptedFoodComponent] {
        [FoodRecommendationTestSupport.component("protein bar", role: .mixed, calories: 220, protein: 20, carbs: 22, fat: 7)]
    }

    private func chickenCurryRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken curry", role: .protein, calories: 360, protein: 38, carbs: 10, fat: 18),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 260, protein: 5, carbs: 58, fat: 1),
            FoodRecommendationTestSupport.component("curry sauce", role: .sauce, calories: 100, protein: 1, carbs: 14, fat: 5)
        ]
    }
}
