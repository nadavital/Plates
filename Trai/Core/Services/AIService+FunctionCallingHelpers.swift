//
//  AIService+FunctionCallingHelpers.swift
//  Trai
//
//  Helper methods for AI function calling
//

import Foundation
import SwiftData
import os

extension AIService {

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
        - Editing specific meal components after something was logged (edit_food_components)
        - Viewing and updating the user's nutrition plan (get_user_plan, update_user_plan)
        - Checking workout history (get_recent_workouts)
        - Reviewing and revising the user's workout plan (revise_workout_plan)
        - Reading and managing workout goals (get_workout_goals, create_workout_goal, update_workout_goal)
        - Logging workouts (log_workout)
        - Checking and logging body weight (get_weight_history, log_weight)
        - Remembering facts about the user (save_memory, delete_memory)
        - Managing temporary short-term context (save_short_term_context, clear_short_term_context)

        Current date/time: \(context.currentDateTime)

        """

        if let profile = context.profile {
            prompt += buildUserInfoSection(profile: profile)
            prompt += buildWorkoutPlanSection(profile: profile)
        }

        prompt += buildTodaysFoodSection(entries: context.todaysFoodEntries)

        if !context.memoriesContext.isEmpty {
            prompt += buildMemoriesSection(memoriesContext: context.memoriesContext)
        }

        if !context.coachContext.isEmpty {
            prompt += buildCoachContextSection(coachContext: context.coachContext)
        }

        if let pending = context.pendingSuggestion {
            prompt += buildPendingSuggestionSection(pending: pending)
        }

        if let pendingWorkoutPlan = context.pendingWorkoutPlanSuggestion {
            prompt += buildPendingWorkoutPlanSection(suggestion: pendingWorkoutPlan)
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

        let trackedMacroNames = profile.enabledMacrosOrdered.map(\.displayName).joined(separator: ", ")

        section += """
        User's Goal: \(profile.goal.displayName)
        Daily Targets: \(profile.dailyCalorieGoal) kcal, \(profile.dailyProteinGoal)g protein, \(profile.dailyCarbsGoal)g carbs, \(profile.dailyFatGoal)g fat, \(profile.dailyFiberGoal)g fiber, \(profile.dailySugarGoal)g sugar
        Actively Tracked Macros: \(trackedMacroNames.isEmpty ? "Calories only" : trackedMacroNames)
        All macro targets are still stored in the plan, but day-to-day UI should prioritize the actively tracked macros.

        """

        return section
    }

    private func buildTodaysFoodSection(entries: [FoodEntry]) -> String {
        """

        TODAY'S LOGGED FOOD SNAPSHOT:
        \(FoodLogSummaryFormatter.promptSummary(for: entries, label: "Food log"))

        Use this snapshot to stay grounded in what the user has already logged today.
        This snapshot is conversational context only and does NOT provide entry IDs.
        Still call get_food_log for exact date-range questions, nutrition math, or before editing an existing entry.

        """
    }

    private func buildWorkoutPlanSection(profile: UserProfile) -> String {
        guard let plan = profile.workoutPlan else { return "" }

        let sessionPreview = plan.templates
            .sorted { $0.order < $1.order }
            .prefix(5)
            .map(\.name)
            .joined(separator: ", ")

        return """

        CURRENT WORKOUT PLAN:
        - Split: \(plan.splitType.displayName)
        - Days per week: \(plan.daysPerWeek)
        - Sessions: \(sessionPreview)

        """
    }

    private func buildMemoriesSection(memoriesContext: String) -> String {
        """

        WHAT YOU KNOW ABOUT THIS USER:
        \(memoriesContext)

        Use this knowledge to personalize your responses. For example, don't suggest fish if they don't like it.

        """
    }

    private func buildCoachContextSection(coachContext: String) -> String {
        """

        RECENT SHORT-TERM CONTEXT:
        \(coachContext)

        Treat this as temporary context with higher near-term priority than general advice.
        """
    }

    private func buildPendingSuggestionSection(pending: SuggestedFoodEntry) -> String {
        """

        PENDING MEAL SUGGESTION (not yet logged):
        - Name: \(pending.name)
        - Calories: \(pending.calories) kcal
        - Protein: \(Int(pending.proteinGrams))g, Carbs: \(Int(pending.carbsGrams))g, Fat: \(Int(pending.fatGrams))g
        \(pending.loggedAtDateString.map { "- Date: \($0)" } ?? "")
        \(pending.loggedAtTime.map { "- Time: \($0)" } ?? "")
        \(pending.servingSize.map { "- Serving: \($0)" } ?? "")
        \(!pending.components.isEmpty ? "- Components: \(pending.components.map(\.displayName).joined(separator: ", "))" : "")

