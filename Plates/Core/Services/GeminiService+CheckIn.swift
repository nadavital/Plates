//
//  GeminiService+CheckIn.swift
//  Plates
//
//  Check-in specific Gemini methods with streaming + structured output
//

import Foundation
import SwiftData
import os.log

extension GeminiService {

    // MARK: - Check-In Schema

    /// JSON schema for structured check-in responses (lowercase types per Gemini docs)
    private var checkInResponseSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "message": [
                    "type": "string",
                    "description": "Your conversational response to the user (2-4 sentences max)"
                ],
                "suggestedResponses": [
                    "type": "array",
                    "description": "2-4 quick response options for the user to tap",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "label": ["type": "string", "description": "Short response text (2-6 words)"],
                            "emoji": ["type": "string", "description": "Single emoji for this option"]
                        ],
                        "required": ["id", "label"]
                    ]
                ],
                "isComplete": [
                    "type": "boolean",
                    "description": "Set to true when the check-in conversation is complete"
                ],
                "summary": [
                    "type": "string",
                    "description": "Brief summary of the check-in (only when isComplete is true)"
                ]
            ],
            "required": ["message", "suggestedResponses"]
        ]
    }

    // MARK: - Streaming Check-In Chat

    /// Result from streaming check-in chat
    struct CheckInChatResult: Sendable {
        let message: String
        let suggestedResponses: [CheckInResponseOption]
        let isComplete: Bool
        let summary: String?
    }

    /// Stream a check-in conversation with structured output
    func streamCheckInChat(
        message: String,
        summary: CheckInService.WeeklySummary,
        profile: UserProfile,
        conversationHistory: [ChatMessage],
        previousCheckIns: [WeeklyCheckIn] = [],
        onTextChunk: @escaping (String) -> Void
    ) async throws -> CheckInChatResult {
        isLoading = true
        defer { isLoading = false }

        log("🔧 Starting streaming check-in chat", type: .info)

        let systemPrompt = buildCheckInSystemPrompt(
            summary: summary,
            profile: profile,
            previousCheckIns: previousCheckIns
        )

        var contents: [[String: Any]] = []

        // Add system prompt
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": "{\"message\": \"Got it, I'll conduct a friendly check-in with suggested responses.\"}"]]
        ])

        // Add conversation history
        for msg in conversationHistory.suffix(10) {
            if !msg.content.isEmpty {
                let parts: [[String: Any]] = [["text": msg.content]]
                contents.append([
                    "role": msg.isFromUser ? "user" : "model",
                    "parts": parts
                ])
            }
        }

        // Add current message
        contents.append([
            "role": "user",
            "parts": [["text": message]]
        ])

        // Build request with structured output
        let config = buildGenerationConfig(
            thinkingLevel: .low,
            maxTokens: 1024,
            jsonSchema: checkInResponseSchema
        )

        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": config
        ]

        // Use streaming API
        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(Secrets.geminiAPIKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        var accumulatedJSON = ""
        var lastExtractedMessage = ""

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeminiError.invalidResponse
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let candidate = candidates.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let part = parts.first,
                  let text = part["text"] as? String else { continue }

            accumulatedJSON += text

            // Try to extract message from partial JSON for streaming display
            if let extractedMessage = extractMessageFromPartialJSON(accumulatedJSON),
               extractedMessage != lastExtractedMessage {
                lastExtractedMessage = extractedMessage
                await MainActor.run {
                    onTextChunk(extractedMessage)
                }
            }
        }

        // Parse the complete JSON response
        log("📥 Complete JSON: \(accumulatedJSON)", type: .debug)

        guard let jsonData = accumulatedJSON.data(using: .utf8),
              let response = try? JSONDecoder().decode(CheckInAIResponse.self, from: jsonData) else {
            log("❌ Failed to parse check-in response. Raw: \(accumulatedJSON)", type: .error)
            // Return basic response if parsing fails
            return CheckInChatResult(
                message: lastExtractedMessage.isEmpty ? "How are you feeling about this week?" : lastExtractedMessage,
                suggestedResponses: [],
                isComplete: false,
                summary: nil
            )
        }

        log("✅ Check-in response parsed. Suggested responses: \(response.suggestedResponses?.count ?? 0)", type: .info)

        return CheckInChatResult(
            message: response.message,
            suggestedResponses: response.suggestedResponses ?? [],
            isComplete: response.isComplete ?? false,
            summary: response.summary
        )
    }

    /// Extract message field from partial JSON for streaming display
    private func extractMessageFromPartialJSON(_ json: String) -> String? {
        // Look for "message": "..." pattern
        guard let messageStart = json.range(of: "\"message\":\\s*\"", options: .regularExpression) else {
            return nil
        }

        let afterMessageKey = json[messageStart.upperBound...]

        // Find the content, handling escaped quotes
        var content = ""
        var i = afterMessageKey.startIndex
        var escapeNext = false

        while i < afterMessageKey.endIndex {
            let char = afterMessageKey[i]

            if escapeNext {
                // Handle common escapes
                switch char {
                case "n": content += "\n"
                case "t": content += "\t"
                case "\"": content += "\""
                case "\\": content += "\\"
                default: content += String(char)
                }
                escapeNext = false
            } else if char == "\\" {
                escapeNext = true
            } else if char == "\"" {
                // End of string
                break
            } else {
                content += String(char)
            }

            i = afterMessageKey.index(after: i)
        }

        return content.isEmpty ? nil : content
    }

    // MARK: - Check-In System Prompt

    private func buildCheckInSystemPrompt(
        summary: CheckInService.WeeklySummary,
        profile: UserProfile,
        previousCheckIns: [WeeklyCheckIn]
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let weekRange = "\(dateFormatter.string(from: summary.weekStartDate)) - \(dateFormatter.string(from: summary.weekEndDate))"

        var previousContext = ""
        if !previousCheckIns.isEmpty {
            let recent = previousCheckIns.prefix(3)
            previousContext = """

            Previous check-ins:
            \(recent.map { checkIn in
                "- \(dateFormatter.string(from: checkIn.checkInDate)): Focus was '\(checkIn.userFocusNextWeek ?? "not set")'"
            }.joined(separator: "\n"))
            """
        }

        return """
        You are Trai, a supportive fitness coach conducting a weekly check-in with \(profile.name). Never refer to yourself as an AI or assistant.
        Keep responses SHORT (2-4 sentences). Be warm and conversational, not formal.

        CRITICAL: You MUST include "suggestedResponses" array with 2-4 options in EVERY response.
        Each option needs: id (unique string), label (2-6 words), emoji (single emoji).
        Make options feel natural - mix positive, neutral, and honest choices.

        This week's data (\(weekRange)):
        - Days tracked: \(summary.daysTracked)/7
        - Avg calories: \(summary.averageDailyCalories) (goal: \(summary.calorieGoal))
        - Avg protein: \(Int(summary.averageProtein))g (goal: \(summary.proteinGoal)g)
        - Calorie adherence: \(Int(summary.calorieAdherence * 100))%
        - Protein adherence: \(Int(summary.proteinAdherence * 100))%
        - Workouts: \(summary.workoutsCompleted)
        \(summary.weightChangeFormatted.map { "- Weight change: \($0)" } ?? "")
        \(previousContext)

        Goal: \(profile.goal.displayName)

        Check-in flow (ask one question at a time):
        1. Greeting acknowledging their week's data
        2. How they're feeling/energy levels
        3. What went well this week
        4. Any challenges they faced
        5. Focus for next week
        6. When done, set isComplete=true and provide summary

        Example response format:
        {"message": "Your message here", "suggestedResponses": [{"id": "1", "label": "Great overall", "emoji": "💪"}, {"id": "2", "label": "Had some struggles", "emoji": "😅"}]}

        Respond ONLY with valid JSON. No markdown, no extra text.
        """
    }

    // MARK: - Generate Initial Greeting (Streaming)

    /// Generate the initial check-in greeting with streaming
    func streamCheckInGreeting(
        summary: CheckInService.WeeklySummary,
        profile: UserProfile,
        onTextChunk: @escaping (String) -> Void
    ) async throws -> CheckInChatResult {
        log("👋 Generating streaming check-in greeting", type: .info)

        // Use the same streaming method but with a "start check-in" prompt
        return try await streamCheckInChat(
            message: "Let's start my weekly check-in.",
            summary: summary,
            profile: profile,
            conversationHistory: [],
            onTextChunk: onTextChunk
        )
    }
}
