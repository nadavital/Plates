import XCTest
@testable import Trai

@MainActor
final class FoodPatternRecommendationTests: XCTestCase {
    func testOneOffAcceptedFoodIsNotProactive() {
        let entries = [
            chickenRice("Chicken Rice Bowl", day: 0),
            chickenRice("Grilled Chicken With Rice", day: 1),
            chickenRice("Chicken and rice", day: 2),
            pastrami(day: 2)
        ]

        let result = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: entries, targetDay: 3)
        )

        XCTAssertTrue(result.suggestions.contains {
            Set($0.suggestedEntry.components.map(\.displayName)) == Set(["Chicken", "Rice"])
        })
        XCTAssertFalse(result.suggestions.contains { $0.suggestedEntry.name == "Katz Pastrami Sandwich" })
    }

    func testRecentOneOffCanOnlyAppearAsSessionCompletionWithAnchor() {
        let sessionID = UUID()
        let entries = [
            chickenRice("Chicken Rice Bowl", day: 0),
            FoodRecommendationTestSupport.entry(
                name: "Chicken",
                loggedAt: FoodRecommendationTestSupport.day(2),
                components: [FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5)],
                sessionID: sessionID
            )
        ]

        let blankResult = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: entries, targetDay: 3)
        )
        let anchoredResult = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: entries, targetDay: 3, sessionID: sessionID)
        )

        XCTAssertTrue(blankResult.suggestions.isEmpty)
        XCTAssertTrue(anchoredResult.suggestions.contains { $0.suggestedEntry.name == "Chicken Rice Bowl" })
        XCTAssertEqual(anchoredResult.suggestions.first?.source, .continueSession)
    }

    func testEvidenceControlsLatteSuggestionsWithoutHardcodedMorningException() {
        let singleLatte = [
            latte(day: 2, hour: 8)
        ]
        let repeatedLatte = [
            latte(day: 0, hour: 8),
            latte(day: 1, hour: 8)
        ]

        let singleResult = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: singleLatte, targetDay: 3, targetHour: 8)
        )
        let repeatedResult = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: repeatedLatte, targetDay: 3, targetHour: 8)
        )

        XCTAssertFalse(singleResult.suggestions.contains { $0.suggestedEntry.name == "Latte" })
        XCTAssertTrue(repeatedResult.suggestions.contains { $0.suggestedEntry.name == "Latte" })
    }

    func testEverySuggestionIncludesProvenance() {
        let result = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: [
                chickenRice("Chicken Rice Bowl", day: 0),
                chickenRice("Grilled Chicken With Rice", day: 1)
            ], targetDay: 2)
        )

        let suggestion = result.suggestions.first
        XCTAssertFalse(suggestion?.provenance.sourceEntryIDs.isEmpty ?? true)
        XCTAssertFalse(suggestion?.provenance.sourceTitles.isEmpty ?? true)
        XCTAssertFalse(suggestion?.provenance.sourceLoggedAt.isEmpty ?? true)
        XCTAssertTrue(suggestion?.provenance.reasonCodes.contains("repeated-history") ?? false)
    }

    func testSubstantialPatternsRankAheadOfFrequentSimpleDrinks() {
        let entries = [
            drink("Latte", component: "latte", day: 0, hour: 12),
            drink("Latte", component: "latte", day: 1, hour: 12),
            drink("Cappuccino", component: "cappuccino", day: 0, hour: 12),
            drink("Cappuccino", component: "cappuccino", day: 1, hour: 12),
            drink("Iced Latte", component: "iced latte", day: 0, hour: 12),
            drink("Iced Latte", component: "iced latte", day: 1, hour: 12),
            chickenRice("Chicken Rice Bowl", day: 0),
            chickenRice("Chicken Rice Bowl", day: 1)
        ]

        let result = FoodPatternRecommendationEngine().recommendationsSync(
            for: request(entries: entries, targetDay: 2, targetHour: 12)
        )

        XCTAssertEqual(result.suggestions.first?.suggestedEntry.name, "Chicken Rice Bowl")
        XCTAssertLessThanOrEqual(result.suggestions.filter { $0.pattern.componentProfile.allSatisfy { $0.role == .drink } }.count, 1)
    }

    private func request(
        entries: [FoodEntry],
        targetDay: Int,
        targetHour: Int = 12,
        sessionID: UUID? = nil
    ) -> FoodRecommendationRequest {
        FoodRecommendationRequest(
            now: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            targetDate: FoodRecommendationTestSupport.day(targetDay, hour: targetHour),
            sessionID: sessionID,
            limit: 3,
            entries: entries,
            memories: []
        )
    }

    private func chickenRice(_ name: String, day: Int) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day),
            components: [
                FoodRecommendationTestSupport.component("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                FoodRecommendationTestSupport.component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
    }

    private func pastrami(day: Int) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: "Katz Pastrami Sandwich",
            loggedAt: FoodRecommendationTestSupport.day(day),
            calories: 850,
            protein: 35,
            carbs: 75,
            fat: 38,
            components: [
                FoodRecommendationTestSupport.component("pastrami", role: .protein, calories: 420, protein: 30, carbs: 0, fat: 30),
                FoodRecommendationTestSupport.component("rye bread", role: .carb, calories: 220, protein: 6, carbs: 40, fat: 3)
            ]
        )
    }

    private func latte(day: Int, hour: Int) -> FoodEntry {
        drink("Latte", component: "latte", day: day, hour: hour)
    }

    private func drink(_ name: String, component: String, day: Int, hour: Int) -> FoodEntry {
        FoodRecommendationTestSupport.entry(
            name: name,
            loggedAt: FoodRecommendationTestSupport.day(day, hour: hour),
            calories: 150,
            protein: 8,
            carbs: 12,
            fat: 5,
            components: [
                FoodRecommendationTestSupport.component(component, role: .drink, calories: 150, protein: 8, carbs: 12, fat: 5)
            ]
        )
    }
}