        If the user says this is wrong or wants corrections (e.g., "that's actually a wrap", "it's closer to 400 calories", "add the sauce", "no toast", "half the rice"), provide an UPDATED suggest_food_log with corrected totals and corrected components. Acknowledge their correction naturally.

        """
    }

    private func buildPendingWorkoutPlanSection(suggestion: WorkoutPlanSuggestionEntry) -> String {
        let sessionPreview = suggestion.plan.templates
            .sorted { $0.order < $1.order }
            .prefix(5)
            .map(\.name)
            .joined(separator: ", ")

        return """

        PENDING WORKOUT PLAN PROPOSAL (not yet saved):
        - Split: \(suggestion.plan.splitType.displayName)
        - Days per week: \(suggestion.plan.daysPerWeek)
        - Sessions: \(sessionPreview)

        If the user asks for another tweak before saving, treat this pending proposal as the current draft and revise from it, not from their saved plan.

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
        - For nutrition plan changes, prioritize the macros the user is actively tracking in the app. It is okay for the underlying plan to keep sensible targets for other macros too.
        - Never ask the user for internal IDs, UUIDs, database identifiers, or tool-only fields if you can retrieve them yourself.

        FOOD LOGGING:
        - Call suggest_food_log ONLY when user says they ATE something ("I had an apple", "just ate lunch")
        - If the user specifies a past day or explicit date for a meal, include logged_at_date in YYYY-MM-DD format when calling suggest_food_log.
        - If the user specifies only a time, include logged_at_time in HH:mm 24-hour format.
        - When a food or drink is primarily sugar or contains clearly inferable sugar, include sugar_grams explicitly. Sugar is a subset of carbs, so for plain sugar, honey, syrup, soda, juice, candy, or sweetened drinks, sugar_grams should not be omitted or set to 0 when carbs are present. For something like pure table sugar, sugar_grams should match carbs_grams.
        - When a meal has multiple meaningful parts, include components in suggest_food_log with per-component macros and stable IDs when possible.
        - For corrections to existing meals: ALWAYS call get_food_log first to find the correct entry ID, then call edit_food_entry or edit_food_components depending on whether the user is changing the whole meal or just one part of it.
        - For corrections to PART of an existing meal (for example "remove the toast", "half the rice", "add avocado", "I didn't eat the sauce"), call get_food_log with include_components=true and then call edit_food_components.
        - Prefer edit_food_components over edit_food_entry when the user is clearly changing one component or part of a meal rather than renaming or replacing the whole entry.
        - Do not rely on the injected food snapshot for edits; it does not include entry IDs.
        - Never ask the user for a food entry ID or UUID.
        - Never ask the user for a component ID. If you need it, get it from get_food_log(include_components=true).
        - If multiple logged meals could match the user's correction, ask one short natural-language follow-up using meal details like name, time, or date, never internal identifiers.
        - Don't say "I've logged this" - you suggest, user confirms

        RECOVERY & WORKOUTS:
        When asked about recovery or what to work out: call get_muscle_recovery_status, then give a specific recommendation based on which muscles are ready.

        WORKOUT PLAN CHANGES:
        - If the user wants to review or change their workout plan, use revise_workout_plan.
        - Before revising the plan, call get_recent_workouts and/or get_muscle_recovery_status when that context would materially improve the recommendation.
        - Put the requested change plus any relevant findings directly into revise_workout_plan.change_request.
        - Never say the workout plan was already saved; the user must confirm the proposal first.

