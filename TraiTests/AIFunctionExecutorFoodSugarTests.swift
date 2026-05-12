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

    func testEditFoodEntryUsesDinnerAsSemanticHintWhenStoredMealTypeIsStale() async throws {
        let morningEntry = FoodEntry(
            name: "Coffee",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 5,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0
        )
        morningEntry.loggedAt = try loggedAtToday(hour: 10, minute: 0)
        context.insert(morningEntry)

        let dinnerEntry = FoodEntry(
            name: "Chicken Bowl",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 520,
            proteinGrams: 40,
            carbsGrams: 45,
            fatGrams: 18
        )
        dinnerEntry.loggedAt = try loggedAtToday(hour: 18, minute: 0)
        context.insert(dinnerEntry)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "edit_food_entry",
                arguments: [
                    "target_name": "Chicken Bowl",
                    "target_meal_type": "dinner",
                    "calories": 610
                ]
            )
        )

        guard case .suggestedFoodEdit(let edit) = result else {
            return XCTFail("Expected suggested food edit result")
        }

        XCTAssertEqual(edit.entryId, dinnerEntry.id)
        XCTAssertEqual(edit.changes.first(where: { $0.fieldKey == "calories" })?.newNumericValue, 610)
    }

    func testEditFoodComponentsResolvesDinnerByLoggedTimeWhenStoredMealTypeIsStale() async throws {
        let morningEntry = FoodEntry(
            name: "Eggs",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 210,
            proteinGrams: 14,
            carbsGrams: 2,
            fatGrams: 16
        )
        morningEntry.loggedAt = try loggedAtToday(hour: 10, minute: 0)
        context.insert(morningEntry)

        let dinnerEntry = FoodEntry(
            name: "Rice Bowl",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 520,
            proteinGrams: 28,
            carbsGrams: 70,
            fatGrams: 14
        )
        dinnerEntry.loggedAt = try loggedAtToday(hour: 18, minute: 0)
        context.insert(dinnerEntry)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "edit_food_components",
                arguments: [
                    "target_meal_type": "dinner",
                    "operations": [[
                        "type": "add",
                        "display_name": "Avocado",
                        "calories": 120,
                        "protein_grams": 2,
                        "carbs_grams": 6,
                        "fat_grams": 11
                    ]]
                ]
            )
        )

        guard case .suggestedFoodComponentEdit(let edit) = result else {
            return XCTFail("Expected suggested food component edit result")
        }

        XCTAssertEqual(edit.entryId, dinnerEntry.id)
        XCTAssertEqual(edit.operations.first?.componentName, "Avocado")
    }

    func testGetFoodLogReportsSemanticMealContextWhenStoredMealTypeIsStale() async throws {
        let dinnerEntry = FoodEntry(
            name: "Salmon Bowl",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 640,
            proteinGrams: 42,
            carbsGrams: 58,
            fatGrams: 24
        )
        dinnerEntry.input = .chat
        dinnerEntry.loggedAt = try loggedAtToday(hour: 18, minute: 30)
        context.insert(dinnerEntry)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(.init(name: "get_food_log", arguments: [:]))

        guard case .dataResponse(let functionResult) = result,
              let entries = functionResult.response["entries"] as? [[String: Any]],
              let payload = entries.first(where: { $0["id"] as? String == dinnerEntry.id.uuidString }) else {
            return XCTFail("Expected food log payload for dinner entry")
        }

        XCTAssertEqual(payload["meal_type"] as? String, FoodEntry.MealType.dinner.rawValue)
        XCTAssertEqual(payload["stored_meal_type"] as? String, FoodEntry.MealType.snack.rawValue)
        XCTAssertEqual(payload["time_context"] as? String, FoodEntry.MealType.dinner.rawValue)
    }

    func testManualSnackKeepsStoredMealTypeButStillReportsTimeContext() async throws {
        let snackEntry = FoodEntry(
            name: "Protein Bar",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 220,
            proteinGrams: 20,
            carbsGrams: 22,
            fatGrams: 7
        )
        snackEntry.input = .manual
        snackEntry.loggedAt = try loggedAtToday(hour: 18, minute: 30)
        context.insert(snackEntry)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(.init(name: "get_food_log", arguments: [:]))

        guard case .dataResponse(let functionResult) = result,
              let entries = functionResult.response["entries"] as? [[String: Any]],
              let payload = entries.first(where: { $0["id"] as? String == snackEntry.id.uuidString }) else {
            return XCTFail("Expected food log payload for manual snack entry")
        }

        XCTAssertEqual(payload["meal_type"] as? String, FoodEntry.MealType.snack.rawValue)
        XCTAssertEqual(payload["stored_meal_type"] as? String, FoodEntry.MealType.snack.rawValue)
        XCTAssertEqual(payload["time_context"] as? String, FoodEntry.MealType.dinner.rawValue)
    }

    func testSnapshotBuilderUsesSemanticMealLabelForChatEntriesWithStaleMealType() async throws {
        let dinnerEntry = FoodEntry(
            name: "Pasta",
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 610,
            proteinGrams: 24,
            carbsGrams: 86,
            fatGrams: 18
        )
        dinnerEntry.input = .chat
        dinnerEntry.loggedAt = try loggedAtToday(hour: 19, minute: 0)

        let snapshot = FoodSnapshotBuilder().buildAcceptedSnapshot(
            from: dinnerEntry,
            source: .chat
        )

        XCTAssertEqual(snapshot.mealLabel, FoodEntry.MealType.dinner.rawValue)
    }

    private func loggedAtToday(hour: Int, minute: Int) throws -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}
