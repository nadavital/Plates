import XCTest
import SwiftData
@testable import Trai

@MainActor
final class WorkoutSemanticParsingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: WorkoutGoal.self,
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

    func testWorkoutModeNormalizationHandlesCommonPhrases() {
        XCTAssertEqual(WorkoutMode.normalized(from: "running"), .cardio)
        XCTAssertEqual(WorkoutMode.normalized(from: "strength training"), .strength)
        XCTAssertEqual(WorkoutMode.normalized(from: "weight-lifting"), .strength)
        XCTAssertEqual(WorkoutMode.normalized(from: "bouldering"), .climbing)
        XCTAssertEqual(WorkoutMode.normalized(from: "stretching"), .flexibility)
    }

    func testTargetMuscleParsingHandlesDisplayNames() {
        XCTAssertEqual(LiveWorkout.MuscleGroup.fromTargetStrings(["Full Body"]), [.fullBody])
        XCTAssertEqual(
            LiveWorkout.MuscleGroup.fromTargetStrings(["Lower Body"]),
            LiveWorkout.MuscleGroup.legMuscles
        )
    }

    func testCreateWorkoutGoalNormalizesRunningToCardio() async throws {
        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "create_workout_goal",
                arguments: [
                    "title": "Run three times per week",
                    "goal_kind": "frequency",
                    "workout_type": "running",
                    "period_unit": "week",
                    "period_count": 1,
                    "success_criteria": "Complete three cardio sessions in one week."
                ]
            )
        )

        guard case .dataResponse(let functionResult) = result,
              let goal = functionResult.response["goal"] as? [String: Any] else {
            return XCTFail("Expected workout goal response")
        }

        XCTAssertEqual(goal["workout_type"] as? String, WorkoutMode.cardio.rawValue)
        XCTAssertEqual(goal["success_criteria"] as? String, "Complete three cardio sessions in one week.")
    }

    func testUpdateWorkoutGoalNormalizesWeightLiftingToStrength() async throws {
        let goal = WorkoutGoal(
            title: "Move more",
            goalKind: .frequency,
            linkedWorkoutType: .cardio
        )
        context.insert(goal)
        try context.save()

        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "update_workout_goal",
                arguments: [
                    "goal_id": goal.id.uuidString,
                    "workout_type": "weight lifting"
                ]
            )
        )

        guard case .dataResponse(let functionResult) = result,
              let updatedGoal = functionResult.response["goal"] as? [String: Any] else {
            return XCTFail("Expected updated workout goal response")
        }

        XCTAssertEqual(updatedGoal["workout_type"] as? String, WorkoutMode.strength.rawValue)
        XCTAssertEqual(goal.linkedWorkoutType, .strength)
    }

    func testLogWorkoutNormalizesRunningType() async {
        let executor = AIFunctionExecutor(modelContext: context, userProfile: nil)
        let result = await executor.execute(
            .init(
                name: "log_workout",
                arguments: [
                    "type": "running",
                    "name": "Morning run",
                    "duration_minutes": 35
                ]
            )
        )

        guard case .suggestedWorkoutLog(let workoutLog) = result else {
            return XCTFail("Expected suggested workout log")
        }

        XCTAssertEqual(workoutLog.workoutType, WorkoutMode.cardio.rawValue)
    }
}
