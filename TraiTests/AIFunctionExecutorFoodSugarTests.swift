import XCTest
import SwiftData
@testable import Trai

@MainActor
final class AIFunctionExecutorFoodSugarTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testSuggestFoodLogCarriesSugarGramsIntoSuggestedEntry() async {
        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "suggest_food_log",
                arguments: [
                    "name": "Sugar",
                    "calories": 32,
                    "protein_grams": 0,
                    "carbs_grams": 8,
                    "fat_grams": 0,
                    "sugar_grams": 8,
                    "serving_size": "2 teaspoons",
                    "emoji": "🍬"
                ]
            )
        )

        guard case .suggestedFood(let entry) = result else {
            return XCTFail("Expected suggested food result")
        }

        XCTAssertEqual(entry.name, "Sugar")
        XCTAssertEqual(entry.carbsGrams, 8)
        XCTAssertEqual(entry.sugarGrams, 8)
        XCTAssertEqual(entry.servingSize, "2 teaspoons")
    }

    func testEditFoodEntryIncludesSugarChangeSuggestion() async throws {
        let existingEntry = FoodEntry(
            name: "Sugar",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 16,
            proteinGrams: 0,
            carbsGrams: 4,
            fatGrams: 0
        )
        existingEntry.sugarGrams = 4
        context.insert(existingEntry)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "edit_food_entry",
                arguments: [
                    "entry_id": existingEntry.id.uuidString,
                    "sugar_grams": 8
                ]
            )
        )

        guard case .suggestedFoodEdit(let edit) = result else {
            return XCTFail("Expected suggested food edit result")
        }

        let sugarChange = try XCTUnwrap(edit.changes.first(where: { $0.fieldKey == "sugarGrams" }))
        XCTAssertEqual(sugarChange.field, "Sugar")
        XCTAssertEqual(sugarChange.oldValue, "4g")
        XCTAssertEqual(sugarChange.newValue, "8g")
        XCTAssertEqual(sugarChange.newNumericValue, 8)
    }
}
