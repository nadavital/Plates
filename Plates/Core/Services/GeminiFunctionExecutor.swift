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
        /// No special action needed
        case noAction
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

    init(modelContext: ModelContext, userProfile: UserProfile?) {
        self.modelContext = modelContext
        self.userProfile = userProfile
    }

    // MARK: - Execution

    /// Execute a function call and return the result
    func execute(_ call: FunctionCall) -> ExecutionResult {
        switch call.name {
        case "suggest_food_log":
            return executeSuggestFoodLog(call.arguments)

        case "edit_food_entry":
            return executeEditFoodEntry(call.arguments)

        case "get_todays_food_log":
            return executeGetTodaysFoodLog()

        case "get_user_plan":
            return executeGetUserPlan()

        case "update_user_plan":
            return executeUpdateUserPlan(call.arguments)

        case "get_recent_workouts":
            return executeGetRecentWorkouts(call.arguments)

        case "log_workout":
            return executeLogWorkout(call.arguments)

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
