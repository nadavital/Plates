import XCTest
@testable import Trai

final class NutritionDisplayPolicyTests: XCTestCase {
    func testTargetBasedCalorieStateShowsProgressAndRemaining() {
        let state = NutritionDisplayPolicy.calorieState(consumed: 1_750, target: 2_000)

        XCTAssertEqual(state.target, 2_000)
        XCTAssertEqual(state.remaining, 250)
        XCTAssertEqual(state.primaryValueText, "1750 / 2000")
        XCTAssertEqual(state.secondaryText, "250 kcal remaining")
        XCTAssertEqual(state.progress, 0.875, accuracy: 0.001)
    }

    func testZeroCalorieTargetCannotDivideByZero() {
        let state = NutritionDisplayPolicy.calorieState(consumed: 1_750, target: 0)

        XCTAssertEqual(state.target, 1)
        XCTAssertEqual(state.remaining, 0)
        XCTAssertEqual(state.progress, 1)
        XCTAssertEqual(state.secondaryText, "0 kcal remaining")
    }

    func testTargetBasedMacroStatesShowProgressAndRemaining() throws {
        let states = NutritionDisplayPolicy.macroStates(
            values: [.protein: 100, .carbs: 120],
            targets: [.protein: 150, .carbs: 200],
            enabledMacros: [.protein, .carbs]
        )

        let protein = try XCTUnwrap(states.first { $0.macro == .protein })
        XCTAssertEqual(protein.target, 150)
        XCTAssertEqual(protein.remaining, 50)
        XCTAssertEqual(protein.remainingText, "50g left")
        XCTAssertEqual(protein.progress, 0.666, accuracy: 0.001)
    }

    func testMissingMacroTargetFallsBackToSafeTarget() throws {
        let states = NutritionDisplayPolicy.macroStates(
            values: [.protein: 100, .carbs: 120],
            targets: [:],
            enabledMacros: [.protein, .carbs]
        )

        let protein = try XCTUnwrap(states.first { $0.macro == .protein })
        XCTAssertEqual(protein.target, 1)
        XCTAssertEqual(protein.remaining, 0)
        XCTAssertEqual(protein.remainingText, "0g left")
        XCTAssertEqual(protein.progress, 1)
        XCTAssertEqual(protein.valueText, "100g")
    }
}
