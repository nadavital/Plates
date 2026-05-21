//
//  AIService+WorkoutPlan.swift
//  Trai
//
//  Workout plan generation and refinement
//

import Foundation
import os

extension AIService {

    // MARK: - Workout Plan Refinement Response

    struct WorkoutPlanRefinementResponse {
        let responseType: ResponseType
        let message: String
        let proposedPlan: WorkoutPlan?
        let updatedPlan: WorkoutPlan?

        enum ResponseType: String {
            case message
            case proposePlan
            case planUpdate
        }
    }

    struct WorkoutPlanFollowUpQuestion: Decodable {
        let prompt: String
        let placeholder: String?
        let suggestions: [WorkoutPlanFollowUpSuggestion]
    }

    struct WorkoutPlanFollowUpSuggestion: Decodable {
        let title: String
        let text: String
    }

    private struct WorkoutPlanFollowUpQuestionEnvelope: Decodable {
        let question: WorkoutPlanFollowUpQuestion
    }

    struct WorkoutPlanGenerationResult {
        let plan: WorkoutPlan
        let goalSuggestions: [WorkoutGoalSuggestion]
    }

    private struct WorkoutPlanGenerationEnvelope: Decodable {
        let plan: WorkoutPlan
        let goalSuggestions: [WorkoutGoalSuggestion]
    }

    // MARK: - Workout Plan Generation

