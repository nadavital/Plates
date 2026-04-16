import XCTest
@testable import Trai

final class UserProfileWorkoutPlanRequestTests: XCTestCase {
    func testBuildWorkoutPlanRequestFallsBackToStoredSessionDuration() {
        let profile = UserProfile()
        profile.workoutTimePerSession = 55

        let request = profile.buildWorkoutPlanRequest()

        XCTAssertEqual(request.timePerWorkout, 55)
    }

    func testBuildWorkoutPlanRequestPrefersExplicitSessionDurationOverride() {
        let profile = UserProfile()
        profile.workoutTimePerSession = 55

        let request = profile.buildWorkoutPlanRequest(timePerWorkout: 40)

        XCTAssertEqual(request.timePerWorkout, 40)
    }
}
