//
//  GeminiService+FunctionCallingHelpers.swift
//  Trai
//
//  Helper methods for Gemini function calling
//

import Foundation
import SwiftData
import os

extension GeminiService {

    // MARK: - System Prompt Builder

    func buildFunctionCallingSystemPrompt(context: ChatFunctionContext) -> String {
        var prompt = """
        You are Trai, a knowledgeable fitness coach. Be helpful, concise, and direct.

        TONE PROFILE:
        - Selected style: \(context.coachTone.rawValue)
        - \(context.coachTone.chatStylePrompt)
        - Natural, conversational tone (use contractions, casual language)
        - Get to the point - don't pad responses with unnecessary pleasantries
        - Skip "How are you?" and "Hope you're doing well" in follow-ups
        - Honest and supportive, not preachy
        - Never refer to yourself as an AI or assistant

        You have access to tools for:
        - Logging food the user has eaten (suggest_food_log)
        - Checking food log and nutrition progress (get_food_log)
        - Viewing and updating the user's nutrition plan (get_user_plan, update_user_plan)
        - Checking workout history (get_recent_workouts)
        - Logging workouts (log_workout)
        - Checking and logging body weight (get_weight_history, log_weight)
        - Remembering facts about the user (save_memory, delete_memory)
        - Managing temporary short-term context (save_short_term_context, clear_short_term_context)

        Current date/time: \(context.currentDateTime)

        """

        if let profile = context.profile {
            prompt += buildUserInfoSection(profile: profile)
        }

        if !context.memoriesContext.isEmpty {
            prompt += buildMemoriesSection(memoriesContext: context.memoriesContext)
        }

        if !context.pulseContext.isEmpty {
            prompt += buildPulseContextSection(pulseContext: context.pulseContext)
        }

        if let pending = context.pendingSuggestion {
            prompt += buildPendingSuggestionSection(pending: pending)
        }

        if let workout = context.activeWorkout {
            prompt += buildActiveWorkoutSection(workout: workout)
        }

        prompt += buildGuidelinesSection()

        return prompt
    }

    private func buildUserInfoSection(profile: UserProfile) -> String {
        var userInfo: [String] = []
        if !profile.name.isEmpty {
            userInfo.append("Name: \(profile.name)")
        }
        if let age = profile.age {
            userInfo.append("Age: \(age)")
        }
        if profile.genderValue != .notSpecified {
            userInfo.append("Gender: \(profile.genderValue.displayName)")
        }
        if let height = profile.heightCm {
            let heightStr = profile.usesMetricHeight
                ? "\(Int(height)) cm"
                : String(format: "%.0f'%.0f\"", floor(height / 2.54 / 12), (height / 2.54).truncatingRemainder(dividingBy: 12))
            userInfo.append("Height: \(heightStr)")
        }
        if let weight = profile.currentWeightKg {
            let weightStr = profile.usesMetricWeight
                ? "\(Int(weight)) kg"
                : "\(Int(weight * 2.205)) lbs"
            userInfo.append("Current weight: \(weightStr)")
        }
        userInfo.append("Activity level: \(profile.activityLevelValue.displayName)")

        var section = ""
        if !userInfo.isEmpty {
            section += """
            USER INFO:
            \(userInfo.joined(separator: ", "))

            """
        }

        section += """
        User's Goal: \(profile.goal.displayName)
        Daily Targets: \(profile.dailyCalorieGoal) kcal, \(profile.dailyProteinGoal)g protein, \(profile.dailyCarbsGoal)g carbs, \(profile.dailyFatGoal)g fat, \(profile.dailyFiberGoal)g fiber

        """

        return section
    }

    private func buildMemoriesSection(memoriesContext: String) -> String {
        """

        WHAT YOU KNOW ABOUT THIS USER:
        \(memoriesContext)

        Use this knowledge to personalize your responses. For example, don't suggest fish if they don't like it.

        """
    }

    private func buildPulseContextSection(pulseContext: String) -> String {
        """

        RECENT SHORT-TERM CONTEXT (PULSE):
        \(pulseContext)

        Treat this as temporary context with higher near-term priority than general advice.
        """
    }

    private func buildPendingSuggestionSection(pending: SuggestedFoodEntry) -> String {
        """

        PENDING MEAL SUGGESTION (not yet logged):
        - Name: \(pending.name)
        - Calories: \(pending.calories) kcal
        - Protein: \(Int(pending.proteinGrams))g, Carbs: \(Int(pending.carbsGrams))g, Fat: \(Int(pending.fatGrams))g
        \(pending.servingSize.map { "- Serving: \($0)" } ?? "")

        If the user says this is wrong or wants corrections (e.g., "that's actually a wrap", "it's closer to 400 calories", "add the sauce"), provide an UPDATED suggest_food_log with the corrected values. Acknowledge their correction naturally.

        """
    }

