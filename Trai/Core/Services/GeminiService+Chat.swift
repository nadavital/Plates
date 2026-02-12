//
//  GeminiService+Chat.swift
//  Trai
//
//  Chat and conversation methods
//

import Foundation
import os

extension GeminiService {

    // MARK: - Chat

    /// Chat with the AI fitness coach (non-streaming)
    func chat(
        message: String,
        context: FitnessContext,
        conversationHistory: [ChatMessage] = [],
        tone: TraiCoachTone = .sharedPreference
    ) async throws -> String {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let contents = buildChatContents(
            message: message,
            context: context,
            conversationHistory: conversationHistory,
            tone: tone
        )

        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": buildGenerationConfig(thinkingLevel: .low)
        ]

        return try await makeRequest(body: requestBody)
    }

    /// Chat with streaming response - calls onChunk with each text chunk as it arrives
    func chatStreaming(
        message: String,
        context: FitnessContext,
        conversationHistory: [ChatMessage] = [],
        tone: TraiCoachTone = .sharedPreference,
        onChunk: @escaping (String) -> Void
    ) async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let contents = buildChatContents(
            message: message,
            context: context,
            conversationHistory: conversationHistory,
            tone: tone
        )

        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": buildGenerationConfig(thinkingLevel: .low)
        ]

        try await makeStreamingRequest(body: requestBody, onChunk: onChunk)
    }

    /// Chat with structured output - can suggest meals from text descriptions
    func chatStructured(
        message: String,
        context: FitnessContext,
        conversationHistory: [ChatMessage] = [],
        pendingSuggestion: SuggestedFoodEntry? = nil,
        tone: TraiCoachTone = .sharedPreference
    ) async throws -> ChatFoodAnalysisResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        let currentDateTime = dateFormatter.string(from: Date())

        let historyString = conversationHistory.suffix(6)
            .map { ($0.isFromUser ? "User" : "Coach") + ": " + $0.content }
            .joined(separator: "\n")

        let prompt = GeminiPromptBuilder.buildTextChatPrompt(
            userMessage: message,
            context: context,
            currentDateTime: currentDateTime,
            conversationHistory: historyString,
            pendingSuggestion: pendingSuggestion,
            tone: tone
        )

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .medium,
                jsonSchema: GeminiPromptBuilder.chatImageAnalysisSchema
            )
        ]

        let responseText = try await makeRequest(body: requestBody)
        return try parseChatFoodAnalysis(from: responseText)
    }

    func buildChatContents(
        message: String,
        context: FitnessContext,
        conversationHistory: [ChatMessage],
        tone: TraiCoachTone = .sharedPreference
    ) -> [[String: Any]] {
        var contents: [[String: Any]] = []

        let systemPrompt = GeminiPromptBuilder.buildSystemPrompt(context: context, tone: tone)
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": tone.primingReply]]
        ])

        for msg in conversationHistory.suffix(10) {
            contents.append([
                "role": msg.isFromUser ? "user" : "model",
                "parts": [["text": msg.content]]
            ])
        }

        contents.append([
            "role": "user",
            "parts": [["text": message]]
        ])

        return contents
    }

    // MARK: - Nutrition Advice

    /// Get nutrition advice based on today's meals and goals
    func getNutritionAdvice(todaysMeals: [FoodEntry], profile: UserProfile) async throws -> String {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let prompt = GeminiPromptBuilder.buildNutritionAdvicePrompt(meals: todaysMeals, profile: profile)

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(thinkingLevel: .medium)
        ]

        return try await makeRequest(body: requestBody)
    }
}
