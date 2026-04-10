//
//  AIService+Memory.swift
//  Trai
//
//  Memory parsing - uses AI to extract categorized memories from user notes
//

import Foundation
import os

extension AIService {

    /// Parsed memory from user notes
    struct ParsedMemory: Codable {
        let content: String
        let category: String  // preference, restriction, habit, goal, context, feedback
        let topic: String     // food, workout, schedule, general
        let importance: Int   // 1-5

        func toCoachMemory(source: String) -> CoachMemory {
            CoachMemory(
                content: content,
                category: MemoryCategory(rawValue: category) ?? .context,
                topic: MemoryTopic(rawValue: topic) ?? .general,
                source: source,
                importance: importance
            )
        }
    }

    /// Parse user notes into categorized memories using AI
    /// - Parameters:
    ///   - notes: The user's freeform notes (e.g., activity notes, goal notes)
    ///   - context: Additional context about where the notes came from
    /// - Returns: Array of parsed memories
    func parseNotesIntoMemories(notes: String, context: String = "onboarding") async throws -> [ParsedMemory] {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else { return [] }
        let requestTicket = try beginAIRequest(for: .memoryExtraction)

        log("Parsing notes into memories: \"\(trimmedNotes.prefix(100))...\"", type: .info)

        let systemPrompt = """
        You are an AI assistant that extracts distinct facts and preferences from user notes.
        Parse the user's notes into separate, categorized memories.

        Each memory should be:
        - A single, clear fact or preference
        - Properly categorized by type and topic
        - Assigned an importance score (1-5, where 5 is critical like allergies)

        Categories:
        - preference: Things the user likes or prefers (e.g., "Prefers morning workouts")
        - restriction: Things the user can't or won't do (e.g., "Allergic to peanuts", "Can't do squats due to knee injury")
        - habit: Regular behaviors (e.g., "Usually skips breakfast", "Works out 3x/week")
        - goal: Specific goals (e.g., "Training for a marathon", "Wants to lose 20 lbs")
        - context: Background information (e.g., "Works night shifts", "Has a home gym")
        - feedback: User feedback on plans/suggestions (e.g., "Found portions too large")

        Topics:
        - food: Anything related to eating, nutrition, diet
        - workout: Anything related to exercise, training, fitness
        - schedule: Anything related to timing, availability, routine
        - general: Everything else

        Guidelines:
        - Split compound statements into separate memories
        - Be concise but preserve important details
        - Allergies and medical restrictions are importance 5
        - Strong preferences are importance 4
        - General context is importance 3
        - Minor preferences are importance 2
        """

        let userPrompt = """
        Parse these notes into separate memories:

        "\(trimmedNotes)"

        Context: These notes are from \(context).
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "memories": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "content": [
                                "type": "string",
                                "description": "The memory content - a single clear fact or preference"
                            ],
                            "category": [
                                "type": "string",
                                "enum": ["preference", "restriction", "habit", "goal", "context", "feedback"]
                            ],
                            "topic": [
                                "type": "string",
                                "enum": ["food", "workout", "schedule", "general"]
                            ],
                            "importance": [
                                "type": "integer",
                                "description": "Importance from 1 (minor) to 5 (critical)"
                            ]
                        ],
                        "required": ["content", "category", "topic", "importance"]
                    ]
                ]
            ],
            "required": ["memories"]
        ]

        let request = AIBackendPayloadBuilder.canonicalRequest(
            system: systemPrompt,
            messages: [
                AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: userPrompt)
            ],
            output: AIBackendPayloadBuilder.canonicalOutput(
                kind: .jsonSchema,
                schema: schema
            ),
            generation: AIBackendPayloadBuilder.canonicalGeneration(
                reasoningLevel: .low,
                maxTokens: 2048
            )
        )

        do {
            let response = try await makeRequest(request: request)
            logResponse(response)

            guard let data = response.data(using: String.Encoding.utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let memoriesArray = json["memories"] as? [[String: Any]] else {
                cancelAIRequest(requestTicket)
                log("Failed to parse memories response", type: .error)
                return []
            }

            let memories = memoriesArray.compactMap { dict -> ParsedMemory? in
                guard let content = dict["content"] as? String,
                      let category = dict["category"] as? String,
                      let topic = dict["topic"] as? String,
                      let importance = dict["importance"] as? Int else {
                    return nil
                }
                return ParsedMemory(
                    content: content,
                    category: category,
                    topic: topic,
                    importance: importance
                )
            }

            completeAIRequest(requestTicket)
            log("Parsed \(memories.count) memories from notes", type: .info)
            return memories
        } catch {
            cancelAIRequest(requestTicket)
            throw error
        }
    }
}