    private func buildActiveWorkoutSection(workout: WorkoutContext) -> String {
        """

        ⚠️ ACTIVE WORKOUT IN PROGRESS - PRIORITY CONTEXT:
        \(workout.description)

        The user is mid-workout and opened chat between sets. This is your TOP priority:
        - They're likely asking about their CURRENT workout (exercises, form, alternatives)
        - Keep responses SHORT (2-3 sentences max) - they're holding their phone between sets
        - Be direct and actionable - no lengthy explanations
        - If they ask about form, give ONE key cue
        - If something hurts, suggest ONE alternative exercise
        - Offer quick encouragement but don't be preachy

        """
    }

    private func buildGuidelinesSection() -> String {
        """

        GUIDELINES:
        - Follow the user's intent naturally. If they switch topics, go with them.
        - When asked about progress or meals, call get_food_log first.
        - For food photos, analyze and call suggest_food_log with estimates.
        - Include relevant emojis for food (☕, 🥗, 🍳, etc.)
        - When suggesting plan changes, explain WHY before calling update_user_plan.

        FOOD LOGGING:
        - Call suggest_food_log ONLY when user says they ATE something ("I had an apple", "just ate lunch")
        - For corrections to existing meals: call get_food_log to find the entry ID, then edit_food_entry
        - Don't say "I've logged this" - you suggest, user confirms

        RECOVERY & WORKOUTS:
        When asked about recovery or what to work out: call get_muscle_recovery_status, then give a specific recommendation based on which muscles are ready.

        PLAN REVIEWS:
        When user asks to review their plan:
        1. FIRST call: get_weight_history (30 days), get_food_log (this_week), get_recent_workouts (14 days)
        2. Recalculate TDEE from current weight using Mifflin-St Jeor + activity multiplier
        3. Compare to current plan and their actual progress
        4. Explain your reasoning with the data

        WEIGHT LOGGING:
        - If user provides a body weight ("I'm 182 lbs", "log 79.8 kg"), call log_weight
        - Include unit from user message when available; default to profile preference only if not explicit
        - After calling log_weight, confirm success and repeat what was logged

        MEMORY:
        Save important persistent facts (preferences, restrictions, habits, goals) with save_memory. Be proactive - if they mention something useful for future conversations, save it.
        Use save_short_term_context for temporary states (pain flare, bad sleep, short travel constraints) that should expire soon. Use clear_short_term_context when those temporary states resolve.
        """
    }

    // MARK: - Follow-up Response Senders

    func sendFunctionResultForSuggestion(
        name: String,
        response: [String: Any],
        previousContents: [[String: Any]],
        originalParts: [[String: Any]],
        executor: GeminiFunctionExecutor
    ) async throws -> FunctionFollowUpResult {
        let funcResult = GeminiFunctionExecutor.FunctionResult(name: name, response: response)
        return try await sendFunctionResult(
            functionResult: funcResult,
            previousContents: previousContents,
            originalParts: originalParts,
            executor: executor,
            onTextChunk: nil
        )
    }

    func sendFunctionResult(
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

        for iteration in 0..<5 {
            guard let funcResult = pendingFunctionResult else { break }
            pendingFunctionResult = nil

            contents.append([
                "role": "model",
                "parts": currentParts
            ])

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
                "generationConfig": buildGenerationConfig(thinkingLevel: .low)
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

                guard let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    continue
                }

                receivedAnyContent = true

                for part in parts {
                    currentParts.append(part)

                    if let text = part["text"] as? String {
                        result.text += text
                    }

                    if let functionCall = part["functionCall"] as? [String: Any],
                       let functionName = functionCall["name"] as? String {
                        log("⏭️ Ignoring follow-up function call: \(functionName)", type: .debug)
                    }
                }
            }

            result.accumulatedParts = currentParts

