//
//  GeminiService+FunctionCallingHelpers.swift
//  Plates
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
        - Checking food log and nutrition progress (get_food_log)
        - Viewing and updating the user's nutrition plan (get_user_plan, update_user_plan)
        - Checking workout history (get_recent_workouts)
        - Logging workouts (log_workout)
        - Remembering facts about the user (save_memory, delete_memory)

        Current date/time: \(context.currentDateTime)

        """

        if let profile = context.profile {
            prompt += buildUserInfoSection(profile: profile)
        }

        if !context.memoriesContext.isEmpty {
            prompt += buildMemoriesSection(memoriesContext: context.memoriesContext)
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
        if let weight = profile.currentWeightKg {
            let weightStr = profile.usesMetricWeight
                ? "\(Int(weight)) kg"
                : "\(Int(weight * 2.205)) lbs"
            userInfo.append("Current weight: \(weightStr)")
        }

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

        🏋️ ACTIVE WORKOUT IN PROGRESS:
        \(workout.description)

        The user is currently working out and opened chat mid-workout. Be especially helpful about:
        - Form tips for their current exercise
        - Rest time suggestions
        - Exercise alternatives if something hurts
        - Motivation and encouragement
        - Quick questions about their workout

        Keep responses SHORT - they're in the middle of a workout and checking their phone between sets.

        """
    }

    private func buildGuidelinesSection() -> String {
        """

        IMPORTANT GUIDELINES:
        1. Follow the user's current intent. If they switch topics, follow along naturally.
        2. ONLY use suggest_food_log when the user EXPLICITLY says they ate/had/consumed something NEW (e.g., "I just had an apple", "I ate a sandwich", "Had coffee this morning").
           - Do NOT suggest logging for questions about food ("is this healthy?", "what about bananas?")
           - Do NOT suggest logging when discussing food hypothetically
           - Do NOT suggest logging in follow-up responses unless the user mentions eating something new
           - Do NOT use suggest_food_log to correct/edit an already-logged meal - use edit_food_entry instead
        3. EDITING LOGGED MEALS: When the user wants to change/correct an already-logged meal:
           - First use get_food_log to find the entry and its ID
           - Then use edit_food_entry with the entry_id to modify it
           - NEVER create a new entry with suggest_food_log when editing existing meals
        4. When asked about progress or what they've eaten, use get_food_log.
        5. Be conversational and concise. Answer questions directly.
        6. For food photos, analyze and use suggest_food_log with nutritional estimates.
        7. Don't say "I've logged this" - you can only suggest, the user confirms.
        8. Include relevant emojis for food items (☕, 🥗, 🍳, etc.)
        9. When using update_user_plan to suggest plan changes, ALWAYS include a conversational message explaining WHY you're suggesting the changes. Never just return the plan update without context - the user needs to understand your reasoning before seeing the suggestion card.

        MEMORY USAGE:
        - Use save_memory to remember important facts about the user that will help you be a better coach.
        - Save preferences ("doesn't like fish", "prefers morning workouts"), restrictions ("allergic to nuts", "knee injury"), habits ("usually skips breakfast"), goals ("training for marathon"), and context ("works night shifts").
        - Be proactive about saving memories - if the user mentions something that would help future conversations, save it.
        - Use delete_memory when the user indicates something has changed (e.g., "I actually like fish now").
        - Don't save trivial or one-time information - focus on persistent facts and preferences.
        - You can call save_memory in parallel with other function calls when appropriate.
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
                    if result.suggestedFood != nil || result.planUpdate != nil || result.suggestedFoodEdit != nil {
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
                        result.suggestedFood = food
                        log("🍽️ Got food suggestion - stopping chain", type: .info)

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

                    case .noAction:
                        break
                    }
                }
            }
        }

        let hasSuggestion = result.suggestedFood != nil || result.planUpdate != nil || result.suggestedFoodEdit != nil || result.suggestedWorkout != nil || result.suggestedWorkoutLog != nil
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
            if let food = chainedResult.suggestedFood {
                result.suggestedFood = food
            }
            if let plan = chainedResult.planUpdate {
                result.planUpdate = plan
            }
            if let edit = chainedResult.suggestedFoodEdit {
                result.suggestedFoodEdit = edit
            }
            result.savedMemories.append(contentsOf: chainedResult.savedMemories)
        }

        return result
    }
}