        WORKOUT GOALS:
        - When the user wants to set, refine, pause, complete, or review workout goals, use get_workout_goals first unless the request is brand new and fully specified.
        - Workout goals should usually be multi-session or multi-week, not "complete one normal workout."
        - Prefer progression, consistency, frequency, distance, duration, or milestone framing over one-off routine completion.
        - If the user asks for something like "work out 3x a week", create a frequency goal with the right cadence fields instead of flattening it into a generic milestone.
        - If the request maps to a specific recurring exercise, it's okay to create an activity-linked goal for that exercise.
        - Use soft target dates when they help make the goal concrete, but don't force a hard date on every goal.
        - After updating or creating a workout goal, clearly tell the user what changed.

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
        previousMessages: [TraiAIMessage],
        originalParts: [TraiAIPart],
        executor: AIFunctionExecutor
    ) async throws -> FunctionFollowUpResult {
        let funcResult = AIFunctionExecutor.FunctionResult(name: name, response: response)
        return try await sendFunctionResult(
            functionResult: funcResult,
            previousMessages: previousMessages,
            originalParts: originalParts,
            executor: executor,
            onTextChunk: nil
        )
    }

    func sendFunctionResult(
        functionResult: AIFunctionExecutor.FunctionResult,
        previousMessages: [TraiAIMessage],
        originalParts: [TraiAIPart],
        executor: AIFunctionExecutor,
        onTextChunk: ((String) -> Void)?
    ) async throws -> FunctionFollowUpResult {
        var messages = previousMessages
        var currentParts = originalParts
        var result = FunctionFollowUpResult()
        var pendingFunctionResult: AIFunctionExecutor.FunctionResult? = functionResult

        for iteration in 0..<5 {
            guard let funcResult = pendingFunctionResult else { break }
            pendingFunctionResult = nil

            messages.append(
                AIBackendPayloadBuilder.canonicalMessage(role: .assistant, parts: currentParts)
            )
            messages.append(
                AIBackendPayloadBuilder.canonicalMessage(
                    role: .tool,
                    parts: [
                        AIBackendPayloadBuilder.toolResponsePart(
                            name: funcResult.name,
                            response: funcResult.response
                        )
                    ]
                )
            )

            let requestBody = AIBackendPayloadBuilder.requestBody(from: AIBackendPayloadBuilder.canonicalRequest(
                messages: messages,
                generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .low)
            ))

            let requestTicket = try beginAIRequest(for: .agentToolFollowUp)

            do {
                let url = try serviceURL(action: "streamGenerateContent", streaming: true)

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                try await configureRequest(&request)
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    cancelAIRequest(requestTicket)
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
                        if let text = part["text"] as? String {
                            currentParts.append(.text(text))
                            result.text += text
                        }

                        if let functionCall = part["functionCall"] as? [String: Any],
                           let functionName = functionCall["name"] as? String {
                            currentParts.append(
                                AIBackendPayloadBuilder.toolCallPart(
                                    id: functionCall["id"] as? String,
                                    name: functionName,
                                    arguments: functionCall["args"] as? [String: Any] ?? [:]
                                )
                            )
                            log("⏭️ Ignoring follow-up function call: \(functionName)", type: .debug)
                        }
                    }
                }

                completeAIRequest(requestTicket)
                result.accumulatedParts = currentParts

                if !receivedAnyContent {
                    log("⚠️ No response at iteration \(iteration)", type: .info)
                }
            } catch {
                cancelAIRequest(requestTicket)
                throw error
            }
        }

        return result
    }

    func sendParallelFunctionResults(
        functionResults: [AIFunctionExecutor.FunctionResult],
        previousMessages: [TraiAIMessage],
        originalParts: [TraiAIPart],
        executor: AIFunctionExecutor,
        previousText: String = "",
        onTextChunk: ((String) -> Void)?,
        depth: Int = 0
    ) async throws -> FunctionFollowUpResult {
        guard depth < 5 else {
            log("⚠️ Max function call depth reached, stopping chain", type: .info)
            return FunctionFollowUpResult()
        }

        var messages = previousMessages
        var result = FunctionFollowUpResult()
        let accumulatedPreviousText = previousText

        messages.append(
            AIBackendPayloadBuilder.canonicalMessage(role: .assistant, parts: originalParts)
        )
        messages.append(
            AIBackendPayloadBuilder.canonicalMessage(
                role: .tool,
                parts: functionResults.map {
                    AIBackendPayloadBuilder.toolResponsePart(
                        name: $0.name,
                        response: $0.response
                    )
                }
            )
        )

        let canonicalTools: [TraiAITool] = AIFunctionDeclarations.chatFunctions.compactMap { declaration in
            guard let name = declaration["name"] as? String else { return nil }
            return AIBackendPayloadBuilder.canonicalTool(
                name: name,
                description: declaration["description"] as? String ?? "",
                parameters: declaration["parameters"] as? [String: Any] ?? [:]
            )
        }

        let requestBody = AIBackendPayloadBuilder.requestBody(from: AIBackendPayloadBuilder.canonicalRequest(
            messages: messages,
            tools: canonicalTools,
            generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .low)
        ))

        let requestTicket = try beginAIRequest(for: .agentToolFollowUp)

        do {
            let url = try serviceURL(action: "streamGenerateContent", streaming: true)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            try await configureRequest(&request)
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                cancelAIRequest(requestTicket)
                log("❌ Parallel function response request failed", type: .error)
                return result
            }

            var additionalFunctionResults: [AIFunctionExecutor.FunctionResult] = []

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
                    if let text = part["text"] as? String {
                        result.accumulatedParts.append(.text(text))
                        result.text += text
                        if let onTextChunk {
                            onTextChunk(accumulatedPreviousText + result.text)
                        }
                    }

                    if let functionCall = part["functionCall"] as? [String: Any],
                       let functionName = functionCall["name"] as? String {
                        // Allow multiple food suggestions but stop chain for other types
                        let hasNonFoodSuggestion =
                            result.planUpdate != nil ||
                            result.suggestedFoodEdit != nil ||
                            result.suggestedFoodComponentEdit != nil ||
                            result.suggestedWorkoutPlan != nil ||
                            result.suggestedWorkout != nil ||
                            result.suggestedWorkoutLog != nil ||
                            result.suggestedReminder != nil
                        if hasNonFoodSuggestion && functionName != "suggest_food_log" {
                            log("⏭️ Skipping \(functionName) - already have suggestion", type: .info)
                            continue
                        }

                        let args = functionCall["args"] as? [String: Any] ?? [:]
                        result.accumulatedParts.append(
                            AIBackendPayloadBuilder.toolCallPart(
                                id: functionCall["id"] as? String,
                                name: functionName,
                                arguments: args
                            )
                        )
                        let argsPreview = args.keys.joined(separator: ", ")
                        log("🔗 Chain[\(depth)]: \(functionName)(\(argsPreview))", type: .info)

                        let call = AIFunctionExecutor.FunctionCall(name: functionName, arguments: args)
                        let execResult = await executor.execute(call)

                        if functionName == "save_memory", let content = args["content"] as? String {
                            result.savedMemories.append(content)
                        }

                        switch execResult {
                        case .directMessage(let message):
                            if result.text.isEmpty {
                                result.text = message
                            }

                        case .suggestedFood(let food):
                            result.suggestedFoods.append(food)
                            log("🍽️ Got food suggestion (\(result.suggestedFoods.count) total)", type: .info)

                        case .suggestedPlanUpdate(let update):
                            result.planUpdate = update
                            log("📊 Got plan update - stopping chain", type: .info)

                        case .suggestedFoodEdit(let edit):
                            result.suggestedFoodEdit = edit
                            log("✏️ Got edit suggestion - stopping chain", type: .info)

                        case .suggestedFoodComponentEdit(let edit):
                            result.suggestedFoodComponentEdit = edit
                            log("🧩 Got component edit suggestion - stopping chain", type: .info)

                        case .suggestedWorkoutPlanUpdate(let workoutPlan):
                            result.suggestedWorkoutPlan = workoutPlan
                            if result.text.isEmpty {
                                result.text = workoutPlan.message
                            }
                            log("🗓️ Got workout plan suggestion - stopping chain", type: .info)

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

            completeAIRequest(requestTicket)

            let hasSuggestion = !result.suggestedFoods.isEmpty || result.planUpdate != nil || result.suggestedFoodEdit != nil || result.suggestedFoodComponentEdit != nil || result.suggestedWorkoutPlan != nil || result.suggestedWorkout != nil || result.suggestedWorkoutLog != nil || result.suggestedReminder != nil
            if !additionalFunctionResults.isEmpty && !hasSuggestion {
                let chainedResult = try await sendParallelFunctionResults(
                    functionResults: additionalFunctionResults,
                    previousMessages: messages,
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
                if let componentEdit = chainedResult.suggestedFoodComponentEdit {
                    result.suggestedFoodComponentEdit = componentEdit
                }
                if let workoutPlan = chainedResult.suggestedWorkoutPlan {
                    result.suggestedWorkoutPlan = workoutPlan
                }
                if let reminder = chainedResult.suggestedReminder {
                    result.suggestedReminder = reminder
                }
                result.savedMemories.append(contentsOf: chainedResult.savedMemories)
            }

            return result
        } catch {
            cancelAIRequest(requestTicket)
            throw error
        }
    }
}
