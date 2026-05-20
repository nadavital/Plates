import XCTest
@testable import Trai

final class OnboardingFlowPlannerTests: XCTestCase {
    func testFirstRunOnboardingKeepsOnlyPlanCriticalSteps() {
        let steps = OnboardingFlowPlanner.steps()

        XCTAssertEqual(steps, [
            .welcome,
            .goals,
            .biometrics,
            .activity,
            .nutritionPlan
        ])
        XCTAssertFalse(steps.contains(.macroPreferences))
        XCTAssertFalse(steps.contains(.health))
        XCTAssertFalse(steps.contains(.workoutSetup))
        XCTAssertEqual(steps.last, .nutritionPlan)
    }
}
