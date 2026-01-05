//
//  GeminiService+FunctionCalling.swift
//  Plates
//
//  Gemini function calling for tool use
//

import Foundation
import SwiftData
import os

extension GeminiService {

    // MARK: - Types

    /// Context for function calling chat
    struct ChatFunctionContext: Sendable {
        let profile: UserProfile?
        let todaysFoodEntries: [FoodEntry]
        let currentDateTime: String
        let conversationHistory: String
        let memoriesContext: String  // Formatted memories for system prompt
    }

    /// Result from function calling chat
    struct ChatFunctionResult: Sendable {
        let message: String
        let suggestedFood: SuggestedFoodEntry?
        let planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        let functionsCalled: [String]
        let savedMemories: [String]  // Memory contents that were saved during this response
    }

    // MARK: - Function Calling Chat

    /// Chat using Gemini function calling for tool use
    func chatWithFunctions(
        message: String,
        imageData: Data?,
        context: ChatFunctionContext,
        conversationHistory: [ChatMessage],
        modelContext: ModelContext,
        onTextChunk: ((String) -> Void)? = nil
    ) async throws -> ChatFunctionResult {
        isLoading = true
        defer { isLoading = false }

        log("🔧 Starting function calling chat", type: .info)

        let systemPrompt = buildFunctionCallingSystemPrompt(context: context)
        var contents: [[String: Any]] = []

        // Add system prompt
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": "Hey! What's going on?"]]
        ])

        // Add conversation history
        for msg in conversationHistory.suffix(10) {
            let parts: [[String: Any]] = [["text": msg.content]]
            contents.append([
                "role": msg.isFromUser ? "user" : "model",
                "parts": parts
            ])
        }

        // Build user message with optional image
        var userParts: [[String: Any]] = []
        if let imageData {
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
            log("📸 Image attached to message", type: .info)
        }
        userParts.append(["text": message.isEmpty ? "What is this?" : message])

        contents.append([
            "role": "user",
            "parts": userParts
        ])

        // Build request with function declarations
        var config = buildGenerationConfig(thinkingLevel: .medium, maxTokens: 2048)
        if imageData != nil {
            config["mediaResolution"] = "MEDIA_RESOLUTION_HIGH"
        }

        let requestBody: [String: Any] = [
            "contents": contents,
            "tools": [["function_declarations": GeminiFunctionDeclarations.chatFunctions]],
            "generationConfig": config
        ]

        // Use streaming API
        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(Secrets.geminiAPIKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            log("❌ API Error: status \(httpResponse.statusCode)", type: .error)
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: "Streaming request failed")
        }

        return try await parseStreamingFunctionResponse(
            bytes: bytes,
            startTime: startTime,
            context: context,
            modelContext: modelContext,
            contents: contents,
            onTextChunk: onTextChunk
        )
    }

    // MARK: - Private Helpers

    private func buildFunctionCallingSystemPrompt(context: ChatFunctionContext) -> String {
        var prompt = """
        You are Trai, a friendly and knowledgeable fitness coach. You're casual, encouraging, and genuinely care about helping people reach their goals. You speak like a supportive friend who happens to be a nutrition and fitness expert.

        Personality traits:
        - Warm and encouraging, but not over-the-top
        - Speak naturally, like texting a friend (use contractions, casual language)
        - Celebrate wins, no matter how small
        - Give straight talk when needed - you're honest but kind
        - Curious about their day and how they're feeling

        Never refer to yourself as an AI, Gemini, or an assistant. You're just Trai, their coach.

        You have access to tools for:
        - Logging food the user has eaten (suggest_food_log)
        - Checking today's food log and nutrition progress (get_todays_food_log)
        - Viewing and updating the user's nutrition plan (get_user_plan, update_user_plan)
        - Checking workout history (get_recent_workouts)
        - Logging workouts (log_workout)
        - Remembering facts about the user (save_memory, delete_memory)

        Current date/time: \(context.currentDateTime)

        """

        if let profile = context.profile {
            // Add personalization info
            var userInfo: [String] = []
            if !profile.name.isEmpty {
                userInfo.append("Name: \(profile.name)")
            }
            if let age = profile.age {
                userInfo.append("Age: \(age)")
            }
            if let weight = profile.currentWeightKg {
                let weightStr = profile.usesMetricWeight
                    ? "\(Int(weight)) kg"
                    : "\(Int(weight * 2.205)) lbs"
                userInfo.append("Current weight: \(weightStr)")
            }

            if !userInfo.isEmpty {
                prompt += """
                USER INFO:
                \(userInfo.joined(separator: ", "))

                """
            }

            prompt += """
            User's Goal: \(profile.goal.displayName)
            Daily Targets: \(profile.dailyCalorieGoal) kcal, \(profile.dailyProteinGoal)g protein, \(profile.dailyCarbsGoal)g carbs, \(profile.dailyFatGoal)g fat, \(profile.dailyFiberGoal)g fiber

            """
        }

        // Add memories if available
        if !context.memoriesContext.isEmpty {
            prompt += """

            WHAT YOU KNOW ABOUT THIS USER:
            \(context.memoriesContext)

            Use this knowledge to personalize your responses. For example, don't suggest fish if they don't like it.

            """
        }

        prompt += """

        IMPORTANT GUIDELINES:
        1. Follow the user's current intent. If they switch topics, follow along naturally.
        2. ONLY use suggest_food_log when the user EXPLICITLY says they ate/had/consumed something (e.g., "I just had an apple", "I ate a sandwich", "Had coffee this morning").
           - Do NOT suggest logging for questions about food ("is this healthy?", "what about bananas?")
           - Do NOT suggest logging when discussing food hypothetically
           - Do NOT suggest logging in follow-up responses unless the user mentions eating something new
        3. When asked about progress or what they've eaten, use get_todays_food_log.
        4. Be conversational and concise. Answer questions directly.
        5. For food photos, analyze and use suggest_food_log with nutritional estimates.
        6. Don't say "I've logged this" - you can only suggest, the user confirms.
        7. Include relevant emojis for food items (☕, 🥗, 🍳, etc.)
        8. When using update_user_plan to suggest plan changes, ALWAYS include a conversational message explaining WHY you're suggesting the changes. Never just return the plan update without context - the user needs to understand your reasoning before seeing the suggestion card.

        MEMORY USAGE:
        - Use save_memory to remember important facts about the user that will help you be a better coach.
        - Save preferences ("doesn't like fish", "prefers morning workouts"), restrictions ("allergic to nuts", "knee injury"), habits ("usually skips breakfast"), goals ("training for marathon"), and context ("works night shifts").
        - Be proactive about saving memories - if the user mentions something that would help future conversations, save it.
        - Use delete_memory when the user indicates something has changed (e.g., "I actually like fish now").
        - Don't save trivial or one-time information - focus on persistent facts and preferences.
        - You can call save_memory in parallel with other function calls when appropriate.
        """

        return prompt
    }

    private func parseStreamingFunctionResponse(
        bytes: URLSession.AsyncBytes,
        startTime: Date,
        context: ChatFunctionContext,
        modelContext: ModelContext,
        contents: [[String: Any]],
        onTextChunk: ((String) -> Void)?
    ) async throws -> ChatFunctionResult {
        var functionsCalled: [String] = []
        var textResponse = ""
        var suggestedFood: SuggestedFoodEntry?
        var planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []

        let executor = GeminiFunctionExecutor(modelContext: modelContext, userProfile: context.profile)

        // Collect all function calls for parallel processing
        var pendingFunctionCalls: [(name: String, args: [String: Any])] = []
        var pendingFunctionResults: [GeminiFunctionExecutor.FunctionResult] = []

        // Parse streaming response - collect ALL function calls first
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            for part in parts {
                accumulatedParts.append(part)

                // Handle text chunks - stream them immediately
                if let text = part["text"] as? String {
                    textResponse += text
                    onTextChunk?(textResponse)
                }

                // Collect function calls (don't process yet)
                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String {
                    let elapsed = Date().timeIntervalSince(startTime)
                    log("⏱️ Function call received in \(String(format: "%.2f", elapsed))s", type: .info)
                    log("🔧 Function called: \(functionName)", type: .info)
                    functionsCalled.append(functionName)

                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    pendingFunctionCalls.append((name: functionName, args: args))
                }
            }
        }

        // Now process all collected function calls
        if !pendingFunctionCalls.isEmpty {
            log("📦 Processing \(pendingFunctionCalls.count) function call(s) in parallel", type: .info)

            for (functionName, args) in pendingFunctionCalls {
                let call = GeminiFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                let result = executor.execute(call)

                // Capture saved memory content
                if functionName == "save_memory", let content = args["content"] as? String {
                    savedMemories.append(content)
                    log("🧠 Memory saved: \(content)", type: .info)
                }

                switch result {
                case .suggestedFood(let food):
                    suggestedFood = food
                    log("🍽️ Food suggestion: \(food.name) - \(food.calories) kcal", type: .info)

                case .suggestedPlanUpdate(let update):
                    planUpdate = update
                    log("📊 Plan update suggested", type: .info)

                case .dataResponse(let functionResult):
                    pendingFunctionResults.append(functionResult)

                case .noAction:
                    break
                }
            }

            // Send all function results back together
            if !pendingFunctionResults.isEmpty {
                log("📤 Sending \(pendingFunctionResults.count) function result(s) back to Gemini", type: .info)
                let followUp = try await sendParallelFunctionResults(
                    functionResults: pendingFunctionResults,
                    previousContents: contents,
                    originalParts: accumulatedParts,
                    executor: executor,
                    onTextChunk: onTextChunk
                )
                // Only update text if follow-up has content (don't lose streamed text)
                if !followUp.text.isEmpty {
                    textResponse = followUp.text
                }
                // Capture any suggestions from chained function calls
                if let food = followUp.suggestedFood {
                    suggestedFood = food
                }
                if let plan = followUp.planUpdate {
                    planUpdate = plan
                }
                savedMemories.append(contentsOf: followUp.savedMemories)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log("⏱️ Streaming complete in \(String(format: "%.2f", elapsed))s", type: .info)

        // If we got a food suggestion, send result back for conversational response
        if let food = suggestedFood, textResponse.isEmpty {
            let foodResult = GeminiFunctionExecutor.FunctionResult(
                name: "suggest_food_log",
                response: [
                    "status": "suggestion_shown",
                    "food_name": food.name,
                    "calories": food.calories,
                    "protein": food.proteinGrams,
                    "note": "User will see a card to confirm or edit this suggestion"
                ]
            )
            let followUp = try await sendFunctionResult(
                functionResult: foodResult,
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor,
                onTextChunk: onTextChunk
            )
            textResponse = followUp.text
        }

        // If we got a plan update suggestion, send result back for conversational response
        if let plan = planUpdate, textResponse.isEmpty {
            let planResult = GeminiFunctionExecutor.FunctionResult(
                name: "update_user_plan",
                response: [
                    "status": "suggestion_shown",
                    "calories": plan.calories as Any,
                    "protein": plan.proteinGrams as Any,
                    "carbs": plan.carbsGrams as Any,
                    "fat": plan.fatGrams as Any,
                    "note": "User will see a card to review and confirm these plan changes"
                ]
            )
            let followUp = try await sendFunctionResult(
                functionResult: planResult,
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor,
                onTextChunk: onTextChunk
            )
            textResponse = followUp.text
        }

        return ChatFunctionResult(
            message: textResponse,
            suggestedFood: suggestedFood,
            planUpdate: planUpdate,
            functionsCalled: functionsCalled,
            savedMemories: savedMemories
        )
    }

    /// Result from sending a function result back to Gemini
    private struct FunctionFollowUpResult {
        var text: String = ""
        var suggestedFood: SuggestedFoodEntry?
        var planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []
    }

    /// Send multiple function results back in parallel
    private func sendParallelFunctionResults(
        functionResults: [GeminiFunctionExecutor.FunctionResult],
        previousContents: [[String: Any]],
        originalParts: [[String: Any]],
        executor: GeminiFunctionExecutor,
        onTextChunk: ((String) -> Void)?
    ) async throws -> FunctionFollowUpResult {
        var contents = previousContents
        var result = FunctionFollowUpResult()

        // Add model's function call parts
        contents.append([
            "role": "model",
            "parts": originalParts
        ])

        // Build all function responses in one parts array
        var responseParts: [[String: Any]] = []
        for funcResult in functionResults {
            responseParts.append([
                "functionResponse": [
                    "name": funcResult.name,
                    "response": funcResult.response
                ]
            ])
        }

        // Send all function responses together
        contents.append([
            "role": "user",
            "parts": responseParts
        ])

        let requestBody: [String: Any] = [
            "contents": contents,
            "tools": [["function_declarations": GeminiFunctionDeclarations.chatFunctions]],
            "generationConfig": buildGenerationConfig(thinkingLevel: .low, maxTokens: 1024)
        ]

        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(Secrets.geminiAPIKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            log("❌ Parallel function response request failed", type: .error)
            return result
        }

        // Collect any additional function calls from the response
        var additionalFunctionResults: [GeminiFunctionExecutor.FunctionResult] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first else {
                continue
            }

            if let finishReason = firstCandidate["finishReason"] as? String {
                log("📋 Finish reason: \(finishReason)", type: .debug)
            }

            guard let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            for part in parts {
                result.accumulatedParts.append(part)

                // Handle text
                if let text = part["text"] as? String {
                    result.text += text
                    log("📨 Follow-up text chunk: +\(text.count) chars", type: .debug)
                    onTextChunk?(result.text)
                }

                // Handle any chained function calls
                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String {
                    log("🔧 Chained function called: \(functionName)", type: .info)

                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    let call = GeminiFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                    let execResult = executor.execute(call)

                    // Capture saved memory content
                    if functionName == "save_memory", let content = args["content"] as? String {
                        result.savedMemories.append(content)
                        log("🧠 Memory saved in follow-up: \(content)", type: .info)
                    }

                    switch execResult {
                    case .suggestedFood(let food):
                        result.suggestedFood = food
                        log("🍽️ Food suggestion from follow-up: \(food.name)", type: .info)

                    case .suggestedPlanUpdate(let update):
                        result.planUpdate = update
                        log("📊 Plan update from follow-up", type: .info)

                    case .dataResponse(let nextFuncResult):
                        additionalFunctionResults.append(nextFuncResult)

                    case .noAction:
                        break
                    }
                }
            }
        }

        // If there are additional chained function calls, recurse
        if !additionalFunctionResults.isEmpty {
            log("📤 Sending \(additionalFunctionResults.count) chained function result(s)", type: .info)
            let chainedResult = try await sendParallelFunctionResults(
                functionResults: additionalFunctionResults,
                previousContents: contents,
                originalParts: result.accumulatedParts,
                executor: executor,
                onTextChunk: onTextChunk
            )
            if !chainedResult.text.isEmpty {
                result.text = chainedResult.text
            }
            if let food = chainedResult.suggestedFood {
                result.suggestedFood = food
            }
            if let plan = chainedResult.planUpdate {
                result.planUpdate = plan
            }
            result.savedMemories.append(contentsOf: chainedResult.savedMemories)
        }

        log("📤 Parallel follow-up complete. Text length: \(result.text.count)", type: .debug)
        return result
    }

    private func sendFunctionResult(
        functionResult: GeminiFunctionExecutor.FunctionResult,
        previousContents: [[String: Any]],
        originalParts: [[String: Any]],
        executor: GeminiFunctionExecutor,
        onTextChunk: ((String) -> Void)?
    ) async throws -> FunctionFollowUpResult {
        var contents = previousContents
        var currentParts = originalParts
        var result = FunctionFollowUpResult()
        var pendingFunctionResult: GeminiFunctionExecutor.FunctionResult? = functionResult

        // Loop to handle multi-turn function calling (max 5 iterations for safety)
        for iteration in 0..<5 {
            guard let funcResult = pendingFunctionResult else { break }
            pendingFunctionResult = nil

            contents.append([
                "role": "model",
                "parts": currentParts
            ])

            // Send function response back - response should be a direct object, not stringified
            contents.append([
                "role": "user",
                "parts": [[
                    "functionResponse": [
                        "name": funcResult.name,
                        "response": funcResult.response
                    ]
                ]]
            ])

            let requestBody: [String: Any] = [
                "contents": contents,
                "tools": [["function_declarations": GeminiFunctionDeclarations.chatFunctions]],
                "generationConfig": buildGenerationConfig(thinkingLevel: .low, maxTokens: 1024)
            ]

            let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(Secrets.geminiAPIKey)")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                log("❌ Follow-up streaming request failed (iteration \(iteration))", type: .error)
                break
            }

            currentParts = []
            var receivedAnyContent = false

            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first else {
                    continue
                }

                // Check for finish reason without content (happens when Gemini ends without text)
                if let finishReason = firstCandidate["finishReason"] as? String {
                    log("📋 Finish reason: \(finishReason)", type: .debug)
                }

                guard let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    continue
                }

                receivedAnyContent = true

                for part in parts {
                    currentParts.append(part)

                    // Handle text
                    if let text = part["text"] as? String {
                        result.text += text
                        log("📨 Follow-up text chunk: +\(text.count) chars", type: .debug)
                        onTextChunk?(result.text)
                    }

                    // Handle function calls
                    if let functionCall = part["functionCall"] as? [String: Any],
                       let functionName = functionCall["name"] as? String {
                        log("🔧 Follow-up function called: \(functionName)", type: .info)

                        let args = functionCall["args"] as? [String: Any] ?? [:]
                        let call = GeminiFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                        let execResult = executor.execute(call)

                        // Capture saved memory content
                        if functionName == "save_memory", let content = args["content"] as? String {
                            result.savedMemories.append(content)
                            log("🧠 Memory saved in follow-up: \(content)", type: .info)
                        }

                        switch execResult {
                        case .suggestedFood(let food):
                            result.suggestedFood = food
                            log("🍽️ Food suggestion from follow-up: \(food.name)", type: .info)

                        case .suggestedPlanUpdate(let update):
                            result.planUpdate = update
                            log("📊 Plan update from follow-up", type: .info)

                        case .dataResponse(let nextFuncResult):
                            // Chain to another function call
                            pendingFunctionResult = nextFuncResult
                            log("📤 Chaining to next function call", type: .info)

                        case .noAction:
                            break
                        }
                    }
                }
            }

            result.accumulatedParts = currentParts

            // Log if we received no content in this iteration
            if !receivedAnyContent {
                log("⚠️ No content received in follow-up iteration \(iteration)", type: .info)
            }
        }

        log("📤 Follow-up complete. Text length: \(result.text.count)", type: .debug)
        return result
    }
}
