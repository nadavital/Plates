import Foundation
import SwiftData

/// Represents a message in the AI chat conversation
@Model
final class ChatMessage {
    var id: UUID = UUID()

    /// The message content
    var content: String = ""

    /// Whether this message is from the user (true) or AI (false)
    var isFromUser: Bool = true

    var timestamp: Date = Date()

    /// Session ID to group messages into conversations
    var sessionId: UUID?

    /// Summary of context that was provided to AI for this response
    var contextSummary: String?

    /// Whether the message is still being generated
    var isLoading: Bool = false

    /// Error message if the request failed
    var errorMessage: String?

    /// Image data attached to this message (for food logging via chat)
    var imageData: Data?

    /// Food entry logged from this message (AI response with logMeal action)
    var loggedFoodEntryId: UUID?

    /// Suggested meal data (JSON encoded) - for confirmation before logging
    var suggestedMealData: Data?

    /// Whether the user has dismissed the meal suggestion
    var suggestedMealDismissed: Bool = false

    /// Suggested plan update data (JSON encoded) - for confirmation before applying
    var suggestedPlanData: Data?

    /// Whether the user has dismissed the plan suggestion
    var suggestedPlanDismissed: Bool = false

    /// Whether a plan update was applied from this message
    var planUpdateApplied: Bool = false

    /// Memories saved during this response (JSON encoded array of strings)
    var savedMemoriesData: Data?

    /// Food edit confirmation data (JSON encoded) - shows changes made to existing food entry
    var foodEditData: Data?

    init() {}

    init(content: String, isFromUser: Bool, sessionId: UUID? = nil, imageData: Data? = nil) {
        self.content = content
        self.isFromUser = isFromUser
        self.sessionId = sessionId
        self.imageData = imageData
    }

    /// Whether this message has an attached image
    var hasImage: Bool {
        imageData != nil
    }

    /// Whether this message has a pending meal suggestion (not yet logged or dismissed)
    var hasPendingMealSuggestion: Bool {
        suggestedMealData != nil && loggedFoodEntryId == nil && !suggestedMealDismissed
    }

    /// Decode the suggested meal data
    var suggestedMeal: SuggestedFoodEntry? {
        guard let data = suggestedMealData else { return nil }
        return try? JSONDecoder().decode(SuggestedFoodEntry.self, from: data)
    }

    /// Set the suggested meal data
    func setSuggestedMeal(_ meal: SuggestedFoodEntry?) {
        if let meal {
            suggestedMealData = try? JSONEncoder().encode(meal)
        } else {
            suggestedMealData = nil
        }
    }

    /// Whether this message has a pending plan suggestion (not yet applied or dismissed)
    var hasPendingPlanSuggestion: Bool {
        suggestedPlanData != nil && !planUpdateApplied && !suggestedPlanDismissed
    }

    /// Decode the suggested plan data
    var suggestedPlan: PlanUpdateSuggestionEntry? {
        guard let data = suggestedPlanData else { return nil }
        return try? JSONDecoder().decode(PlanUpdateSuggestionEntry.self, from: data)
    }

    /// Set the suggested plan data
    func setSuggestedPlan(_ plan: PlanUpdateSuggestionEntry?) {
        if let plan {
            suggestedPlanData = try? JSONEncoder().encode(plan)
        } else {
            suggestedPlanData = nil
        }
    }

    /// Whether this message has saved memories
    var hasSavedMemories: Bool {
        guard let data = savedMemoriesData else { return false }
        guard let memories = try? JSONDecoder().decode([String].self, from: data) else { return false }
        return !memories.isEmpty
    }

