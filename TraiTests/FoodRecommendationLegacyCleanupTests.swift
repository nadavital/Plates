import SwiftData
import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationLegacyCleanupTests: XCTestCase {
    func testMealBucketDoesNotControlRecommendationEligibility() {
        let breakfast = FoodRecommendationTestSupport.entry(
            name: "Chicken Rice Bowl",
            loggedAt: FoodRecommendationTestSupport.day(0, hour: 12),
            components: chickenRiceComponents()
        )
        breakfast.mealType = FoodEntry.MealType.breakfast.rawValue
        let dinner = FoodRecommendationTestSupport.entry(
            name: "Chicken Rice Bowl",
            loggedAt: FoodRecommendationTestSupport.day(1, hour: 12),
            components: chickenRiceComponents()
        )
        dinner.mealType = FoodEntry.MealType.dinner.rawValue
        let result = FoodRecommendationEngine().recommendationsSync(
            for: FoodRecommendationRequest(
                now: FoodRecommendationTestSupport.day(2, hour: 12),
                targetDate: FoodRecommendationTestSupport.day(2, hour: 12),
                sessionID: nil,
                limit: 3,
                entries: [breakfast, dinner],
                memories: []
            )
        )

        XCTAssertEqual(result.suggestions.first?.title, "Chicken Rice Bowl")
    }

    func testFoodKindMismatchDoesNotBlockHabitSuggestion() {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents())
        ]
        let memory = FoodMemory()
        memory.kind = .food
        memory.status = .candidate
        memory.displayName = "Chicken Rice Bowl"

        let result = FoodRecommendationEngine().recommendationsSync(
            for: FoodRecommendationRequest(
                now: FoodRecommendationTestSupport.day(2),
                targetDate: FoodRecommendationTestSupport.day(2),
                sessionID: nil,
                limit: 3,
                entries: entries,
                memories: [memory]
            )
        )

        XCTAssertEqual(result.suggestions.first?.title, "Chicken Rice Bowl")
    }

    func testLegacyAcceptedSnapshotStillDecodes() throws {
        let entry = FoodRecommendationTestSupport.entry(
            name: "Chicken Rice Bowl",
            loggedAt: FoodRecommendationTestSupport.day(0),
            components: chickenRiceComponents()
        )
        let data = try XCTUnwrap(entry.acceptedSnapshotData)
        let decoded = try JSONDecoder().decode(AcceptedFoodSnapshot.self, from: data)

        XCTAssertEqual(decoded.mealTimeBucket, .lunch)
        XCTAssertEqual(decoded.displayName, "Chicken Rice Bowl")
    }

    func testMemoryResolutionStillRunsAfterSuggestionEngineSwitch() throws {
        let schema = Schema([FoodEntry.self, FoodMemory.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()))
        try context.save()

        try FoodMemoryService().resolvePendingEntries(limit: 5, modelContext: context)
        let refreshed = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)

        XCTAssertNotNil(refreshed.acceptedSnapshot)
        XCTAssertEqual(refreshed.foodMemoryResolutionState, .createdCandidate)
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }
}