    /// Generate a personalized workout plan
    func generateWorkoutPlan(request: WorkoutPlanGenerationRequest) async throws -> WorkoutPlan {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        let requestTicket = try beginAIRequest(for: .workoutPlanGeneration)

        log("🏋️ Starting workout plan generation for: \(request.name)", type: .info)
        log("📊 User data - Age: \(request.age), Goal: \(request.goal.rawValue)", type: .info)
        log("🎯 Workout prefs - Days: \(request.availableDays.map { "\($0)" } ?? "flexible"), Experience: \(request.experienceLevel?.rawValue ?? "unspecified"), Equipment: \(request.equipmentAccess?.rawValue ?? "unspecified")", type: .info)

        let prompt = AIPromptBuilder.buildWorkoutPlanGenerationPrompt(request: request)
        logPrompt(prompt)

        do {
            let plan: WorkoutPlan = try await executePlanGenerationPipeline(
                prompt: prompt,
                schema: AIPromptBuilder.workoutPlanSchema,
                decodeFailureLabel: "workout plan",
                reasoningLevel: .low
            )
            let validatedPlan: WorkoutPlan
            do {
                validatedPlan = try validateGeneratedWorkoutPlan(plan, request: request)
            } catch {
                log("Generated workout plan failed validation: \(error.localizedDescription). Retrying with stricter instructions.", type: .error)
                let repairedPlan: WorkoutPlan = try await executePlanGenerationPipeline(
                    prompt: correctiveWorkoutPlanPrompt(
                        originalPrompt: prompt,
                        invalidPlan: plan,
                        request: request
                    ),
                    schema: AIPromptBuilder.workoutPlanSchema,
                    decodeFailureLabel: "corrected workout plan",
                    reasoningLevel: .low
                )
                validatedPlan = try validateGeneratedWorkoutPlan(repairedPlan, request: request)
            }
            completeAIRequest(requestTicket)
            log("✅ Successfully parsed workout plan - Split: \(validatedPlan.splitType.displayName), Templates: \(validatedPlan.templates.count)", type: .info)
            return validatedPlan
        } catch AIServiceError.parsingError {
            cancelAIRequest(requestTicket)
            log("Workout plan generation failed because the AI response could not be parsed. Not falling back silently.", type: .error)
            throw AIServiceError.parsingError
        } catch {
            cancelAIRequest(requestTicket)
            log("Failed to generate workout plan: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    func generateWorkoutPlanWithGoalSuggestions(
        request: WorkoutPlanGenerationRequest,
        userGoal: String?,
        memoryContext: [String],
        existingGoals: [String],
        userIntent: String?,
        prefersMetricWeight: Bool
    ) async throws -> WorkoutPlanGenerationResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        let requestTicket = try beginAIRequest(for: .workoutPlanGeneration)

        log("🏋️ Starting workout plan + goals generation for: \(request.name)", type: .info)
        log("🎯 Workout prefs - Days: \(request.availableDays.map { "\($0)" } ?? "flexible"), Experience: \(request.experienceLevel?.rawValue ?? "unspecified"), Equipment: \(request.equipmentAccess?.rawValue ?? "unspecified")", type: .info)

        let prompt = workoutPlanWithGoalsPrompt(
            request: request,
            userGoal: userGoal,
            memoryContext: memoryContext,
            existingGoals: existingGoals,
            userIntent: userIntent,
            prefersMetricWeight: prefersMetricWeight
        )
        logPrompt(prompt)

        do {
            let envelope: WorkoutPlanGenerationEnvelope = try await executePlanGenerationPipeline(
                prompt: prompt,
                schema: AIPromptBuilder.workoutPlanWithGoalSuggestionsSchema,
                decodeFailureLabel: "workout plan with goals",
                reasoningLevel: .low
            )
            let validatedPlan: WorkoutPlan
            do {
                validatedPlan = try validateGeneratedWorkoutPlan(envelope.plan, request: request)
            } catch {
                log("Generated workout plan with goals failed validation: \(error.localizedDescription). Retrying with stricter instructions.", type: .error)
                let repairedEnvelope: WorkoutPlanGenerationEnvelope = try await executePlanGenerationPipeline(
                    prompt: correctiveWorkoutPlanPrompt(
                        originalPrompt: prompt,
                        invalidPlan: envelope.plan,
                        request: request
                    ),
                    schema: AIPromptBuilder.workoutPlanWithGoalSuggestionsSchema,
                    decodeFailureLabel: "corrected workout plan with goals",
                    reasoningLevel: .low
                )
                validatedPlan = try validateGeneratedWorkoutPlan(repairedEnvelope.plan, request: request)
                let repairedGoals = WorkoutGoalSuggestion.validatedUnique(
                    repairedEnvelope.goalSuggestions,
                    allowsWeightGoals: workoutPlanGoalContextHasWeightBaseline(
                        request: request,
                        memoryContext: memoryContext,
                        existingGoals: existingGoals,
                        userIntent: userIntent
                    )
                )
                completeAIRequest(requestTicket)
                log("✅ Successfully parsed workout plan + goals - Split: \(validatedPlan.splitType.displayName), Templates: \(validatedPlan.templates.count), Goals: \(repairedGoals.count)", type: .info)
                return WorkoutPlanGenerationResult(plan: validatedPlan, goalSuggestions: repairedGoals)
            }

            let goals = WorkoutGoalSuggestion.validatedUnique(
                envelope.goalSuggestions,
                allowsWeightGoals: workoutPlanGoalContextHasWeightBaseline(
                    request: request,
                    memoryContext: memoryContext,
                    existingGoals: existingGoals,
                    userIntent: userIntent
                )
            )
            completeAIRequest(requestTicket)
            log("✅ Successfully parsed workout plan + goals - Split: \(validatedPlan.splitType.displayName), Templates: \(validatedPlan.templates.count), Goals: \(goals.count)", type: .info)
            return WorkoutPlanGenerationResult(plan: validatedPlan, goalSuggestions: goals)
        } catch AIServiceError.parsingError {
            cancelAIRequest(requestTicket)
            log("Workout plan + goals generation failed because the AI response could not be parsed. Not falling back silently.", type: .error)
            throw AIServiceError.parsingError
        } catch {
            cancelAIRequest(requestTicket)
            log("Failed to generate workout plan + goals: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    private func workoutPlanGoalContextHasWeightBaseline(
        request: WorkoutPlanGenerationRequest,
        memoryContext: [String],
        existingGoals: [String],
        userIntent: String?
    ) -> Bool {
        WorkoutGoalSuggestion.hasWeightBaselineContext(
            memoryContext
            + existingGoals
            + (request.conversationContext ?? [])
            + (request.specificGoals ?? [])
            + [request.preferences, userIntent].compactMap { $0 }
        )
    }

    private func validateGeneratedWorkoutPlan(
        _ plan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest
    ) throws -> WorkoutPlan {
        guard !plan.templates.isEmpty else {
            throw AIServiceError.parsingError
        }
        guard plan.planIntent != nil, plan.modalityProgression != nil else {
            log("Workout plan missing planIntent or modalityProgression.", type: .error)
            throw AIServiceError.parsingError
        }

        guard plan.templates.allSatisfy({ !$0.blocks.isEmpty }) else {
            log("Workout plan missing explicit block structure for one or more templates.", type: .error)
            throw AIServiceError.parsingError
        }

        if let requestedDays = request.availableDays {
            guard plan.templates.count == requestedDays else {
                log("Workout plan template count mismatch. Requested \(requestedDays), got \(plan.templates.count).", type: .error)
                throw AIServiceError.parsingError
            }

            if plan.daysPerWeek != requestedDays {
                return copyWorkoutPlan(plan, daysPerWeek: requestedDays)
            }
        } else if plan.daysPerWeek != plan.templates.count {
            return copyWorkoutPlan(plan, daysPerWeek: plan.templates.count)
        }

        if request.requestsCardioAsAccessory,
           plan.templates.contains(where: { $0.isStandaloneCardioTemplate }) {
            log("Workout plan used a standalone cardio template even though the personalization brief requested cardio as an accessory.", type: .error)
            throw AIServiceError.parsingError
        }

        if request.limitsAccessoryCardioToOneSession {
            let supportBlockCount = plan.templates.reduce(0) { count, template in
                count + template.cardioSupportBlockCount
            }
            guard supportBlockCount <= 1 else {
                log("Workout plan duplicated accessory cardio even though the user limited it to one placement.", type: .error)
                throw AIServiceError.parsingError
            }
        }

        return plan
    }

    private func correctiveWorkoutPlanPrompt(
        originalPrompt: String,
        invalidPlan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest
    ) -> String {
        let requestedDays = request.availableDays.map(String.init) ?? "flexible"
        let requiredTemplateText: String
        if let availableDays = request.availableDays {
            requiredTemplateText = "Return exactly \(availableDays) workout templates. Set daysPerWeek to \(availableDays)."
        } else {
            requiredTemplateText = "For a flexible schedule, make daysPerWeek match the number of templates you return."
        }

        return """
        \(originalPrompt)

        VALIDATION FAILURE TO FIX:
        The previous workout plan was internally inconsistent.
        - Requested available days: \(requestedDays)
        - Returned daysPerWeek: \(invalidPlan.daysPerWeek)
        - Returned templates: \(invalidPlan.templates.count)

        Correct the plan now. \(requiredTemplateText)
        Keep the user's personalization brief as the highest-priority customization input.
        \(request.requestsCardioAsAccessory ? "The user asked for cardio as an accessory or finisher, so do not return standalone cardio or HIIT templates. Add the cardio work inside one strength or mixed template instead." : "")
        \(request.limitsAccessoryCardioToOneSession ? "The user limited cardio support to one placement, so return exactly one cardio finisher/accessory block in the whole plan." : "")
        Return planIntent, modalityProgression, and ordered blocks for every template. Do not flatten activity work into fake strength exercises.
        Return only the corrected JSON object matching the schema.
        """
    }

    private func workoutPlanWithGoalsPrompt(
        request: WorkoutPlanGenerationRequest,
        userGoal: String?,
        memoryContext: [String],
        existingGoals: [String],
        userIntent: String?,
        prefersMetricWeight: Bool
    ) -> String {
        let workoutModes = WorkoutMode.allCases.map(\.rawValue).joined(separator: ", ")
        let contextGoal = userGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntent = userIntent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePrompt = AIPromptBuilder.buildWorkoutPlanGenerationPrompt(request: request)

        return """
        \(basePrompt)

        ALSO CREATE GOALS:
        Alongside the plan, return 0-2 goalSuggestions that are directly tied to the plan you create. One strong goal is better than two weak goals. Returning no goals is acceptable when the plan/context does not support a goal that is specific, useful, and trackable.
        - Prefer one concrete plan-specific goal. Add a second only when it captures a different, meaningful intent from the plan or user request.
        - Goals should feel meaningful over roughly the next 4-8 weeks unless the user asked for a different timeline.
        - Do not suggest goals like "complete a workout" or anything that is already normal baseline behavior.
        - For new users or thin context, avoid goals that sound like performance progression unless Trai has a baseline to compare against.
        - Do not create vague progression goals like "add one rep", "add a little load", "improve the main lifts", or "get stronger" unless the structured target and successCriteria make the exact achievement verifiable from app data.
        - Broad goals are allowed, but the intent must be accurate: goal title, target fields, linkedWorkoutType/linkedActivityName, and successCriteria should all describe the same behavior Trai can track.
        - If the plan includes a personalized constraint or habit, such as cardio only as a lower-day finisher, prefer a goal for that habit over generic strength progression.
        - Every goal must include successCriteria: one concise sentence that says how Trai and the person using the app will know the goal is achieved.
        - Write rationale, successCriteria, and notes directly to the person using the app with "you" and "your"; do not say "the user".
        - Frequency, duration, distance, and weight goals must have a targetValue greater than 0 and a clear targetUnit.
        - Frequency goals must also include periodUnitRaw and periodCount.
        - For frequency goals, periodCount means the denominator period, not the goal horizon. Use periodCount 1 for "per week", "per day", or "per month"; use targetDateISO8601/checkInCadenceDays to express a 4-8 week horizon.
        - Do not return vague frequency goals unless the structured fields make them trackable.
        - Do not use "run" in a goal title unless the plan actually includes running.
        - This is often the user's first Trai workout plan. Unless the context explicitly includes recent lifting numbers, a current baseline, or the user gave one in the setup answers, do not create exercise-specific weight-increase goals like "add 5 kg to bench".
        - Do not infer a strength baseline just because an exercise appears in the plan.
        - Weight/load goals require a known current baseline and should progress from that baseline.
        - When baseline context is thin, prefer goals tied to the generated plan itself: complete the planned weekly structure for several weeks, log each named day in the split, complete a requested accessory habit, build a training routine, or check in on the plan after enough sessions.
        - Avoid duplicating any existing goal.
        - linkedWorkoutType must be one of: \(workoutModes)
        - goalKind must be one of: milestone, frequency, duration, distance, weight
        - For milestone goals, leave targetValue, targetUnit, periodUnitRaw, and periodCount empty.
        - For frequency goals, targetValue must be the count, targetUnit should usually be "sessions" or a specific activity unit, periodUnitRaw must be day, week, or month, and periodCount must be 1.
        - When it helps, include a soft targetDateISO8601 roughly 4-8 weeks out.
        - For weight goals, use \(prefersMetricWeight ? "kg by default" : "lbs by default") unless the user context clearly suggests the other unit.
        - Keep titles short and natural.

        Goal context:
        - Primary fitness goal: \(contextGoal?.isEmpty == false ? contextGoal! : "Not specified")
        - Relevant memory/context: \(memoryContext.isEmpty ? "None" : memoryContext.joined(separator: " | "))
        - Existing workout goals: \(existingGoals.isEmpty ? "None" : existingGoals.joined(separator: " | "))
        - User request: \(trimmedIntent?.isEmpty == false ? trimmedIntent! : "No extra request. Suggest the best fit from the plan.")

        Return a single JSON object with:
        - plan: the workout plan object
        - goalSuggestions: the trackable goals, or an empty array if no goal is good enough
        """
    }

    private func copyWorkoutPlan(_ plan: WorkoutPlan, daysPerWeek: Int) -> WorkoutPlan {
        WorkoutPlan(
            splitType: plan.splitType,
            daysPerWeek: daysPerWeek,
            templates: plan.templates,
            planIntent: plan.planIntent,
            rationale: plan.rationale,
            guidelines: plan.guidelines,
            progressionStrategy: plan.progressionStrategy,
            modalityProgression: plan.modalityProgression,
            warnings: plan.warnings
        )
    }

    // MARK: - Workout Plan Setup Follow-up

    func generateWorkoutPlanFollowUpQuestion(
        request: WorkoutPlanGenerationRequest,
        answeredQuestions: [String]
    ) async throws -> WorkoutPlanFollowUpQuestion {
        try await performAIRequest(for: .workoutPlanRefinement) {
            let workoutTypes = request.selectedWorkoutTypes?
                .map(\.displayName)
                .joined(separator: ", ") ?? request.workoutType.displayName
            let specificGoals = request.specificGoals?.joined(separator: " | ") ?? "None"
            let preferences = request.preferences?.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = request.conversationContext?.joined(separator: " | ") ?? "None"
            let answered = answeredQuestions.isEmpty ? "None" : answeredQuestions.joined(separator: " | ")

            let prompt = """
            You are Trai, a fitness coach inside a workout plan setup flow.

            Choose exactly one follow-up question for a short paid Pro workout plan setup.

            The question should make the resulting workout plan and generated goals materially more personal. It must fill the most important remaining gap from the user's context, not repeat what they already answered. The app may ask up to two adaptive follow-ups, so ask the next highest-value question rather than trying to cover every gap at once.

            Rules:
            - Ask one concise, conversational question.
            - Do not ask a generic "anything else?" question.
            - Do not ask about a strength split unless the user selected strength or clearly mentioned lifting.
            - If the user selected multiple training styles, ask about the tradeoff, priority, or performance goal that matters most.
            - If the user selected strength, useful gaps include target lifts, body parts, split preference, weak points, or aesthetic/performance goals.
            - If the user selected cardio, useful gaps include event/distance/pace, hard/easy rhythm, preferred modalities, or progression tolerance.
            - If the user selected sport or climbing, useful gaps include practice days, performance bottlenecks, recovery interference, or skill goals.
            - If the user selected mobility, useful gaps include painful/tight areas, movement goal, frequency, or whether it supports another sport.
            - Use the user's onboarding, nutrition, memories, existing goals, schedule, equipment, and prior answers.
            - Give 3-5 suggestion chips that are real answers the user could tap. Do not include skip, surprise me, or let Trai choose.
            - Keep chip titles short. The chip text can be more descriptive.

            User context:
            - Name: \(request.name)
            - Primary app goal: \(request.goal.displayName)
            - Activity level: \(request.activityLevel.displayName)
            - Training styles: \(workoutTypes)
            - Schedule: \(request.availableDays.map { "\($0) days/week" } ?? "Flexible")
            - Session length: \(request.timePerWorkout.map { "\($0) min" } ?? "Flexible")
            - Experience: \(request.experienceLevel?.displayName ?? "Not specified")
            - Equipment: \(request.equipmentAccess?.displayName ?? "Not specified")
            - Preferred split: \(request.preferredSplit?.displayName ?? "Not specified")
            - Specific goals: \(specificGoals)
            - Injuries or limitations: \(request.injuries ?? "None")
            - Preferences: \(preferences?.isEmpty == false ? preferences! : "None")
            - Onboarding and known context: \(context)
            - Questions already answered in this setup: \(answered)
            """

            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "question": [
                        "type": "object",
                        "properties": [
                            "prompt": ["type": "string"],
                            "placeholder": [
                                "type": "string",
                                "nullable": true
                            ],
                            "suggestions": [
                                "type": "array",
                                "minItems": 3,
                                "maxItems": 5,
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "title": ["type": "string"],
                                        "text": ["type": "string"]
                                    ],
                                    "required": ["title", "text"]
                                ]
                            ]
                        ],
                        "required": ["prompt", "suggestions"]
                    ]
                ],
                "required": ["question"]
            ]

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: schema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .minimal
                )
            )

            logPrompt(prompt)

            let response = try await makeRequest(request: request)
            logResponse(response)

            guard let data = response.data(using: .utf8) else {
                throw AIServiceError.invalidResponse
            }

            return try JSONDecoder().decode(WorkoutPlanFollowUpQuestionEnvelope.self, from: data).question
        }
    }

    // MARK: - Workout Plan Refinement (Chat)

    /// Refine/discuss the workout plan through chat
    func refineWorkoutPlan(
        currentPlan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest,
        userMessage: String,
        conversationHistory: [WorkoutPlanChatMessage]
    ) async throws -> WorkoutPlanRefinementResponse {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .workoutPlanRefinement) {
            log("💬 Workout plan refinement request: \(userMessage)", type: .info)

            let prompt = AIPromptBuilder.buildWorkoutPlanRefinementPrompt(
                currentPlan: currentPlan,
                request: request,
                userMessage: userMessage,
                conversationHistory: conversationHistory
            )
            logPrompt(prompt)

            do {
                let envelope: PlanPipelineRefinementEnvelope<WorkoutPlan> = try await executePlanRefinementPipeline(
                    prompt: prompt,
                    schema: AIPromptBuilder.workoutPlanRefinementSchema
                )

                let responseType = WorkoutPlanRefinementResponse.ResponseType(rawValue: envelope.responseType) ?? .message
                let proposedPlan = envelope.proposedPlan.flatMap(validatedRefinedWorkoutPlan)
                let updatedPlan = envelope.updatedPlan.flatMap(validatedRefinedWorkoutPlan)
                return WorkoutPlanRefinementResponse(
                    responseType: responseType,
                    message: envelope.message,
                    proposedPlan: proposedPlan,
                    updatedPlan: updatedPlan
                )
            } catch {
                log("Failed to refine workout plan: \(error.localizedDescription)", type: .error)
                throw error
            }
        }
    }

    private func validatedRefinedWorkoutPlan(_ plan: WorkoutPlan) -> WorkoutPlan? {
        guard !plan.templates.isEmpty,
              plan.planIntent != nil,
              plan.modalityProgression != nil,
              plan.templates.allSatisfy({ !$0.blocks.isEmpty }) else {
            log("Ignoring workout plan refinement that dropped explicit plan structure.", type: .error)
            return nil
        }

        if plan.daysPerWeek != plan.templates.count {
            return copyWorkoutPlan(plan, daysPerWeek: plan.templates.count)
        }

        return plan
    }
}

private extension WorkoutPlan.WorkoutTemplate {
    var cardioSupportBlockCount: Int {
        displayBlocks.filter { block in
            switch block.kind {
            case .cardioFinisher:
                return true
            case .cardio, .conditioning:
                let text = [block.title, block.detail, block.notes ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                return text.contains("finisher") || text.contains("accessory") || text.contains("support")
            case .warmup, .strength, .skill, .mobility, .recovery, .sportPractice, .cooldown, .custom:
                return false
            }
        }
        .count
    }

    var isStandaloneCardioTemplate: Bool {
        if sessionType == .cardio || sessionType == .hiit {
            return true
        }

        if displayBlocks.count == 1,
           let onlyBlock = displayBlocks.first,
           onlyBlock.kind == .cardio || onlyBlock.kind == .conditioning {
            return true
        }

        let text = ([name, notes ?? ""] + focusAreas)
            .joined(separator: " ")
            .lowercased()

        return text.contains("cardio day") ||
            text.contains("running day") ||
            text.contains("cycling day") ||
            text.contains("endurance day")
    }
}
