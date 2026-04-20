//
//  AIFunctionExecutor.swift
//  Trai
//
//  Executes AI function calls locally and formats results
//  Extensions: AIFunctionExecutor+Food.swift, AIFunctionExecutor+PlanWorkout.swift
//

import Foundation
import SwiftData

/// Executes AI function calls and returns results
@MainActor
final class AIFunctionExecutor {

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
        /// Direct text to return to the user without another follow-up model pass
        case directMessage(String)
        /// Data to send back to the AI backend for final response
        case dataResponse(FunctionResult)
        /// Food suggestion to show user (needs confirmation)
        case suggestedFood(SuggestedFoodEntry)
        /// Plan update suggestion (needs confirmation)
        case suggestedPlanUpdate(PlanUpdateSuggestion)
        /// Food edit suggestion to show user (needs confirmation before applying)
        case suggestedFoodEdit(SuggestedFoodEdit)
        /// Food component edit suggestion to show user (needs confirmation before applying)
        case suggestedFoodComponentEdit(SuggestedFoodComponentEdit)
        /// Workout plan update suggestion (needs confirmation)
        case suggestedWorkoutPlanUpdate(WorkoutPlanSuggestionEntry)
        /// Workout suggestion to show user (needs confirmation)
        case suggestedWorkout(WorkoutSuggestion)
        /// Workout start suggestion (needs user approval before starting)
        case suggestedWorkoutStart(SuggestedWorkoutEntry)
        /// Workout log suggestion (needs user approval before saving)
        case suggestedWorkoutLog(SuggestedWorkoutLog)
        /// Live workout started - navigate to tracker
        case startedLiveWorkout(LiveWorkout)
        /// Reminder suggestion to show user (needs confirmation)
        case suggestedReminder(SuggestedReminder)
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

    // MARK: - Dependencies

    let modelContext: ModelContext
    let userProfile: UserProfile?
    let pendingWorkoutPlan: WorkoutPlan?
    let isIncognitoMode: Bool
    let activityData: AIService.ActivityData

    init(
        modelContext: ModelContext,
        userProfile: UserProfile?,
        pendingWorkoutPlan: WorkoutPlan? = nil,
        isIncognitoMode: Bool = false,
        activityData: AIService.ActivityData = .empty
    ) {
        self.modelContext = modelContext
        self.userProfile = userProfile
        self.pendingWorkoutPlan = pendingWorkoutPlan
        self.isIncognitoMode = isIncognitoMode
        self.activityData = activityData
    }

    // MARK: - Execution

    /// Execute a function call and return the result
    func execute(_ call: FunctionCall) async -> ExecutionResult {
        switch call.name {
        case "suggest_food_log":
            return executeSuggestFoodLog(call.arguments)

        case "edit_food_entry":
            return executeEditFoodEntry(call.arguments)

        case "edit_food_components":
            return executeEditFoodComponents(call.arguments)

        case "get_food_log":
            return executeGetFoodLog(call.arguments)

        case "get_user_plan":
            return executeGetUserPlan()

        case "update_user_plan":
            return executeUpdateUserPlan(call.arguments)

        case "get_recent_workouts":
            return executeGetRecentWorkouts(call.arguments)

        case "revise_workout_plan":
            return await executeReviseWorkoutPlan(call.arguments)

        case "get_workout_goals":
            return executeGetWorkoutGoals(call.arguments)

        case "create_workout_goal":
            return executeCreateWorkoutGoal(call.arguments)

        case "update_workout_goal":
            return executeUpdateWorkoutGoal(call.arguments)

        case "update_workout_notes":
            return executeUpdateWorkoutNotes(call.arguments)

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

        case "log_weight":
            return executeLogWeight(call.arguments)

        case "get_activity_summary":
            return executeGetActivitySummary()

        case "save_memory":
            return executeSaveMemory(call.arguments)

        case "delete_memory":
            return executeDeleteMemory(call.arguments)

        case "save_short_term_context":
            return executeSaveShortTermContext(call.arguments)

        case "clear_short_term_context":
            return executeClearShortTermContext(call.arguments)

        case "create_reminder":
            return executeCreateReminder(call.arguments)

        default:
            return .dataResponse(FunctionResult(
                name: call.name,
                response: ["error": "Unknown function: \(call.name)"]
            ))
        }
    }
}
