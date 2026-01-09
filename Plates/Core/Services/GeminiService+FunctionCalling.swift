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

    // MARK: - Function Calling Chat

    /// Chat using Gemini function calling for tool use
    func chatWithFunctions(
        message: String,
        imageData: Data?,
        context: ChatFunctionContext,
        conversationHistory: [ChatMessage],
        modelContext: ModelContext,
        onTextChunk: ((String) -> Void)? = nil,
        onFunctionCall: ((String) -> Void)? = nil
    ) async throws -> ChatFunctionResult {
        isLoading = true
        defer { isLoading = false }

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
            onTextChunk: onTextChunk,
            onFunctionCall: onFunctionCall
        )
    }

    // MARK: - Response Parser

    private func parseStreamingFunctionResponse(
        bytes: URLSession.AsyncBytes,
        startTime: Date,
        context: ChatFunctionContext,
        modelContext: ModelContext,
        contents: [[String: Any]],
        onTextChunk: ((String) -> Void)?,
        onFunctionCall: ((String) -> Void)?
    ) async throws -> ChatFunctionResult {
        var functionsCalled: [String] = []
        var textResponse = ""
        var suggestedFood: SuggestedFoodEntry?
        var planUpdate: GeminiFunctionExecutor.PlanUpdateSuggestion?
        var suggestedFoodEdit: SuggestedFoodEdit?
        var suggestedWorkout: SuggestedWorkoutEntry?
        var suggestedWorkoutLog: SuggestedWorkoutLog?
        var savedMemories: [String] = []
        var accumulatedParts: [[String: Any]] = []

        let executor = GeminiFunctionExecutor(
            modelContext: modelContext,
            userProfile: context.profile,
            isIncognitoMode: context.isIncognitoMode
        )

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

                if let text = part["text"] as? String {
                    textResponse += text
                    onTextChunk?(textResponse)
                }

                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String {
                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    let argsPreview = args.keys.joined(separator: ", ")
                    log("🔧 \(functionName)(\(argsPreview))", type: .info)
                    functionsCalled.append(functionName)
                    onFunctionCall?(functionName)
                    pendingFunctionCalls.append((name: functionName, args: args))
                }
            }
        }

        // Process all collected function calls
        if !pendingFunctionCalls.isEmpty {
            for (functionName, args) in pendingFunctionCalls {
                let call = GeminiFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                let result = executor.execute(call)

                if functionName == "save_memory", let content = args["content"] as? String {
                    savedMemories.append(content)
                    log("🧠 Saved: \(content.prefix(50))...", type: .info)
                }

                switch result {
                case .suggestedFood(let food):
                    suggestedFood = food
                    log("🍽️ Suggest: \(food.name) (\(food.calories) kcal)", type: .info)

                case .suggestedPlanUpdate(let update):
                    planUpdate = update
                    log("📊 Plan update suggested", type: .info)

                case .suggestedFoodEdit(let edit):
                    suggestedFoodEdit = edit
                    log("✏️ Edit: \(edit.name) - \(edit.changes.count) changes", type: .info)

                case .dataResponse(let functionResult):
                    pendingFunctionResults.append(functionResult)
                    log("📊 Data: \(functionResult.name)", type: .debug)

                case .suggestedWorkout(let suggestion):
                    // Workout suggestions are shown in WorkoutsView, not chat (for now)
                    log("💪 Workout suggested: \(suggestion.name)", type: .info)

                case .suggestedWorkoutStart(let workout):
                    // Workout start suggestion - needs user approval
                    suggestedWorkout = workout
                    log("🏋️ Workout suggestion: \(workout.name) (\(workout.exercises.count) exercises)", type: .info)

                case .suggestedWorkoutLog(let workoutLog):
                    // Workout log suggestion - needs user approval
                    suggestedWorkoutLog = workoutLog
                    log("📝 Workout log suggestion: \(workoutLog.displayName) (\(workoutLog.exercises.count) exercises)", type: .info)

                case .startedLiveWorkout(let workout):
                    // Legacy: Workout started directly (shouldn't happen with new flow)
                    log("🏋️ Started workout: \(workout.name)", type: .info)

                case .noAction:
                    break
                }
            }

            // Send all function results back together
            if !pendingFunctionResults.isEmpty {
                log("📤 Sending \(pendingFunctionResults.count) result(s) to model", type: .debug)
                let followUp = try await sendParallelFunctionResults(
                    functionResults: pendingFunctionResults,
                    previousContents: contents,
                    originalParts: accumulatedParts,
                    executor: executor,
                    previousText: textResponse,
                    onTextChunk: onTextChunk
                )
                if !followUp.text.isEmpty {
                    textResponse += followUp.text
                    onTextChunk?(textResponse)
                }
                if let food = followUp.suggestedFood { suggestedFood = food }
                if let plan = followUp.planUpdate { planUpdate = plan }
                if let edit = followUp.suggestedFoodEdit { suggestedFoodEdit = edit }
                savedMemories.append(contentsOf: followUp.savedMemories)
            }
        }

        // Generate conversational responses for suggestions
        if let food = suggestedFood, textResponse.isEmpty {
            let followUp = try await sendFunctionResultForSuggestion(
                name: "suggest_food_log",
                response: [
                    "status": "suggestion_ready",
                    "food_name": food.name,
                    "calories": food.calories,
                    "protein": food.proteinGrams,
                    "instruction": "The user will see a card with this food suggestion. Please write a brief, friendly message acknowledging what they ate. Be conversational and encouraging."
                ],
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        if let plan = planUpdate, textResponse.isEmpty {
            let followUp = try await sendFunctionResultForSuggestion(
                name: "update_user_plan",
                response: [
                    "status": "suggestion_ready",
                    "calories": plan.calories as Any,
                    "protein": plan.proteinGrams as Any,
                    "carbs": plan.carbsGrams as Any,
                    "fat": plan.fatGrams as Any,
                    "instruction": "The user will see a card with these plan changes. Please write a brief message explaining why you're suggesting these adjustments. Be conversational and explain your reasoning."
                ],
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        if let edit = suggestedFoodEdit, textResponse.isEmpty {
            let changesDescription = edit.changes.map { "\($0.field): \($0.oldValue) → \($0.newValue)" }.joined(separator: ", ")
            let followUp = try await sendFunctionResultForSuggestion(
                name: "edit_food_entry",
                response: [
                    "status": "suggestion_ready",
                    "entry_name": edit.name,
                    "changes": changesDescription,
                    "instruction": "The user will see a card with these proposed changes. Please write a brief, friendly message explaining what you're suggesting to update and why. Be conversational."
                ],
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        if let workout = suggestedWorkout, textResponse.isEmpty {
            let exerciseNames = workout.exercises.prefix(3).map { $0.name }.joined(separator: ", ")
            let followUp = try await sendFunctionResultForSuggestion(
                name: "start_live_workout",
                response: [
                    "status": "suggestion_ready",
                    "workout_name": workout.name,
                    "workout_type": workout.workoutType,
                    "exercise_count": workout.exercises.count,
                    "exercises_preview": exerciseNames,
                    "duration_minutes": workout.durationMinutes,
                    "instruction": "The user will see a card with this workout suggestion. Please write a brief, encouraging message about the workout you're suggesting. Mention why this workout is good for them based on their goals/recovery. Be conversational and motivating."
                ],
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        if let workoutLog = suggestedWorkoutLog, textResponse.isEmpty {
            let exercisesSummary = workoutLog.exercises.isEmpty ? "general workout" : workoutLog.exercises.map { $0.name }.joined(separator: ", ")
            let followUp = try await sendFunctionResultForSuggestion(
                name: "log_workout",
                response: [
                    "status": "suggestion_ready",
                    "workout_type": workoutLog.workoutType,
                    "exercise_count": workoutLog.exercises.count,
                    "exercises": exercisesSummary,
                    "duration_minutes": workoutLog.durationMinutes as Any,
                    "instruction": "The user will see a card to confirm logging this workout. Please write a brief, encouraging message acknowledging their workout. Congratulate them on completing it and be motivating. Be conversational."
                ],
                previousContents: contents,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        log("✅ Complete: \(textResponse.count) chars, functions: \(functionsCalled.joined(separator: ", "))", type: .info)

        return ChatFunctionResult(
            message: textResponse,
            suggestedFood: suggestedFood,
            planUpdate: planUpdate,
            suggestedFoodEdit: suggestedFoodEdit,
            suggestedWorkout: suggestedWorkout,
            suggestedWorkoutLog: suggestedWorkoutLog,
            functionsCalled: functionsCalled,
            savedMemories: savedMemories
        )
    }
}
