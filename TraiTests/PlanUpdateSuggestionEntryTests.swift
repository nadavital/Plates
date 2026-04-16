import XCTest
@testable import Trai

final class PlanUpdateSuggestionEntryTests: XCTestCase {
    func testHasChangesTreatsFiberAndSugarAsTopLevelPlanChanges() {
        let fiberSuggestion = PlanUpdateSuggestionEntry(fiberGrams: 30)
        let sugarSuggestion = PlanUpdateSuggestionEntry(sugarGrams: 45)

        XCTAssertTrue(fiberSuggestion.hasChanges)
        XCTAssertTrue(sugarSuggestion.hasChanges)
    }

    func testIdentifierIncludesFiberAndSugarValues() {
        let lowerSugar = PlanUpdateSuggestionEntry(calories: 2200, sugarGrams: 40)
        let higherSugar = PlanUpdateSuggestionEntry(calories: 2200, sugarGrams: 55)
        let fiberAdjusted = PlanUpdateSuggestionEntry(calories: 2200, fiberGrams: 35, sugarGrams: 40)

        XCTAssertNotEqual(lowerSugar.id, higherSugar.id)
        XCTAssertNotEqual(lowerSugar.id, fiberAdjusted.id)
    }
}
