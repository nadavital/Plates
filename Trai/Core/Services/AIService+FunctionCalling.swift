//
//  AIService+FunctionCalling.swift
//  Trai
//
//  AI function calling for tool use
//

import Foundation
import SwiftData
import os

extension AIService {

    // MARK: - Function Calling Chat

    /// Chat using AI function calling for tool use
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
        let requestTicket = try beginAIRequest(for: .agentCoachChat)

        do {
            let systemPrompt = buildFunctionCallingSystemPrompt(context: context)
            var messages: [TraiAIMessage] = []

            // Add system prompt
            messages.append(
                AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: systemPrompt)
            )
            messages.append(
                AIBackendPayloadBuilder.canonicalTextMessage(role: .assistant, text: context.coachTone.primingReply)
            )

            // Add conversation history
            for msg in conversationHistory.suffix(10) {
                messages.append(
                    AIBackendPayloadBuilder.canonicalTextMessage(
                        role: msg.isFromUser ? .user : .assistant,
                        text: msg.content
                    )
                )
            }

            // Build user message with optional image
            var canonicalUserParts: [TraiAIPart] = []
            if let imageData {
                canonicalUserParts.append(AIBackendPayloadBuilder.imagePart(imageData))
                log("📸 Image attached to message", type: .info)
            }
            let promptText = message.isEmpty ? "What is this?" : message
            canonicalUserParts.append(.text(promptText))

            messages.append(
                AIBackendPayloadBuilder.canonicalMessage(role: .user, parts: canonicalUserParts)
            )

            // Build request with function declarations
            let canonicalTools: [TraiAITool] = AIFunctionDeclarations.chatFunctions.compactMap { declaration in
                guard let name = declaration["name"] as? String else { return nil }
                return AIBackendPayloadBuilder.canonicalTool(
                    name: name,
                    description: declaration["description"] as? String ?? "",
                    parameters: declaration["parameters"] as? [String: Any] ?? [:]
                )
            }

