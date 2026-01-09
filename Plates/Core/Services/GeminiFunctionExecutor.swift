//
//  GeminiFunctionExecutor.swift
//  Plates
//
//  Executes Gemini function calls locally and formats results
//  Extensions: GeminiFunctionExecutor+Food.swift, GeminiFunctionExecutor+PlanWorkout.swift
//

import Foundation
import SwiftData

/// Executes function calls from Gemini and returns results
@MainActor
final class GeminiFunctionExecutor {

    // MARK: - Types

    struct FunctionCall: Sendable {
        let name: String
        let arguments: [String: Any]

        init(name: String, arguments: [String: Any]) {
            self.name = name
            self.arguments = arguments
        }
    }

    struct FunctionResult: Sendable {
        let name: String
        let response: [String: Any]
    }

    enum ExecutionResult {
        /// Data to send back to Gemini for final response
        case dataResponse(FunctionResult)
        /// Food suggestion to show user (needs confirmation)
        case suggestedFood(SuggestedFoodEntry)
        /// Plan update suggestion (needs confirmation)
        case suggestedPlanUpdate(PlanUpdateSuggestion)
        /// Food edit suggestion to show user (needs confirmation before applying)
        case suggestedFoodEdit(SuggestedFoodEdit)
        /// Workout suggestion to show user (needs confirmation)
        case suggestedWorkout(WorkoutSuggestion)
        /// Workout start suggestion (needs user approval before starting)
        case suggestedWorkoutStart(SuggestedWorkoutEntry)
        /// Workout log suggestion (needs user approval before saving)
        case suggestedWorkoutLog(SuggestedWorkoutLog)
        /// Live workout started - navigate to tracker
        case startedLiveWorkout(LiveWorkout)
        /// No special action needed
        case noAction
    }

    struct WorkoutSuggestion {
        let name: String
        let workoutType: LiveWorkout.WorkoutType
        let targetMuscleGroups: [LiveWorkout.MuscleGroup]
        let exercises: [SuggestedExercise]
        let durationMinutes: Int
        let rationale: String

        struct SuggestedExercise: Identifiable {
            let id = UUID()
            let name: String
            let sets: Int
            let reps: Int
            let weightKg: Double?
        }
    }

    struct PlanUpdateSuggestion {
        let calories: Int?
        let proteinGrams: Int?
        let carbsGrams: Int?
        let fatGrams: Int?
        let goal: String?
        let rationale: String?
    }

    // MARK: - Dependencies

    let modelContext: ModelContext
    let userProfile: UserProfile?
    let isIncognitoMode: Bool

    init(modelContext: ModelContext, userProfile: UserProfile?, isIncognitoMode: Bool = false) {
        self.modelContext = modelContext
        self.userProfile = userProfile
        self.isIncognitoMode = isIncognitoMode
    }

    // MARK: - Execution

    /// Execute a function call and return the result
    func execute(_ call: FunctionCall) -> ExecutionResult {
        switch call.name {
        case "suggest_food_log":
            return executeSuggestFoodLog(call.arguments)

        case "edit_food_entry":
            return executeEditFoodEntry(call.arguments)

        case "get_food_log":
            return executeGetFoodLog(call.arguments)

        case "get_user_plan":
            return executeGetUserPlan()

        case "update_user_plan":
            return executeUpdateUserPlan(call.arguments)

        case "get_recent_workouts":
            return executeGetRecentWorkouts(call.arguments)

        case "log_workout":
            return executeLogWorkout(call.arguments)

        case "get_muscle_recovery_status":
            return executeGetMuscleRecoveryStatus()

        case "suggest_workout":
            return executeSuggestWorkout(call.arguments)

        case "start_live_workout":
            return executeStartLiveWorkout(call.arguments)

        case "get_weight_history":
            return executeGetWeightHistory(call.arguments)

        case "save_memory":
            return executeSaveMemory(call.arguments)

        case "delete_memory":
            return executeDeleteMemory(call.arguments)

        default:
            return .dataResponse(FunctionResult(
                name: call.name,
                response: ["error": "Unknown function: \(call.name)"]
            ))
        }
    }
}
