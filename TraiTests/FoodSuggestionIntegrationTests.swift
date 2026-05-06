import SwiftData
import XCTest
@testable import Trai

@MainActor
final class FoodSuggestionIntegrationTests: XCTestCase {
    func testCameraSuggestionsUseHabitEngineForFragmentedStaples() throws {
        let context = try modelContext()
        for entry in [
            entry("Chicken Rice Bowl", day: 0),
            entry("Roasted Chicken Breast With Rice", day: 1),
            entry("Grilled Chicken With Brown Rice", day: 2),
            FoodRecommendationTestSupport.entry(
                name: "Katz Pastrami Sandwich",
                loggedAt: FoodRecommendationTestSupport.day(3),
                calories: 850,
                protein: 35,
                carbs: 75,
                fat: 38,
                components: pastramiComponents()
            )
        ] {
            context.insert(entry)
        }
        try context.save()

        let suggestions = try FoodSuggestionService().cameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(4),
            targetDate: FoodRecommendationTestSupport.day(4),
            modelContext: context
        )

        XCTAssertEqual(suggestions.first?.suggestedEntry.components.map(\.displayName).sorted(), ["Chicken", "Rice"])
    }

    func testCameraSuggestionsDoNotRequireFoodMemoryObservationCounts() throws {
        let context = try modelContext()
        let first = entry("Chicken Rice Bowl", day: 0)
        let second = entry("Grilled Chicken With Rice", day: 1)
        first.foodMemoryIdString = UUID().uuidString
        second.foodMemoryIdString = UUID().uuidString
        context.insert(first)
        context.insert(second)
        try context.save()

        let suggestions = try FoodSuggestionService().cameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(2),
            targetDate: FoodRecommendationTestSupport.day(2),
            modelContext: context
        )

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertEqual(suggestions.first?.suggestedEntry.components.map(\.displayName).sorted(), ["Chicken", "Rice"])
    }

    func testCameraSuggestionsPreserveExistingOutcomeRecording() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        try context.save()
        let suggestion = try XCTUnwrap(
            FoodSuggestionService().cameraSuggestions(
                limit: 1,
                now: FoodRecommendationTestSupport.day(2),
                targetDate: FoodRecommendationTestSupport.day(2),
                modelContext: context
            ).first
        )

        XCTAssertNoThrow(
            try FoodSuggestionService().recordOutcome(.accepted, for: suggestion.memoryID, modelContext: context)
        )
        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let memory = try XCTUnwrap(memories.first { $0.id == suggestion.memoryID })
        XCTAssertGreaterThan(memory.suggestionStats?.timesShown ?? 0, 0)
        XCTAssertEqual(memory.suggestionStats?.timesAccepted, 1)
    }

    func testObservationBuiltSuggestionRecordsShownOnPersistedMemory() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        try context.save()

        let suggestion = try XCTUnwrap(
            FoodSuggestionService().cameraSuggestions(
                limit: 1,
                now: FoodRecommendationTestSupport.day(2),
                targetDate: FoodRecommendationTestSupport.day(2),
                modelContext: context
            ).first
        )
        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let memory = try XCTUnwrap(memories.first { $0.id == suggestion.memoryID })

        XCTAssertGreaterThan(memory.suggestionStats?.timesShown ?? 0, 0)
        XCTAssertTrue(memory.representativeEntryIds.isEmpty == false)
    }

    func testObservationBuiltSuggestionReconcileRecordsAcceptance() throws {
        let context = try modelContext()
        let accepted = entry("Chicken Rice Bowl", day: 2)
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        try context.save()
        let suggestion = try XCTUnwrap(
            FoodSuggestionService().cameraSuggestions(
                limit: 1,
                now: FoodRecommendationTestSupport.day(2),
                targetDate: FoodRecommendationTestSupport.day(2),
                modelContext: context
            ).first
        )

        try FoodSuggestionService().reconcileShownSuggestions(
            [suggestion.memoryID],
            preferredMemoryID: suggestion.memoryID,
            with: try XCTUnwrap(accepted.acceptedSnapshot),
            isRefined: false,
            modelContext: context
        )
        let memory = try XCTUnwrap(try context.fetch(FetchDescriptor<FoodMemory>()).first { $0.id == suggestion.memoryID })

        XCTAssertEqual(memory.suggestionStats?.timesAccepted, 1)
    }

    func testObservationBuiltSuggestionFeedbackSuppressesLaterRanking() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        try context.save()
        let suggestion = try XCTUnwrap(
            FoodSuggestionService().cameraSuggestions(
                limit: 1,
                now: FoodRecommendationTestSupport.day(2, hour: 9),
                targetDate: FoodRecommendationTestSupport.day(2, hour: 9),
                modelContext: context
            ).first
        )

        try FoodSuggestionService().recordOutcome(.dismissed, for: suggestion.memoryID, at: FoodRecommendationTestSupport.day(2, hour: 9), modelContext: context)
        let laterSuggestions = try FoodSuggestionService().cameraSuggestions(
            limit: 1,
            now: FoodRecommendationTestSupport.day(2, hour: 10),
            targetDate: FoodRecommendationTestSupport.day(2, hour: 10),
            modelContext: context
        )

        XCTAssertFalse(laterSuggestions.contains { $0.memoryID == suggestion.memoryID })
    }

    func testFutureSameDayDinnerDoesNotSuppressNoonRecommendation() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        context.insert(
            FoodRecommendationTestSupport.entry(
                name: "Katz Pastrami Sandwich",
                loggedAt: FoodRecommendationTestSupport.day(2, hour: 19),
                calories: 850,
                protein: 35,
                carbs: 75,
                fat: 38,
                components: pastramiComponents()
            )
        )
        try context.save()

        let suggestions = try FoodSuggestionService().cameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(2, hour: 12),
            targetDate: FoodRecommendationTestSupport.day(2, hour: 12),
            modelContext: context
        )

        XCTAssertEqual(suggestions.first?.title, "Chicken Rice Bowl")
        XCTAssertFalse(suggestions.contains { $0.title == "Katz Pastrami Sandwich" })
    }

    func testFutureOneOffDoesNotBecomeCandidateOrDebugObservationForTargetInstant() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        context.insert(
            FoodRecommendationTestSupport.entry(
                name: "Katz Pastrami Sandwich",
                loggedAt: FoodRecommendationTestSupport.day(2, hour: 13),
                calories: 850,
                protein: 35,
                carbs: 75,
                fat: 38,
                components: pastramiComponents()
            )
        )
        try context.save()

        let summary = try FoodSuggestionService().debugCameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(2, hour: 12),
            targetDate: FoodRecommendationTestSupport.day(2, hour: 12),
            modelContext: context
        )

        XCTAssertEqual(summary.totalObservations, 2)
        XCTAssertFalse(summary.shownSuggestionTitles.contains("Katz Pastrami Sandwich"))
    }

    func testEarlierTodayLogStillSuppressesAlreadyLoggedSuggestion() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        context.insert(
            FoodRecommendationTestSupport.entry(
                name: "Chicken Rice Bowl",
                loggedAt: FoodRecommendationTestSupport.day(2, hour: 8),
                components: chickenRiceComponents()
            )
        )
        try context.save()

        let summary = try FoodSuggestionService().debugCameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(2, hour: 12),
            targetDate: FoodRecommendationTestSupport.day(2, hour: 12),
            modelContext: context
        )

        XCTAssertGreaterThan(summary.filteredAlreadySatisfiedToday + summary.suppressedAlreadyTodayCount, 0)
        XCTAssertFalse(summary.shownSuggestionTitles.contains("Chicken Rice Bowl"))
    }

    func testDebugCameraSuggestionsReportsNewEngineStages() throws {
        let context = try modelContext()
        context.insert(entry("Chicken Rice Bowl", day: 0))
        context.insert(entry("Chicken Rice Bowl", day: 1))
        try context.save()

        let summary = try FoodSuggestionService().debugCameraSuggestions(
            limit: 3,
            now: FoodRecommendationTestSupport.day(2),
            targetDate: FoodRecommendationTestSupport.day(2),
            modelContext: context
        )

        XCTAssertEqual(summary.totalObservations, 2)
        XCTAssertEqual(summary.habitCount, 1)
        XCTAssertFalse(summary.candidateCountBySource.isEmpty)
        XCTAssertEqual(summary.suppressedOneOffCount, 0)
        XCTAssertEqual(summary.shownSuggestionTitles.first, "Chicken Rice Bowl")
    }

    private func modelContext() throws -> ModelContext {
        let schema = Schema([FoodEntry.self, FoodMemory.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func entry(_ name: String, day: Int) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day),
            components: chickenRiceComponents()
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
}
