import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationHabitTests: XCTestCase {
    func testObservationBuilderUsesAcceptedSnapshotAsSourceOfTruth() throws {
        let entry = FoodRecommendationTestSupport.entry(
            name: "Accepted Chicken Rice",
            loggedAt: FoodRecommendationTestSupport.day(0),
            components: chickenRiceComponents()
        )
        entry.name = "Parent Name Should Not Win"
        entry.calories = 10

        let observation = try XCTUnwrap(FoodObservationBuilder().observation(from: entry))

        XCTAssertEqual(observation.displayName, "Accepted Chicken Rice")
        XCTAssertEqual(observation.components.map(\.canonicalName), ["chicken", "rice"])
        XCTAssertEqual(observation.calories, 620)
        XCTAssertEqual(observation.source, .camera)
        XCTAssertEqual(observation.userEditedFields, ["name"])
        XCTAssertEqual(observation.loggedAt, entry.acceptedSnapshot?.loggedAt)
    }

    func testObservationBuilderSkipsEntriesWithoutAcceptedSnapshot() {
        let entry = FoodEntry(name: "Legacy", mealType: "lunch", calories: 100, proteinGrams: 1, carbsGrams: 1, fatGrams: 1)

        XCTAssertNil(FoodObservationBuilder().observation(from: entry))
    }

    func testHabitBuilderClustersChickenRiceVariants() {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Roasted Chicken Breast With Rice", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Grilled Chicken With Brown Rice", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenRiceComponents())
        ]

        let habits = FoodHabitBuilder().habits(from: FoodObservationBuilder().observations(from: entries))

        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.signature.canonicalComponents, ["chicken", "rice"])
        XCTAssertEqual(habits.first?.observationCount, 3)
        XCTAssertEqual(habits.first?.distinctDays, 3)
        XCTAssertTrue(["Chicken Rice Bowl", "Roasted Chicken Breast With Rice", "Grilled Chicken With Brown Rice"].contains(habits.first?.representativeTitle ?? ""))
    }

    func testHabitBuilderDoesNotMergeChickenRiceAndChickenSalad() {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Salad", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenSaladComponents()),
            FoodRecommendationTestSupport.entry(name: "Grilled Chicken Salad", loggedAt: FoodRecommendationTestSupport.day(3), components: chickenSaladComponents())
        ]

        let habits = FoodHabitBuilder().habits(from: FoodObservationBuilder().observations(from: entries))

        XCTAssertEqual(habits.count, 2)
        XCTAssertEqual(Set(habits.map(\.signature.canonicalComponents)), Set([["chicken", "rice"], ["chicken", "salad"]]))
    }

    func testHabitBuilderSplitsWildlyDifferentMacroProfiles() {
        let components = chickenRiceComponents()
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), calories: 500, protein: 40, carbs: 55, fat: 12, components: components),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(1), calories: 520, protein: 42, carbs: 57, fat: 13, components: components),
            FoodRecommendationTestSupport.entry(name: "Large Chicken Rice Platter", loggedAt: FoodRecommendationTestSupport.day(2), calories: 1200, protein: 86, carbs: 140, fat: 35, components: components),
            FoodRecommendationTestSupport.entry(name: "Large Chicken Rice Platter", loggedAt: FoodRecommendationTestSupport.day(3), calories: 1230, protein: 88, carbs: 145, fat: 36, components: components)
        ]

        let habits = FoodHabitBuilder().habits(from: FoodObservationBuilder().observations(from: entries))

        XCTAssertEqual(habits.count, 2)
    }

    func testHabitFeedbackDoesNotDoubleCountRefinedOutcomes() throws {
        let memory = memory(
            timesShown: 3,
            timesAccepted: 1,
            timesDismissed: 0,
            timesRefined: 1
        )
        let entry = FoodRecommendationTestSupport.entry(
            name: "Chicken Rice Bowl",
            loggedAt: FoodRecommendationTestSupport.day(0),
            components: chickenRiceComponents()
        )
        entry.foodMemoryIdString = memory.id.uuidString

        let habit = try XCTUnwrap(FoodHabitBuilder().habits(
            from: FoodObservationBuilder().observations(from: [entry]),
            memories: [memory]
        ).first)

        XCTAssertEqual(habit.feedbackProfile.timesAccepted, 1)
    }

    func testHabitFeedbackCountsEachLinkedMemoryOnce() throws {
        let memory = memory(
            timesShown: 4,
            timesAccepted: 1,
            timesDismissed: 1,
            timesRefined: 0
        )
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenRiceComponents())
        ]
        entries.forEach { $0.foodMemoryIdString = memory.id.uuidString }

        let habit = try XCTUnwrap(FoodHabitBuilder().habits(
            from: FoodObservationBuilder().observations(from: entries),
            memories: [memory]
        ).first)

        XCTAssertEqual(habit.feedbackProfile.timesShown, 4)
        XCTAssertEqual(habit.feedbackProfile.timesAccepted, 1)
        XCTAssertEqual(habit.feedbackProfile.timesDismissed, 1)
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("grilled chicken breast", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }

    private func chickenSaladComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("salad", role: .vegetable, calories: 80, protein: 3, carbs: 10, fat: 2)
        ]
    }

    private func memory(
        timesShown: Int,
        timesAccepted: Int,
        timesDismissed: Int,
        timesRefined: Int
    ) -> FoodMemory {
        let memory = FoodMemory()
        memory.suggestionStats = FoodMemorySuggestionStats(
            timesShown: timesShown,
            timesTapped: 0,
            timesAccepted: timesAccepted,
            timesDismissed: timesDismissed,
            timesRefined: timesRefined,
            lastShownAt: nil,
            lastTappedAt: nil,
            lastAcceptedAt: nil,
            lastDismissedAt: nil,
            lastRefinedAt: nil
        )
        return memory
    }
}
