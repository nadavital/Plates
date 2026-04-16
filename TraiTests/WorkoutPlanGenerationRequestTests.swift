import XCTest
@testable import Trai

final class WorkoutPlanGenerationRequestTests: XCTestCase {
    func testFallbackSessionDurationUsesDefaultWhenUnspecified() {
        let request = makeRequest(timePerWorkout: nil)

        XCTAssertEqual(request.fallbackSessionDuration, 45)
    }

    func testFallbackSessionDurationClampsToSupportedBounds() {
        XCTAssertEqual(makeRequest(timePerWorkout: 10).fallbackSessionDuration, 20)
        XCTAssertEqual(makeRequest(timePerWorkout: 75).fallbackSessionDuration, 75)
        XCTAssertEqual(makeRequest(timePerWorkout: 180).fallbackSessionDuration, 120)
    }

    func testIncludesCardioHonorsSelectedWorkoutTypes() {
        let request = makeRequest(
            workoutType: .strength,
            selectedWorkoutTypes: [.strength, .cardio]
        )

        XCTAssertTrue(request.includesCardio)
    }

    private func makeRequest(
        workoutType: WorkoutPlanGenerationRequest.WorkoutType = .mixed,
        selectedWorkoutTypes: [WorkoutPlanGenerationRequest.WorkoutType]? = nil,
        timePerWorkout: Int? = nil
    ) -> WorkoutPlanGenerationRequest {
        WorkoutPlanGenerationRequest(
            name: "Test User",
            age: 30,
            gender: .notSpecified,
            goal: .health,
            activityLevel: .moderate,
            workoutType: workoutType,
            selectedWorkoutTypes: selectedWorkoutTypes,
            experienceLevel: .intermediate,
            equipmentAccess: .fullGym,
            availableDays: 4,
            timePerWorkout: timePerWorkout,
            preferredSplit: nil,
            cardioTypes: nil,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: nil,
            weakPoints: nil,
            injuries: nil,
            preferences: nil,
            conversationContext: nil
        )
    }
}
