import XCTest
@testable import Trai

final class UserProfileNutritionTargetsTests: XCTestCase {
    func testNewProfilesExposeNutritionTargets() {
        let profile = UserProfile()

        XCTAssertEqual(profile.effectiveCalorieGoal(hasWorkoutToday: false), 2_000)
        XCTAssertEqual(profile.dailyProteinGoal, 150)
        XCTAssertEqual(profile.goalFor(.protein), 150)
    }

    func testTrainingAndRestDayCaloriesAdjustEffectiveTarget() {
        let profile = UserProfile()
        profile.dailyCalorieGoal = 2_200
        profile.trainingDayCalories = 2_450
        profile.restDayCalories = 2_050

        XCTAssertEqual(profile.effectiveCalorieGoal(hasWorkoutToday: true), 2_450)
        XCTAssertEqual(profile.effectiveCalorieGoal(hasWorkoutToday: false), 2_050)
    }

    func testNutritionTargetsDoNotBlockWorkoutPlanRequestBuilding() {
        let profile = UserProfile()
        profile.name = "Sam"
        profile.preferredWorkoutDays = 4
        profile.workoutTimePerSession = 50

        let request = profile.buildWorkoutPlanRequest()

        XCTAssertEqual(request.name, "Sam")
        XCTAssertEqual(request.availableDays, 4)
        XCTAssertEqual(request.timePerWorkout, 50)
    }
}
