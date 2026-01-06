//
//  GeminiChatTypes.swift
//  Plates
//
//  Types for Gemini function calling chat
//

import Foundation

extension GeminiService {

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

        init(
            profile: UserProfile?,
            todaysFoodEntries: [FoodEntry],
            currentDateTime: String,
            conversationHistory: String,
            memoriesContext: String,
            pendingSuggestion: SuggestedFoodEntry? = nil,
            isIncognitoMode: Bool = false
        ) {
            self.profile = profile
            self.todaysFoodEntries = todaysFoodEntries
            self.currentDateTime = currentDateTime
            self.conversationHistory = conversationHistory
            self.memoriesContext = memoriesContext
            self.pendingSuggestion = pendingSuggestion
            self.isIncognitoMode = isIncognitoMode
        }
    }

    // MARK: - Chat Result

    /// Result from function calling chat
    struct ChatFunctionResult: Sendable {
        let message: String
        let suggestedFood: SuggestedFoodEntry?
        let planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        let suggestedFoodEdit: SuggestedFoodEdit?
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
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []
    }
}
