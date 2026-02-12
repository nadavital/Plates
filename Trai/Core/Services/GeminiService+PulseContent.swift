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
            contextPacket: nil
        )

        let packet = TraiPulseContextAssembler.assemble(
            patternProfile: request.context.patternProfile ?? .empty,
            activeSignals: activeSnapshots,
            context: baseInput,
            tokenBudget: 560
        )

        let recentAnswer = TraiPulseResponseInterpreter.recentPulseAnswer(from: activeSnapshots, now: now)
        let workoutName = request.context.recommendedWorkoutName ?? "recommended workout"

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
        - log_food

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
        - allow_question: \(request.allowQuestion)
        - blocked_question_id: \(request.blockedQuestionID ?? "")
        - recent_answer: \(recentAnswer?.answer ?? "")
        - recent_question_id: \(recentAnswer?.questionID ?? "")

        COMPACT STATE PACKET:
        \(packet.promptSummary)

        Additional rules:
        - If context implies user is done eating tonight, avoid food logging prompts for tonight.
        - Avoid repeating the same plan change recommendation every day.
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
        default:
            throw GeminiError.parsingError
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = payload.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw GeminiError.parsingError }

        return DailyCoachAction(
            kind: kind,
            title: title,
            subtitle: subtitle?.isEmpty == true ? nil : subtitle
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
                                    "enum": ["start_workout", "log_food"]
                                ],
                                "title": ["type": "string"],
                                "subtitle": ["type": "string"]
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
