//
//  GeminiService+PulseContent.swift
//  Trai
//
//  Model-managed Pulse content generation (no deterministic recommendation fallback).
//

import Foundation

extension GeminiService {
    struct PulseContentRequest: Sendable {
        let context: DailyCoachContext
        let preferences: DailyCoachPreferences
        let tone: TraiCoachTone
        let allowQuestion: Bool
        let blockedQuestionID: String?
    }

    private struct PulseModelPayload: Decodable {
        struct PromptPayload: Decodable {
            struct QuestionPayload: Decodable {
                let id: String
                let prompt: String
                let mode: String
                let options: [String]?
                let placeholder: String?
                let isRequired: Bool?
                let sliderMin: Double?
                let sliderMax: Double?
                let sliderStep: Double?
                let sliderUnit: String?
            }

            struct ActionPayload: Decodable {
                let kind: String
                let title: String
                let subtitle: String?
                let metadata: [String: String]?
            }

            struct PlanProposalPayload: Decodable {
                let id: String
                let title: String
                let rationale: String
                let impact: String
                let changes: [String]
                let applyLabel: String?
                let reviewLabel: String?
                let deferLabel: String?
            }

            let kind: String
            let question: QuestionPayload?
            let action: ActionPayload?
            let planProposal: PlanProposalPayload?
        }

        let surfaceType: String?
        let title: String
        let message: String
        let prompt: PromptPayload?
    }

