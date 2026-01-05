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

    /// Suggested responses data (JSON encoded) - for check-in multiple choice
    var suggestedResponsesData: Data?

    /// Whether the suggested responses have been answered
    var suggestedResponsesAnswered: Bool = false

    /// Memories saved during this response (JSON encoded array of strings)
    var savedMemoriesData: Data?

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

    /// Whether this message has pending suggested responses (not yet answered)
    var hasPendingSuggestedResponses: Bool {
        suggestedResponsesData != nil && !suggestedResponsesAnswered
    }

    /// Decode the suggested responses data
    var suggestedResponses: [CheckInResponseOption]? {
        guard let data = suggestedResponsesData else { return nil }
        return try? JSONDecoder().decode([CheckInResponseOption].self, from: data)
    }

    /// Set the suggested responses data
    func setSuggestedResponses(_ responses: [CheckInResponseOption]?) {
        if let responses, !responses.isEmpty {
            suggestedResponsesData = try? JSONEncoder().encode(responses)
        } else {
            suggestedResponsesData = nil
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
