//
//  GeminiChatTypes.swift
//  Plates
//
//  Types for Gemini function calling chat
//

import Foundation

extension GeminiService {

    // MARK: - Workout Context

    /// Context about an active workout for contextual chat
    struct WorkoutContext: Sendable {
        let workoutName: String
        let elapsedMinutes: Int
        let exercisesCompleted: Int
        let exercisesTotal: Int
        let currentExercise: String?
        let setsCompleted: Int
        let totalVolume: Double
        let targetMuscleGroups: [String]

        var description: String {
            var parts: [String] = []
            parts.append("Currently doing: \(workoutName)")
            parts.append("Time: \(elapsedMinutes) minutes")
            if !targetMuscleGroups.isEmpty {
                parts.append("Target muscles: \(targetMuscleGroups.joined(separator: ", "))")
            }
            if exercisesTotal > 0 {
                parts.append("Progress: \(exercisesCompleted)/\(exercisesTotal) exercises")
            }
            if let current = currentExercise {
                parts.append("Current exercise: \(current)")
            }
            parts.append("Sets completed: \(setsCompleted)")
            if totalVolume > 0 {
                parts.append("Total volume: \(Int(totalVolume)) kg")
            }
            return parts.joined(separator: "\n")
        }
    }

    // MARK: - Chat Context

    /// Context for function calling chat
    struct ChatFunctionContext: Sendable {
        let profile: UserProfile?
        let todaysFoodEntries: [FoodEntry]
        let currentDateTime: String
        let conversationHistory: String
        let memoriesContext: String
        let pendingSuggestion: SuggestedFoodEntry?
        let isIncognitoMode: Bool
        let activeWorkout: WorkoutContext?

        init(
            profile: UserProfile?,
            todaysFoodEntries: [FoodEntry],
            currentDateTime: String,
            conversationHistory: String,
            memoriesContext: String,
            pendingSuggestion: SuggestedFoodEntry? = nil,
            isIncognitoMode: Bool = false,
            activeWorkout: WorkoutContext? = nil
        ) {
            self.profile = profile
            self.todaysFoodEntries = todaysFoodEntries
            self.currentDateTime = currentDateTime
            self.conversationHistory = conversationHistory
            self.memoriesContext = memoriesContext
            self.pendingSuggestion = pendingSuggestion
            self.isIncognitoMode = isIncognitoMode
            self.activeWorkout = activeWorkout
        }
    }

    // MARK: - Chat Result

    /// Result from function calling chat
    struct ChatFunctionResult: Sendable {
        let message: String
        let suggestedFood: SuggestedFoodEntry?
        let planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        let suggestedFoodEdit: SuggestedFoodEdit?
        let suggestedWorkout: SuggestedWorkoutEntry?
        let suggestedWorkoutLog: SuggestedWorkoutLog?
        let functionsCalled: [String]
        let savedMemories: [String]
    }

    // MARK: - Internal Types

    /// Result from sending a function result back to Gemini
    struct FunctionFollowUpResult {
        var text: String = ""
        var suggestedFood: SuggestedFoodEntry?
        var planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        var suggestedFoodEdit: SuggestedFoodEdit?
        var suggestedWorkout: SuggestedWorkoutEntry?
        var suggestedWorkoutLog: SuggestedWorkoutLog?
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []
    }
}