    /// Decode the saved memories
    var savedMemories: [String] {
        guard let data = savedMemoriesData else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Add a saved memory to this message
    func addSavedMemory(_ content: String) {
        var memories = savedMemories
        memories.append(content)
        savedMemoriesData = try? JSONEncoder().encode(memories)
    }

    /// Whether the user has dismissed the suggested food edit
    var suggestedFoodEditDismissed: Bool = false

    /// Whether the food edit has been applied
    var foodEditApplied: Bool = false

    /// Whether this message has a pending food edit suggestion (not yet applied or dismissed)
    var hasPendingFoodEdit: Bool {
        foodEditData != nil && !foodEditApplied && !suggestedFoodEditDismissed
    }

    /// Whether this message has an applied food edit
    var hasAppliedFoodEdit: Bool {
        foodEditData != nil && foodEditApplied
    }

    /// Decode the suggested food edit
    var suggestedFoodEdit: SuggestedFoodEdit? {
        guard let data = foodEditData else { return nil }
        return try? JSONDecoder().decode(SuggestedFoodEdit.self, from: data)
    }

    /// Set the suggested food edit data
    func setSuggestedFoodEdit(_ edit: SuggestedFoodEdit?) {
        if let edit {
            foodEditData = try? JSONEncoder().encode(edit)
        } else {
            foodEditData = nil
        }
    }

    // MARK: - Workout Suggestions

    /// Suggested workout data (JSON encoded) - for confirmation before starting
    var suggestedWorkoutData: Data?

    /// Whether the user has dismissed the workout suggestion
    var suggestedWorkoutDismissed: Bool = false

    /// Whether the workout was started from this message
    var workoutStarted: Bool = false

    /// ID of the started workout (for navigation)
    var startedWorkoutId: UUID?

    /// Whether this message has a pending workout suggestion (not yet started or dismissed)
    var hasPendingWorkoutSuggestion: Bool {
        suggestedWorkoutData != nil && !workoutStarted && !suggestedWorkoutDismissed
    }

    /// Whether this message has a started workout
    var hasStartedWorkout: Bool {
        suggestedWorkoutData != nil && workoutStarted
    }

    /// Decode the suggested workout data
    var suggestedWorkout: SuggestedWorkoutEntry? {
        guard let data = suggestedWorkoutData else { return nil }
        return try? JSONDecoder().decode(SuggestedWorkoutEntry.self, from: data)
    }

    /// Set the suggested workout data
    func setSuggestedWorkout(_ workout: SuggestedWorkoutEntry?) {
        if let workout {
            suggestedWorkoutData = try? JSONEncoder().encode(workout)
        } else {
            suggestedWorkoutData = nil
        }
    }

    // MARK: - Workout Log Suggestions

    /// Suggested workout log data (JSON encoded) - for confirmation before saving
    var suggestedWorkoutLogData: Data?

    /// Whether the user has dismissed the workout log suggestion
    var suggestedWorkoutLogDismissed: Bool = false

    /// Whether the workout log was saved from this message
    var workoutLogSaved: Bool = false

    /// Whether this message has a pending workout log suggestion (not yet saved or dismissed)
    var hasPendingWorkoutLogSuggestion: Bool {
        suggestedWorkoutLogData != nil && !workoutLogSaved && !suggestedWorkoutLogDismissed
    }

    /// Whether this message has a saved workout log
    var hasSavedWorkoutLog: Bool {
        suggestedWorkoutLogData != nil && workoutLogSaved
    }

    /// Decode the suggested workout log data
    var suggestedWorkoutLog: SuggestedWorkoutLog? {
        guard let data = suggestedWorkoutLogData else { return nil }
        return try? JSONDecoder().decode(SuggestedWorkoutLog.self, from: data)
    }

    /// Set the suggested workout log data
    func setSuggestedWorkoutLog(_ workoutLog: SuggestedWorkoutLog?) {
        if let workoutLog {
            suggestedWorkoutLogData = try? JSONEncoder().encode(workoutLog)
        } else {
            suggestedWorkoutLogData = nil
        }
    }

    /// Create a loading placeholder message for AI response
    static func loadingMessage() -> ChatMessage {
        let message = ChatMessage(content: "", isFromUser: false)
        message.isLoading = true
        return message
    }

    /// Create an error message
    static func errorMessage(_ error: String) -> ChatMessage {
        let message = ChatMessage(content: "", isFromUser: false)
        message.errorMessage = error
        return message
    }
}

// MARK: - Suggested Prompts

extension ChatMessage {
    /// Suggested prompts for the user to start a conversation
    static let suggestedPrompts: [(title: String, prompt: String)] = [
        ("Today's plan", "What should I eat and how should I work out today based on my goals?"),
        ("Meal ideas", "Can you suggest some healthy meal ideas for my next meal?"),
        ("Workout suggestion", "What workout should I do today based on my recent activity?"),
        ("Progress check", "How am I doing with my fitness goals? Any suggestions?"),
        ("Nutrition tips", "What are some tips to hit my protein goal today?"),
        ("Recovery advice", "I'm feeling sore. What should I do for recovery?"),
    ]
}
