//
//  AIService+Chat.swift
//  Trai
//
//  Chat and conversation methods
//

import Foundation
import os

extension AIService {

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
        return try await performAIRequest(for: .coachChat) {
            let messages = buildChatMessages(
                message: message,
                context: context,
                conversationHistory: conversationHistory,
                tone: tone
            )

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: messages,
                generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .low)
            )

            return try await makeRequest(request: request)
        }
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
        try await performAIRequest(for: .coachChat) {
            let messages = buildChatMessages(
                message: message,
                context: context,
                conversationHistory: conversationHistory,
                tone: tone
            )

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: messages,
                generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .low)
            )

            try await makeStreamingRequest(request: request, onChunk: onChunk)
        }
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
        return try await performAIRequest(for: .coachChat) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
            let currentDateTime = dateFormatter.string(from: Date())

            let historyString = conversationHistory.suffix(6)
                .map { ($0.isFromUser ? "User" : "Coach") + ": " + $0.content }
                .joined(separator: "\n")

            let prompt = AIPromptBuilder.buildTextChatPrompt(
                userMessage: message,
                context: context,
                currentDateTime: currentDateTime,
                conversationHistory: historyString,
                pendingSuggestion: pendingSuggestion,
                tone: tone
            )

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: AIPromptBuilder.chatImageAnalysisSchema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .medium
                )
            )

            let responseText = try await makeRequest(request: request)
            return try parseChatFoodAnalysis(from: responseText)
        }
    }

    func buildChatMessages(
        message: String,
        context: FitnessContext,
        conversationHistory: [ChatMessage],
        tone: TraiCoachTone = .sharedPreference
    ) -> [TraiAIMessage] {
        var contents: [TraiAIMessage] = []

        let systemPrompt = AIPromptBuilder.buildSystemPrompt(context: context, tone: tone)
        contents.append(
            AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: systemPrompt)
        )
        contents.append(
            AIBackendPayloadBuilder.canonicalTextMessage(role: .assistant, text: tone.primingReply)
        )

        for msg in conversationHistory.suffix(10) {
            contents.append(
                AIBackendPayloadBuilder.canonicalTextMessage(
                    role: msg.isFromUser ? .user : .assistant,
                    text: msg.content
                )
            )
        }

        contents.append(
            AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: message)
        )

        return contents
    }

    // MARK: - Nutrition Advice

    /// Get nutrition advice based on today's meals and goals
    func getNutritionAdvice(todaysMeals: [FoodEntry], profile: UserProfile) async throws -> String {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .nutritionAdvice) {
            let prompt = AIPromptBuilder.buildNutritionAdvicePrompt(meals: todaysMeals, profile: profile)

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
                ],
                generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .medium)
            )

            return try await makeRequest(request: request)
        }
    }
}