            if !receivedAnyContent {
                log("⚠️ No response at iteration \(iteration)", type: .info)
            }
        }

        return result
    }

    func sendParallelFunctionResults(
        functionResults: [GeminiFunctionExecutor.FunctionResult],
        previousContents: [[String: Any]],
        originalParts: [[String: Any]],
        executor: GeminiFunctionExecutor,
        previousText: String = "",
        onTextChunk: ((String) -> Void)?,
        depth: Int = 0
    ) async throws -> FunctionFollowUpResult {
        guard depth < 5 else {
            log("⚠️ Max function call depth reached, stopping chain", type: .info)
            return FunctionFollowUpResult()
        }

        var contents = previousContents
        var result = FunctionFollowUpResult()
        let accumulatedPreviousText = previousText

        contents.append([
            "role": "model",
            "parts": originalParts
        ])

        var responseParts: [[String: Any]] = []
        for funcResult in functionResults {
            responseParts.append([
                "functionResponse": [
                    "name": funcResult.name,
                    "response": funcResult.response
                ]
            ])
        }

        contents.append([
            "role": "user",
            "parts": responseParts
        ])

        let requestBody: [String: Any] = [
            "contents": contents,
            "tools": [["function_declarations": GeminiFunctionDeclarations.chatFunctions]],
            "generationConfig": buildGenerationConfig(thinkingLevel: .low)
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

            guard let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            for part in parts {
                result.accumulatedParts.append(part)

                if let text = part["text"] as? String {
                    result.text += text
                    if let onTextChunk {
                        onTextChunk(accumulatedPreviousText + result.text)
                    }
                }

                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String {
                    // Allow multiple food suggestions but stop chain for other types
                    let hasNonFoodSuggestion = result.planUpdate != nil || result.suggestedFoodEdit != nil
                    if hasNonFoodSuggestion && functionName != "suggest_food_log" {
                        log("⏭️ Skipping \(functionName) - already have suggestion", type: .info)
                        continue
                    }

                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    let argsPreview = args.keys.joined(separator: ", ")
                    log("🔗 Chain[\(depth)]: \(functionName)(\(argsPreview))", type: .info)

                    let call = GeminiFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                    let execResult = executor.execute(call)

                    if functionName == "save_memory", let content = args["content"] as? String {
                        result.savedMemories.append(content)
                    }

                    switch execResult {
                    case .suggestedFood(let food):
                        result.suggestedFoods.append(food)
                        log("🍽️ Got food suggestion (\(result.suggestedFoods.count) total)", type: .info)

                    case .suggestedPlanUpdate(let update):
                        result.planUpdate = update
                        log("📊 Got plan update - stopping chain", type: .info)

                    case .suggestedFoodEdit(let edit):
                        result.suggestedFoodEdit = edit
                        log("✏️ Got edit suggestion - stopping chain", type: .info)

                    case .dataResponse(let nextFuncResult):
                        additionalFunctionResults.append(nextFuncResult)

                    case .suggestedWorkout(let suggestion):
                        log("💪 Got workout suggestion - stopping chain", type: .info)
                        // Workout suggestions handled in WorkoutsView
                        _ = suggestion

                    case .suggestedWorkoutStart(let workout):
                        result.suggestedWorkout = workout
                        log("🏋️ Got workout start suggestion - stopping chain", type: .info)

                    case .suggestedWorkoutLog(let workoutLog):
                        result.suggestedWorkoutLog = workoutLog
                        log("📝 Got workout log suggestion - stopping chain", type: .info)

                    case .startedLiveWorkout(let workout):
                        log("🏋️ Started workout (legacy) - stopping chain", type: .info)
                        // User should navigate to workout view
                        _ = workout

                    case .suggestedReminder(let reminder):
                        result.suggestedReminder = reminder
                        log("⏰ Got reminder suggestion - stopping chain", type: .info)

                    case .noAction:
                        break
                    }
                }
            }
        }

        let hasSuggestion = !result.suggestedFoods.isEmpty || result.planUpdate != nil || result.suggestedFoodEdit != nil || result.suggestedWorkout != nil || result.suggestedWorkoutLog != nil || result.suggestedReminder != nil
        if !additionalFunctionResults.isEmpty && !hasSuggestion {
            let chainedResult = try await sendParallelFunctionResults(
                functionResults: additionalFunctionResults,
                previousContents: contents,
                originalParts: result.accumulatedParts,
                executor: executor,
                previousText: accumulatedPreviousText + result.text,
                onTextChunk: onTextChunk,
                depth: depth + 1
            )
            if !chainedResult.text.isEmpty {
                result.text += chainedResult.text
            }
            result.suggestedFoods.append(contentsOf: chainedResult.suggestedFoods)
            if let plan = chainedResult.planUpdate {
                result.planUpdate = plan
            }
            if let edit = chainedResult.suggestedFoodEdit {
                result.suggestedFoodEdit = edit
            }
            if let reminder = chainedResult.suggestedReminder {
                result.suggestedReminder = reminder
            }
            result.savedMemories.append(contentsOf: chainedResult.savedMemories)
        }

        return result
    }
}
