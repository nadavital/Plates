//
//  GeminiChatTypes.swift
//  Trai
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

    // MARK: - Activity Data

    /// Today's activity data from Apple Health
    struct ActivityData: Sendable {
        let steps: Int
        let activeCalories: Int
        let exerciseMinutes: Int

        nonisolated static let empty = ActivityData(steps: 0, activeCalories: 0, exerciseMinutes: 0)
    }

    // MARK: - Chat Context

    /// Context for function calling chat
    struct ChatFunctionContext: Sendable {
        let profile: UserProfile?
        let todaysFoodEntries: [FoodEntry]
        let currentDateTime: String
        let conversationHistory: String
        let coachTone: TraiCoachTone
        let memoriesContext: String
        let pulseContext: String
        let pendingSuggestion: SuggestedFoodEntry?
        let isIncognitoMode: Bool
        let activeWorkout: WorkoutContext?
        let activityData: ActivityData

        init(
            profile: UserProfile?,
            todaysFoodEntries: [FoodEntry],
            currentDateTime: String,
            conversationHistory: String,
            coachTone: TraiCoachTone = .encouraging,
            memoriesContext: String,
            pulseContext: String = "",
            pendingSuggestion: SuggestedFoodEntry? = nil,
            isIncognitoMode: Bool = false,
            activeWorkout: WorkoutContext? = nil,
            activityData: ActivityData = .empty
        ) {
            self.profile = profile
            self.todaysFoodEntries = todaysFoodEntries
            self.currentDateTime = currentDateTime
            self.conversationHistory = conversationHistory
            self.coachTone = coachTone
            self.memoriesContext = memoriesContext
            self.pulseContext = pulseContext
            self.pendingSuggestion = pendingSuggestion
            self.isIncognitoMode = isIncognitoMode
            self.activeWorkout = activeWorkout
            self.activityData = activityData
        }
    }

    // MARK: - Chat Result

    /// Result from function calling chat
    struct ChatFunctionResult: Sendable {
        let message: String
        let suggestedFoods: [SuggestedFoodEntry]
        let planUpdate: PlanUpdateSuggestion?
        let suggestedFoodEdit: SuggestedFoodEdit?
        let suggestedWorkout: SuggestedWorkoutEntry?
        let suggestedWorkoutLog: SuggestedWorkoutLog?
        let suggestedReminder: SuggestedReminder?
        let functionsCalled: [String]
        let savedMemories: [String]
    }

    // MARK: - Internal Types

    /// Result from sending a function result back to Gemini
    struct FunctionFollowUpResult {
        var text: String = ""
        var suggestedFoods: [SuggestedFoodEntry] = []
        var planUpdate: PlanUpdateSuggestion?
        var suggestedFoodEdit: SuggestedFoodEdit?
        var suggestedWorkout: SuggestedWorkoutEntry?
        var suggestedWorkoutLog: SuggestedWorkoutLog?
        var suggestedReminder: SuggestedReminder?
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []
    }
}