    func generatePulseContent(_ request: PulseContentRequest) async throws -> TraiPulseContentSnapshot {
        let calendar = Calendar.current
        let now = request.context.now
        let hour = calendar.component(.hour, from: now)
        let reminderCompletionRate = request.context.reminderCompletionRate
        let missedReminderCount = request.context.recentMissedReminderCount
        let daysSinceWeightLog = request.context.daysSinceLastWeightLog
        let weightLoggedThisWeek = request.context.weightLoggedThisWeek
        let weightLoggedThisWeekDays = request.context.weightLoggedThisWeekDays
        let weightLikelyLogTimes = request.context.weightLikelyLogTimes
        let todaysExerciseMinutes = request.context.todaysExerciseMinutes
        let lastActiveWorkoutHour = request.context.lastActiveWorkoutHour
        let likelyReminderTimes = request.context.likelyReminderTimes

        let activeSnapshots = request.context.activeSignals.activeSnapshots(now: now)

        let window = request.preferences.workoutWindow.hours
        let baseInput = TraiPulseInputContext(
            now: now,
            hasWorkoutToday: request.context.hasWorkoutToday,
            hasActiveWorkout: request.context.hasActiveWorkout,
            caloriesConsumed: request.context.caloriesConsumed,
            calorieGoal: request.context.calorieGoal,
            proteinConsumed: request.context.proteinConsumed,
            proteinGoal: request.context.proteinGoal,
            readyMuscleCount: request.context.readyMuscleCount,
            recommendedWorkoutName: request.context.recommendedWorkoutName,
            workoutWindowStartHour: window.start,
            workoutWindowEndHour: window.end,
            activeSignals: activeSnapshots,
            tomorrowWorkoutMinutes: request.preferences.tomorrowWorkoutMinutes,
            trend: request.context.trend,
            patternProfile: request.context.patternProfile,
            reminderCompletionRate: reminderCompletionRate,
            recentMissedReminderCount: missedReminderCount,
            daysSinceLastWeightLog: daysSinceWeightLog,
            weightLoggedThisWeek: weightLoggedThisWeek,
            weightLoggedThisWeekDays: weightLoggedThisWeekDays,
            weightLikelyLogTimes: weightLikelyLogTimes,
            weightRecentRangeKg: request.context.weightRecentRangeKg,
            weightLogRoutineScore: request.context.weightLogRoutineScore,
            todaysExerciseMinutes: todaysExerciseMinutes,
            lastActiveWorkoutHour: lastActiveWorkoutHour,
            likelyReminderTimes: likelyReminderTimes,
            pendingReminderCandidates: request.context.pendingReminderCandidates,
            pendingReminderCandidateScores: request.context.pendingReminderCandidateScores,
            contextPacket: nil
        )

        let packet = TraiPulseContextAssembler.assemble(
            patternProfile: request.context.patternProfile ?? .empty,
            activeSignals: activeSnapshots,
            context: baseInput,
            tokenBudget: 560
        )

        let recentAnswer = TraiPulseResponseInterpreter.recentPulseAnswer(from: activeSnapshots, now: now)
        let weightLogRoutineScore = request.context.weightLogRoutineScore
        let pendingReminderCandidates = request.context.pendingReminderCandidates
        let pendingReminderPromptValue = pendingReminderCandidates.isEmpty
            ? "none"
            : pendingReminderCandidates
                .prefix(6)
                .map { "\($0.title) at \($0.time) [id:\($0.id)]" }
                .joined(separator: "; ")
        let pendingReminderPriorityValue = pendingReminderCandidates.isEmpty
            ? "none"
            : pendingReminderCandidates
                .prefix(6)
                .map {
                    let score = request.context.pendingReminderCandidateScores[$0.id]
                    let title = $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let weight = String(format: "%.2f", score ?? 0.0)
                    return "\(title) at \($0.time) [id:\($0.id)] [score:\(weight)]"
                }
                .joined(separator: "; ")
        let likelyWorkoutTimes = request.context.likelyWorkoutTimes
            .isEmpty ? "none" : request.context.likelyWorkoutTimes.joined(separator: ", ")
        let weightRecentRangeKg = request.context.weightRecentRangeKg.map { String(format: "%.1f", $0) } ?? "none"
        let workoutName = request.context.recommendedWorkoutName ?? "recommended workout"
        let currentWeekday = weekdayName(for: calendar.component(.weekday, from: now))
        let hasMorningWeightWindow = weightLikelyLogTimes.contains {
            $0.localizedStandardContains("Morning (4-9 AM)") ||
            $0.localizedStandardContains("Late Morning (9-12 PM)")
        }
        let isUsualWeightLogDay = weightLoggedThisWeekDays.contains(currentWeekday)
        let hasWorkoutCheckInSignal = activeSnapshots.contains {
            $0.source == .workoutCheckIn &&
            calendar.isDate($0.createdAt, inSameDayAs: now)
        }
        let answeredPostWorkoutQuestion = activeSnapshots.contains {
            $0.source == .dashboardNote &&
            $0.detail.contains("[PulseQuestion:readiness-post-workout]") &&
            calendar.isDate($0.createdAt, inSameDayAs: now)
        }
        let shouldPrioritizeWeightLogNow: Bool = {
            guard let daysSinceWeightLog else { return false }
            if daysSinceWeightLog <= 0 { return false }
            if !(4..<12).contains(hour) { return false }
            if hasMorningWeightWindow || isUsualWeightLogDay { return true }
            return weightLogRoutineScore >= 0.42
        }()
        let rankedActions = TraiPulseActionRanker.rankActions(context: request.context, now: now, limit: 4)
        let deterministicActionLine = rankedActions.isEmpty
            ? "none"
            : rankedActions
                .map { action in
                    let score = String(format: "%.2f", action.score)
                    return "\(modelActionKind(for: action.action.kind))[\(score)]"
                }
                .joined(separator: ", ")
        let deterministicTopAction = rankedActions.first.map { modelActionKind(for: $0.action.kind) } ?? "none"
        let deterministicTopScore = rankedActions.first.map { String(format: "%.2f", $0.score) } ?? "0.00"

        let prompt = """
        You are generating content for a fitness app dashboard surface called Trai Pulse.

        IMPORTANT OUTPUT STYLE:
        - This is NOT a conversation.
        - Write like a concise coach note shown at the top of home.
        - Never use chat acknowledgements like "Got it", "You said", "Thanks", "I can".
        - Avoid first-person conversational phrasing.
        - Tone profile: \(request.tone.rawValue)
        - \(request.tone.pulseStylePrompt)
        - Use positive framing; avoid scolding, guilt, or alarmist phrasing.
        - Prefer practical language and one clear next step when relevant.
        - Keep message compact and useful.

        SURFACE RULES:
        - Return JSON only.
        - Produce one main message and at most one prompt.
        - It is valid to return no prompt when there is no high-confidence action or question.
        - Prompt can be either:
          1) one actionable suggestion (`kind=action`), or
          2) one context question (`kind=question`), or
          3) one plan adjustment proposal (`kind=plan_proposal`), or
          4) none.
        - Do not include more than one prompt type.
        - If `allow_question` is false, do not output a question prompt.
        - If blocked_question_id is present, do not reuse that id.
        - Keep title <= 6 words, message <= 26 words.
        - Set `surfaceType` to one of: coach_note, quick_checkin, recovery_probe, timing_nudge, plan_proposal.

        ACTION KIND ENUM:
        - start_workout
        - start_workout_template
        - log_food
        - log_food_camera
        - log_weight
        - open_weight
        - open_calorie_detail
        - open_macro_detail
        - open_profile
        - open_workouts
        - open_workout_plan
        - open_recovery
        - review_nutrition_plan
        - review_workout_plan
        - complete_reminder
        - Do not propose chat-like actions.

        For start_workout_template, use `metadata.template_id` (UUID string) when known, otherwise `metadata.template_name`.
        For complete_reminder, include `reminder_id` (UUID string), and optionally:
        - `reminder_title` (exact reminder label if useful),
        - `reminder_time` (same format as reminder card),
        - `reminder_hour`,
        - `reminder_minute`.
        - If there is more than one pending reminder, always include `reminder_id` and match one exact item.
        - If no valid pending reminder can be identified, return `none` rather than a generic complete reminder.

        QUESTION MODE ENUM:
        - single_choice
        - multiple_choice
        - slider
        - note

        For slider mode include sliderMin, sliderMax, sliderStep, optional sliderUnit.
        For note mode keep options empty.
        For single/multiple choice provide 2-4 options.

        PLAN PROPOSAL RULES:
        - Use plan_proposal only when there is meaningful multi-day trend evidence.
        - Proposal must be cautious and non-destructive.
        - Never imply automatic plan change.
        - Include a compact list of concrete changes in `changes`.

        USER CONTEXT:
        - hour_of_day: \(hour)
        - coach_tone: \(request.tone.rawValue)
        - effort_mode: \(request.preferences.effortMode.rawValue)
        - tomorrow_focus: \(request.preferences.tomorrowFocus.rawValue)
        - preferred_workout_window: \(request.preferences.workoutWindow.rawValue)
        - recommended_workout: \(workoutName)
        - has_workout_today: \(request.context.hasWorkoutToday)
        - has_active_workout: \(request.context.hasActiveWorkout)
        - calories_today: \(request.context.caloriesConsumed)
        - calorie_goal: \(request.context.calorieGoal)
        - protein_today: \(request.context.proteinConsumed)
        - protein_goal: \(request.context.proteinGoal)
        - ready_muscle_count: \(request.context.readyMuscleCount)
        - reminder_completion_rate: \(reminderCompletionRate == nil ? "unknown" : String(format: "%.2f", reminderCompletionRate!))
        - missed_reminders_today: \(missedReminderCount == nil ? "unknown" : String(missedReminderCount!))
        - days_since_weight_log: \(daysSinceWeightLog == nil ? "unknown" : String(daysSinceWeightLog!))
        - weight_logged_this_week: \(weightLoggedThisWeek == nil ? "unknown" : (weightLoggedThisWeek! ? "true" : "false"))
        - weight_log_weekdays: \(weightLoggedThisWeekDays.isEmpty ? "unknown" : weightLoggedThisWeekDays.joined(separator: ", "))
        - weight_log_times: \(weightLikelyLogTimes.isEmpty ? "unknown" : weightLikelyLogTimes.joined(separator: ", "))
        - weight_log_routine_score: \(String(format: "%.2f", weightLogRoutineScore))
        - is_usual_weight_log_day: \(isUsualWeightLogDay)
        - has_morning_weight_log_window: \(hasMorningWeightWindow)
        - should_prioritize_weight_log_now: \(shouldPrioritizeWeightLogNow)
        - plan_review_trigger: \(request.context.planReviewTrigger ?? "none")
        - plan_review_message: \(request.context.planReviewMessage ?? "none")
        - plan_review_days_since: \(request.context.planReviewDaysSince == nil ? "none" : String(request.context.planReviewDaysSince!))
        - plan_review_weight_delta_kg: \(request.context.planReviewWeightDeltaKg == nil ? "none" : String(request.context.planReviewWeightDeltaKg!))
        - todays_exercise_minutes: \(todaysExerciseMinutes == nil ? "unknown" : String(todaysExerciseMinutes!))
        - last_active_workout_hour: \(lastActiveWorkoutHour == nil ? "unknown" : String(lastActiveWorkoutHour!))
        - has_workout_checkin_signal_today: \(hasWorkoutCheckInSignal)
        - answered_post_workout_question_today: \(answeredPostWorkoutQuestion)
        - likely_reminder_times: \(likelyReminderTimes.isEmpty ? "none" : likelyReminderTimes.joined(separator: ", "))
        - likely_workout_times: \(likelyWorkoutTimes.isEmpty ? "none" : likelyWorkoutTimes)
        - deterministic_action_candidates: \(deterministicActionLine)
        - deterministic_top_action: \(deterministicTopAction)
        - deterministic_top_action_score: \(deterministicTopScore)
        - recent_weight_range_kg: \(weightRecentRangeKg)
        - pending_reminders: \(pendingReminderPromptValue)
        - pending_reminder_priorities: \(pendingReminderPriorityValue)
        - allow_question: \(request.allowQuestion)
        - blocked_question_id: \(request.blockedQuestionID ?? "")
        - recent_answer: \(recentAnswer?.answer ?? "")
        - recent_question_id: \(recentAnswer?.questionID ?? "")

        COMPACT STATE PACKET:
        \(packet.promptSummary)

        Additional rules:
        - If context implies user is done eating tonight, avoid food logging prompts for tonight.
        - Avoid repeating the same plan change recommendation every day.
        - If should_prioritize_weight_log_now is true, strongly prefer `log_weight` or `open_weight` over workout-start actions.
        - If has_workout_today is true, has_active_workout is false, allow_question is true, and no workout check-in has been captured today, prefer a short workout follow-up question before suggesting another workout start.
        - If deterministic_top_action_score >= 0.78, prefer that action unless there is a stronger safety/context reason not to.
        """

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .low,
                jsonSchema: Self.pulseContentSchema
            )
        ]

        let responseText = try await makeRequest(body: requestBody)
        let cleanText = cleanJSONResponse(responseText)

        guard let data = cleanText.data(using: .utf8) else {
            throw GeminiError.parsingError
        }

        let payload = try JSONDecoder().decode(PulseModelPayload.self, from: data)
        let snapshot = try mapPulsePayload(payload)
        return TraiPulsePolicyEngine.apply(snapshot, request: request, now: now)
    }

    private func mapPulsePayload(_ payload: PulseModelPayload) throws -> TraiPulseContentSnapshot {
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = payload.message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !message.isEmpty else {
            throw GeminiError.parsingError
        }

        let prompt: TraiPulseContentPrompt?
        if let promptPayload = payload.prompt {
            switch promptPayload.kind {
            case "none":
                prompt = nil
            case "action":
                guard let action = promptPayload.action else { throw GeminiError.parsingError }
                prompt = .action(try mapAction(action))
            case "question":
                guard let question = promptPayload.question else { throw GeminiError.parsingError }
                prompt = .question(try mapQuestion(question))
            case "plan_proposal":
                guard let proposal = promptPayload.planProposal else { throw GeminiError.parsingError }
                prompt = .planProposal(try mapPlanProposal(proposal))
            default:
                throw GeminiError.parsingError
            }
        } else {
            prompt = nil
        }

        let surfaceType = mapSurfaceType(rawValue: payload.surfaceType, prompt: prompt)

        return TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: surfaceType,
            title: title,
            message: message,
            prompt: prompt
        )
    }

    private func mapAction(_ payload: PulseModelPayload.PromptPayload.ActionPayload) throws -> DailyCoachAction {
        let kind: DailyCoachAction.Kind
        switch payload.kind {
        case "start_workout":
            kind = .startWorkout
        case "log_food":
            kind = .logFood
        case "start_workout_template":
            kind = .startWorkoutTemplate
        case "log_food_camera":
            kind = .logFoodCamera
        case "log_weight":
            kind = .logWeight
        case "open_weight":
            kind = .openWeight
        case "open_calorie_detail":
            kind = .openCalorieDetail
        case "open_macro_detail":
            kind = .openMacroDetail
        case "open_profile":
            kind = .openProfile
        case "open_workouts":
            kind = .openWorkouts
        case "open_workout_plan":
            kind = .openWorkoutPlan
        case "open_recovery":
            kind = .openRecovery
        case "review_nutrition_plan":
            kind = .reviewNutritionPlan
        case "review_workout_plan":
            kind = .reviewWorkoutPlan
        case "complete_reminder":
            kind = .completeReminder
        default:
            throw GeminiError.parsingError
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = payload.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = payload.metadata?.reduce(into: [String: String]()) { partial, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                partial[key] = value
            }
        }
        guard !title.isEmpty else { throw GeminiError.parsingError }

        return DailyCoachAction(
            kind: kind,
            title: title,
            subtitle: subtitle?.isEmpty == true ? nil : subtitle,
            metadata: (metadata?.isEmpty ?? true) ? nil : metadata
        )
    }

    private func mapQuestion(_ payload: PulseModelPayload.PromptPayload.QuestionPayload) throws -> TraiPulseQuestion {
        let mode: TraiPulseQuestionInputMode
        let questionID = payload.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let questionPrompt = payload.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = (payload.placeholder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawOptions = (payload.options ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let options = rawOptions.map { TraiPulseQuestionOption(title: $0) }

        guard !questionID.isEmpty, !questionPrompt.isEmpty else {
            throw GeminiError.parsingError
        }

        switch payload.mode {
        case "single_choice":
            guard options.count >= 2 else { throw GeminiError.parsingError }
            mode = .singleChoice
        case "multiple_choice":
            guard options.count >= 2 else { throw GeminiError.parsingError }
            mode = .multipleChoice
        case "slider":
            guard
                let minValue = payload.sliderMin,
                let maxValue = payload.sliderMax,
                let step = payload.sliderStep,
                maxValue > minValue,
                step > 0
            else {
                throw GeminiError.parsingError
            }
            mode = .slider(range: minValue...maxValue, step: step, unit: payload.sliderUnit?.trimmingCharacters(in: .whitespacesAndNewlines))
        case "note":
            guard options.isEmpty else { throw GeminiError.parsingError }
            mode = .note(maxLength: 180)
        default:
            throw GeminiError.parsingError
        }

        return TraiPulseQuestion(
            id: questionID,
            prompt: questionPrompt,
            mode: mode,
            options: options,
            placeholder: placeholder,
            isRequired: payload.isRequired ?? false
        )
    }

    private func mapPlanProposal(_ payload: PulseModelPayload.PromptPayload.PlanProposalPayload) throws -> TraiPulsePlanProposal {
        let id = payload.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rationale = payload.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        let impact = payload.impact.trimmingCharacters(in: .whitespacesAndNewlines)
        let changes = payload.changes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let applyLabel = (payload.applyLabel ?? "Apply with review").trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewLabel = (payload.reviewLabel ?? "Review in Trai").trimmingCharacters(in: .whitespacesAndNewlines)
        let deferLabel = (payload.deferLabel ?? "Not now").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !id.isEmpty, !title.isEmpty, !rationale.isEmpty, !impact.isEmpty, !changes.isEmpty else {
            throw GeminiError.parsingError
        }

        return TraiPulsePlanProposal(
            id: id,
            title: title,
            rationale: rationale,
            impact: impact,
            changes: Array(changes.prefix(3)),
            applyLabel: applyLabel.isEmpty ? "Apply with review" : applyLabel,
            reviewLabel: reviewLabel.isEmpty ? "Review in Trai" : reviewLabel,
            deferLabel: deferLabel.isEmpty ? "Not now" : deferLabel
        )
    }

    private func mapSurfaceType(rawValue: String?, prompt: TraiPulseContentPrompt?) -> TraiPulseSurfaceType {
        if let rawValue, let mapped = TraiPulseSurfaceType(rawValue: rawValue) {
            return mapped
        }

        switch prompt {
        case .some(.planProposal):
            return .planProposal
        case .some(.question(let question)):
            switch question.mode {
            case .slider:
                return .recoveryProbe
            case .singleChoice, .multipleChoice, .note:
                return .quickCheckin
            }
        case .some(.action):
            return .coachNote
        case .none:
            return .coachNote
        }
    }

    private func weekdayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Unknown"
        }
    }

    private func modelActionKind(for kind: DailyCoachAction.Kind) -> String {
        switch kind {
        case .startWorkout:
            return "start_workout"
        case .startWorkoutTemplate:
            return "start_workout_template"
        case .logFood:
            return "log_food"
        case .logFoodCamera:
            return "log_food_camera"
        case .logWeight:
            return "log_weight"
        case .openWeight:
            return "open_weight"
        case .openCalorieDetail:
            return "open_calorie_detail"
        case .openMacroDetail:
            return "open_macro_detail"
        case .openProfile:
            return "open_profile"
        case .openWorkouts:
            return "open_workouts"
        case .openWorkoutPlan:
            return "open_workout_plan"
        case .openRecovery:
            return "open_recovery"
        case .reviewNutritionPlan:
            return "review_nutrition_plan"
        case .reviewWorkoutPlan:
            return "review_workout_plan"
        case .completeReminder:
            return "complete_reminder"
        }
    }

    private static var pulseContentSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "surfaceType": [
                    "type": "string",
                    "enum": ["coach_note", "quick_checkin", "recovery_probe", "timing_nudge", "plan_proposal"]
                ],
                "title": ["type": "string"],
                "message": ["type": "string"],
                "prompt": [
                    "type": "object",
                    "nullable": true,
                    "properties": [
                        "kind": [
                            "type": "string",
                            "enum": ["question", "action", "plan_proposal", "none"]
                        ],
                        "question": [
                            "type": "object",
                            "nullable": true,
                            "properties": [
                                "id": ["type": "string"],
                                "prompt": ["type": "string"],
                                "mode": [
                                    "type": "string",
                                    "enum": ["single_choice", "multiple_choice", "slider", "note"]
                                ],
                                "options": [
                                    "type": "array",
                                    "items": ["type": "string"]
                                ],
                                "placeholder": ["type": "string"],
                                "isRequired": ["type": "boolean"],
                                "sliderMin": ["type": "number"],
                                "sliderMax": ["type": "number"],
                                "sliderStep": ["type": "number"],
                                "sliderUnit": ["type": "string"]
                            ],
                            "required": ["id", "prompt", "mode"]
                        ],
                        "action": [
                            "type": "object",
                            "nullable": true,
                            "properties": [
                                "kind": [
                                    "type": "string",
                                    "enum": [
                                "start_workout",
                                "start_workout_template",
                                "log_food",
                                "log_food_camera",
                                "log_weight",
                                "open_weight",
                                "open_calorie_detail",
                                "open_macro_detail",
                                "open_profile",
                                "open_workouts",
                                "open_workout_plan",
                                        "open_recovery",
                                        "review_nutrition_plan",
                                        "review_workout_plan",
                                        "complete_reminder"
                                    ]
                                ],
                                "title": ["type": "string"],
                                "subtitle": ["type": "string"],
                                "metadata": [
                                    "type": "object",
                                    "nullable": true,
                                    "properties": [
                                        "template_id": ["type": "string"],
                                        "template_name": ["type": "string"],
                                        "reminder_id": ["type": "string"],
                                        "reminder_title": ["type": "string"],
                                        "reminder_time": ["type": "string"],
                                        "reminder_hour": ["type": "string"],
                                        "reminder_minute": ["type": "string"]
                                    ]
                                ]
                            ],
                            "required": ["kind", "title"]
                        ],
                        "planProposal": [
                            "type": "object",
                            "nullable": true,
                            "properties": [
                                "id": ["type": "string"],
                                "title": ["type": "string"],
                                "rationale": ["type": "string"],
                                "impact": ["type": "string"],
                                "changes": [
                                    "type": "array",
                                    "items": ["type": "string"]
                                ],
                                "applyLabel": ["type": "string"],
                                "reviewLabel": ["type": "string"],
                                "deferLabel": ["type": "string"]
                            ],
                            "required": ["id", "title", "rationale", "impact", "changes"]
                        ]
                    ],
                    "required": ["kind"]
                ]
            ],
            "required": ["title", "message"]
        ]
    }
}