            let canonicalRequest = AIBackendPayloadBuilder.canonicalRequest(
                messages: messages,
                tools: canonicalTools,
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .medium,
                    imageResolution: imageData == nil ? nil : .high
                )
            )

            let requestBody = AIBackendPayloadBuilder.requestBody(from: canonicalRequest)

            // Use streaming API
            let url = try serviceURL(action: "streamGenerateContent", streaming: true)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            try await configureRequest(&request)
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let startTime = Date()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                }
                let userError = parseAIProxyError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallbackMessage: "Streaming request failed"
                )
                lastError = userError.localizedDescription
                log("❌ API Error: \(userError.localizedDescription)", type: .error)
                throw userError
            }

            let result = try await parseStreamingFunctionResponse(
                bytes: bytes,
                startTime: startTime,
                userMessage: message,
                context: context,
                modelContext: modelContext,
                messages: messages,
                onTextChunk: onTextChunk,
                onFunctionCall: onFunctionCall
            )
            completeAIRequest(requestTicket)
            return result
        } catch {
            cancelAIRequest(requestTicket)
            throw error
        }
    }

    // MARK: - Response Parser

    private func parseStreamingFunctionResponse(
        bytes: URLSession.AsyncBytes,
        startTime: Date,
        userMessage: String,
        context: ChatFunctionContext,
        modelContext: ModelContext,
        messages: [TraiAIMessage],
        onTextChunk: ((String) -> Void)?,
        onFunctionCall: ((String) -> Void)?
    ) async throws -> ChatFunctionResult {
        var functionsCalled: [String] = []
        var textResponse = ""
        var suggestedFoods: [SuggestedFoodEntry] = []
        var planUpdate: PlanUpdateSuggestion?
        var suggestedFoodEdit: SuggestedFoodEdit?
        var suggestedWorkout: SuggestedWorkoutEntry?
        var suggestedWorkoutLog: SuggestedWorkoutLog?
        var suggestedReminder: SuggestedReminder?
        var savedMemories: [String] = []
        var accumulatedParts: [TraiAIPart] = []

        let executor = AIFunctionExecutor(
            modelContext: modelContext,
            userProfile: context.profile,
            isIncognitoMode: context.isIncognitoMode,
            activityData: context.activityData
        )

        var pendingFunctionCalls: [(name: String, args: [String: Any])] = []
        var pendingFunctionResults: [AIFunctionExecutor.FunctionResult] = []

        // Parse streaming response - collect ALL function calls first
        for try await line in bytes.lines {
            // Check for task cancellation
            try Task.checkCancellation()

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
                if let text = part["text"] as? String {
                    accumulatedParts.append(.text(text))
                    textResponse += text
                    onTextChunk?(textResponse)
                }

                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String {
                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    accumulatedParts.append(
                        AIBackendPayloadBuilder.toolCallPart(
                            id: functionCall["id"] as? String,
                            name: functionName,
                            arguments: args
                        )
                    )
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
                let call = AIFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                let result = executor.execute(call)

                if functionName == "save_memory", let content = args["content"] as? String {
                    savedMemories.append(content)
                    log("🧠 Saved: \(content.prefix(50))...", type: .info)
                }

                switch result {
                case .suggestedFood(let food):
                    suggestedFoods.append(food)
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

                case .suggestedReminder(let reminder):
                    suggestedReminder = reminder
                    log("⏰ Reminder suggestion: \(reminder.title) at \(reminder.hour):\(String(format: "%02d", reminder.minute))", type: .info)

                case .noAction:
                    break
                }
            }

            // Send all function results back together
            if !pendingFunctionResults.isEmpty {
                log("📤 Sending \(pendingFunctionResults.count) result(s) to model", type: .debug)
                let followUp = try await sendParallelFunctionResults(
                    functionResults: pendingFunctionResults,
                    previousMessages: messages,
                    originalParts: accumulatedParts,
                    executor: executor,
                    previousText: textResponse,
                    onTextChunk: onTextChunk
                )
                if !followUp.text.isEmpty {
                    textResponse += followUp.text
                    onTextChunk?(textResponse)
                }
                suggestedFoods.append(contentsOf: followUp.suggestedFoods)
                if let plan = followUp.planUpdate { planUpdate = plan }
                if let edit = followUp.suggestedFoodEdit { suggestedFoodEdit = edit }
                if let reminder = followUp.suggestedReminder { suggestedReminder = reminder }
                savedMemories.append(contentsOf: followUp.savedMemories)
            }
        }

        // Generate conversational responses for suggestions
        let toneInstruction = context.coachTone.followUpInstructionSuffix

        if !suggestedFoods.isEmpty, textResponse.isEmpty {
            let foodNames = suggestedFoods.map { $0.name }.joined(separator: ", ")
            let totalCalories = suggestedFoods.reduce(0) { $0 + $1.calories }
            let followUp = try await sendFunctionResultForSuggestion(
                name: "suggest_food_log",
                response: [
                    "status": "suggestion_ready",
                    "food_names": foodNames,
                    "food_count": suggestedFoods.count,
                    "total_calories": totalCalories,
                    "instruction": suggestedFoods.count > 1
                        ? "The user will see cards with \(suggestedFoods.count) food suggestions. Please write a brief, friendly message acknowledging what they ate. \(toneInstruction)"
                        : "The user will see a card with this food suggestion. Please write a brief, friendly message acknowledging what they ate. \(toneInstruction)"
                ],
                previousMessages: messages,
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
                    "instruction": "The user will see a card with these plan changes. Please write a brief message explaining why you're suggesting these adjustments. \(toneInstruction)"
                ],
                previousMessages: messages,
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
                    "instruction": "The user will see a card with these proposed changes. Please write a brief, friendly message explaining what you're suggesting to update and why. \(toneInstruction)"
                ],
                previousMessages: messages,
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
                    "instruction": "The user will see a card with this workout suggestion. Please write a brief message about why this workout fits their goals/recovery. \(toneInstruction)"
                ],
                previousMessages: messages,
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
                    "instruction": "The user will see a card to confirm logging this workout. Please write a brief acknowledgement of their effort. \(toneInstruction)"
                ],
                previousMessages: messages,
                originalParts: accumulatedParts,
                executor: executor
            )
            textResponse = followUp.text
            onTextChunk?(textResponse)
        }

        // Fallback: If functions were called but no text was generated, ask the model to summarize
        if textResponse.isEmpty && !functionsCalled.isEmpty {
            let dataFunctions = ["get_user_plan", "get_food_log", "get_todays_food_log", "get_recent_workouts",
                                 "get_muscle_recovery_status", "get_weight_history", "log_weight", "get_activity_summary"]
            let calledDataFunctions = functionsCalled.filter { dataFunctions.contains($0) }

            if !calledDataFunctions.isEmpty {
                log("⚠️ No text generated after data functions, requesting summary", type: .info)
                let followUp = try await sendFunctionResultForSuggestion(
                    name: calledDataFunctions.first!,
                    response: [
                    "status": "data_retrieved",
                    "instruction": "The data has been retrieved. Please summarize the information for the user and answer their original question based on the data. \(toneInstruction)"
                ],
                    previousMessages: messages,
                    originalParts: accumulatedParts,
                    executor: executor
                )
                if !followUp.text.isEmpty {
                    textResponse = followUp.text
                    onTextChunk?(textResponse)
                }
            }
        }

        // Quick fallback: if the model returned nothing and the user clearly provided a weight,
        // execute log_weight directly to avoid silent failures.
        if textResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !functionsCalled.contains("log_weight"),
           let quickLogArgs = quickWeightLogArgs(from: userMessage, profile: context.profile) {
            onFunctionCall?("log_weight")
            functionsCalled.append("log_weight")
            let call = AIFunctionExecutor.FunctionCall(name: "log_weight", arguments: quickLogArgs)
            if case .dataResponse(let functionResult) = executor.execute(call) {
                pendingFunctionResults.append(functionResult)
            }
        }

        // Final safety fallback: confirm successful weight logs even if model follow-up text is empty.
        if textResponse.isEmpty,
           functionsCalled.contains("log_weight"),
           let weightResult = pendingFunctionResults.last(where: { $0.name == "log_weight" }),
           let success = weightResult.response["success"] as? Bool,
           success {
            let date = (weightResult.response["date"] as? String) ?? "today"
            if let lbs = weightResult.response["weight_lbs"] as? Double {
                textResponse = "Logged \(Int(lbs.rounded())) lbs for \(date)."
            } else if let kg = weightResult.response["weight_kg"] as? Double {
                textResponse = "Logged \(String(format: "%.1f", kg)) kg for \(date)."
            } else {
                textResponse = "Logged your weight for \(date)."
            }
            onTextChunk?(textResponse)
        }

        // If weight logging failed and model produced no follow-up, surface the error explicitly.
        if textResponse.isEmpty,
           functionsCalled.contains("log_weight"),
           let weightResult = pendingFunctionResults.last(where: { $0.name == "log_weight" }),
           let error = weightResult.response["error"] as? String,
           !error.isEmpty {
            textResponse = "I couldn't log your weight: \(error)"
            onTextChunk?(textResponse)
        }

        log("✅ Complete: \(textResponse.count) chars, functions: \(functionsCalled.joined(separator: ", "))", type: .info)

        return ChatFunctionResult(
            message: textResponse,
            suggestedFoods: suggestedFoods,
            planUpdate: planUpdate,
            suggestedFoodEdit: suggestedFoodEdit,
            suggestedWorkout: suggestedWorkout,
            suggestedWorkoutLog: suggestedWorkoutLog,
            suggestedReminder: suggestedReminder,
            functionsCalled: functionsCalled,
            savedMemories: savedMemories
        )
    }

    private func quickWeightLogArgs(from message: String, profile: UserProfile?) -> [String: Any]? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard !lower.contains("?") else { return nil }
        guard lower.contains("weight") || lower.contains("weigh") || lower.contains("lb") || lower.contains("kg") else {
            return nil
        }
        guard !lower.contains("lost"), !lower.contains("gain"), !lower.contains("history"), !lower.contains("trend") else {
            return nil
        }

        let unitFromProfile = (profile?.usesMetricWeight ?? true) ? "kg" : "lbs"
        var inferredUnit: String = unitFromProfile
        var parsedWeight: Double?

        if let unitMatch = firstRegexMatch(
            pattern: #"([-+]?\d+(?:[.,]\d+)?)\s*(kg|kgs|kilogram|kilograms|lb|lbs|pound|pounds)"#,
            in: lower
        ) {
            let valueString = unitMatch.0.replacingOccurrences(of: ",", with: ".")
            parsedWeight = Double(valueString)
            let unitToken = unitMatch.1
            inferredUnit = unitToken.contains("kg") || unitToken.contains("kilo") ? "kg" : "lbs"
        } else if let value = firstReasonableWeightNumber(in: lower) {
            parsedWeight = value
            if lower.contains("kg") || lower.contains("kilo") {
                inferredUnit = "kg"
            } else if lower.contains("lb") || lower.contains("pound") {
                inferredUnit = "lbs"
            }
        }

        guard let parsedWeight, parsedWeight > 0 else { return nil }
        return [
            "weight": parsedWeight,
            "unit": inferredUnit
        ]
    }

    private func firstReasonableWeightNumber(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?"#) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let valueString = text[range].replacingOccurrences(of: ",", with: ".")
            guard let value = Double(valueString) else { continue }
            if value >= 30, value <= 400 {
                return value
            }
        }
        return nil
    }

    private func firstRegexMatch(pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return (String(text[valueRange]), String(text[unitRange]))
    }
}
