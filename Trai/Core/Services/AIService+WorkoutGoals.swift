//
//  AIService+WorkoutGoals.swift
//  Trai
//

import Foundation

struct WorkoutGoalSuggestion: Codable, Identifiable, Sendable {
    let title: String
    let rationale: String
    let goalKindRaw: String
    let linkedWorkoutTypeRaw: String?
    let linkedActivityName: String?
    let targetValue: Double?
    let targetUnit: String?
    let periodUnitRaw: String?
    let periodCount: Int?
    let notes: String?
    let targetDateISO8601: String?
    let checkInCadenceDays: Int?

    var id: String {
        [
            title,
            goalKindRaw,
            linkedWorkoutTypeRaw ?? "",
            linkedActivityName ?? ""
        ].joined(separator: "|")
    }

    var goalKind: WorkoutGoal.GoalKind {
        WorkoutGoal.GoalKind(rawValue: goalKindRaw) ?? .milestone
    }

    var linkedWorkoutType: WorkoutMode? {
        linkedWorkoutTypeRaw.flatMap(WorkoutMode.init(rawValue:))
    }

    var periodUnit: WorkoutGoal.PeriodUnit? {
        periodUnitRaw.flatMap(WorkoutGoal.PeriodUnit.init(rawValue:))
    }

    var targetDate: Date? {
        guard let targetDateISO8601, !targetDateISO8601.isEmpty else { return nil }
        if let isoDate = ISO8601DateFormatter().date(from: targetDateISO8601) {
            return isoDate
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: targetDateISO8601)
    }

    func asWorkoutGoal() -> WorkoutGoal {
        WorkoutGoal(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            goalKind: goalKind,
            linkedWorkoutType: linkedWorkoutType,
            linkedActivityName: linkedActivityName?.trimmingCharacters(in: .whitespacesAndNewlines),
            targetValue: goalKind.supportsNumericTarget ? targetValue : nil,
            targetUnit: goalKind.supportsNumericTarget ? (targetUnit ?? "") : "",
            periodUnit: goalKind.usesPeriodTarget ? periodUnit : nil,
            periodCount: goalKind.usesPeriodTarget ? periodCount : nil,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rationale,
            targetDate: targetDate,
            checkInCadenceDays: checkInCadenceDays
        )
    }
}

private struct WorkoutGoalSuggestionResponse: Codable {
    let suggestions: [WorkoutGoalSuggestion]
}

struct WorkoutGoalRecommendationContextBuilder {
    static func recentSessionSummaries(
        workouts: [LiveWorkout],
        sessions: [WorkoutSession]
    ) -> [String] {
        let live = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .prefix(4)
            .map { workout in
                let detail = [workout.type.displayName, workout.displayFocusSummary, workout.formattedDuration]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                return "\(workout.name) (\(detail))"
            }

        let imported = sessions
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(4)
            .map { session in
                let detail = [session.inferredWorkoutMode.displayName, session.formattedDuration, session.formattedDistance]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                return "\(session.displayName) (\(detail))"
            }

        return Array((live + imported).prefix(6))
    }

    static func recentTrainingSummary(
        workouts: [LiveWorkout],
        sessions: [WorkoutSession],
        now: Date = Date()
    ) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? .distantPast

        let liveModes = workouts
            .filter { ($0.completedAt ?? $0.startedAt) >= cutoff }
            .map(\.type)

        let sessionModes = sessions
            .filter { $0.loggedAt >= cutoff }
            .map(\.inferredWorkoutMode)

        let modeCounts = Dictionary((liveModes + sessionModes).map { ($0, 1) }, uniquingKeysWith: +)
        let modeLines = modeCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.displayName < rhs.key.displayName
            }
            .prefix(4)
            .map { mode, count in
                "\(mode.displayName): \(count) session\(count == 1 ? "" : "s") in the last 30 days"
            }

        let liveActivityTokens = workouts
            .filter { ($0.completedAt ?? $0.startedAt) >= cutoff }
            .flatMap { workout in
                let focus = workout.focusAreas.map(\.goalNormalizedKey)
                return focus.isEmpty ? [workout.name.goalNormalizedKey] : focus
            }

        let sessionActivityTokens = sessions
            .filter { $0.loggedAt >= cutoff }
            .flatMap { session in
                let tokens = Array(session.goalMatchingTokens)
                return tokens.isEmpty ? [session.displayName.goalNormalizedKey] : tokens
            }

        let activityCounts = Dictionary((liveActivityTokens + sessionActivityTokens).map { ($0, 1) }, uniquingKeysWith: +)
        let activityLines = activityCounts
            .filter { !$0.key.isEmpty }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .prefix(3)
            .map { activity, count in
                "Recurring focus: \(activity.capitalized) (\(count)x)"
            }

        return modeLines + activityLines
    }

    static func exerciseSummaries(
        history: [ExerciseHistory],
        prefersMetricWeight: Bool
    ) -> [String] {
        let snapshots = ExercisePerformanceService.snapshots(from: history)

        return snapshots.values
            .sorted { lhs, rhs in
                if lhs.totalSessions != rhs.totalSessions {
                    return lhs.totalSessions > rhs.totalSessions
                }
                return lhs.exerciseName < rhs.exerciseName
            }
            .prefix(10)
            .map { snapshot in
                var parts: [String] = ["\(snapshot.exerciseName): \(snapshot.totalSessions) sessions"]

                if let lastSession = snapshot.lastSession {
                    parts.append("last \(lastSession.formattedDate)")
                }

                if let weightPR = snapshot.weightPR {
                    parts.append("best \(weightPR.formattedWeight(usesMetric: prefersMetricWeight)) x \(weightPR.bestSetReps)")
                } else if let repsPR = snapshot.repsPR {
                    parts.append("best \(repsPR.bestSetReps) reps")
                }

                if let estimatedOneRepMax = snapshot.estimatedOneRepMax, estimatedOneRepMax > 0 {
                    let oneRMText = prefersMetricWeight
                        ? "\(Int(estimatedOneRepMax.rounded())) kg est 1RM"
                        : "\(Int((estimatedOneRepMax * WeightUtility.kgToLbs).rounded())) lbs est 1RM"
                    parts.append(oneRMText)
                }

                return parts.joined(separator: " • ")
            }
    }
}

extension AIService {
    func suggestWorkoutGoals(
        userGoal: String?,
        plannedSessions: [String],
        recentSessions: [String],
        recentTrainingSummary: [String],
        exerciseSummaries: [String],
        memoryContext: [String],
        existingGoals: [String],
        userIntent: String?,
        prefersMetricWeight: Bool
    ) async throws -> [WorkoutGoalSuggestion] {
        try await performAIRequest(for: .workoutPlanRefinement) {
            let workoutModes = WorkoutMode.allCases.map(\.rawValue).joined(separator: ", ")
            let contextGoal = userGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedIntent = userIntent?.trimmingCharacters(in: .whitespacesAndNewlines)

            let prompt = """
            You are helping set workout goals inside Trai.

            Create 1-2 workout goals that feel lightweight, motivating, and directly tied to what the user is already doing.

            Rules:
            - Suggest at most 2 goals.
            - Prefer one concrete milestone goal and optionally one consistency or progression goal.
            - Goals should feel meaningful over roughly the next 4-8 weeks unless the user asked for a different timeline.
            - Goals should usually represent something the user works toward over multiple sessions or multiple weeks, not a single routine completion.
            - Do NOT suggest goals like "complete a push day", "finish a cardio workout", or anything that is already normal baseline behavior for a regular trainee.
            - Do NOT suggest maintenance goals like "hold steady" unless the user is explicitly deloading, returning from injury, or asked for maintenance.
            - If the user already does a session type consistently, suggest progression, volume, duration, quality, or milestone goals instead of simple attendance.
            - Use frequency goals when the user's pattern or request is about consistency, e.g. 3 sessions per week.
            - Good examples: "Send the blue V5 clean", "Build up to a 75 minute zone 2 session", "Work back toward 185 lbs for 5 on bench", "Climb 2 times each week for the next month", "Add 10 minutes to your weekly yoga flow sessions without extra breaks".
            - Add a numeric goal only if the recent training data clearly supports it.
            - Do not invent an unrealistic modality or activity.
            - Avoid duplicating any existing goal.
            - If the user gave a specific ask, prioritize that.
            - If the context is thin, prefer a broader but still meaningful goal over a vague or tiny one.
            - If an exercise clearly appears as a recurring anchor movement in the history, it is okay to recommend an exercise-specific goal tied to linkedActivityName.
            - Use linkedWorkoutType when the goal is broad to a session type.
            - Use linkedActivityName when the goal is tied to a specific exercise or activity like a route, lift, or interval format.
            - linkedWorkoutType must be one of: \(workoutModes)
            - goalKind must be one of: milestone, frequency, duration, distance, weight
            - For milestone goals, leave targetValue and targetUnit empty.
            - For frequency goals, targetValue should be the count, targetUnit should usually be "sessions", and periodUnitRaw should be day, week, or month.
            - When it helps, include a soft targetDateISO8601 roughly 4-8 weeks out.
            - checkInCadenceDays can be provided for more open-ended goals that should be revisited.
            - For weight goals, use \(prefersMetricWeight ? "kg by default" : "lbs by default") unless the user context clearly suggests the other unit.
            - Keep titles short and natural, like something a coach would suggest in the app.
            - rationale should explain why the goal fits.
            - notes should be optional and concise.

            User context:
            - Primary fitness goal: \(contextGoal?.isEmpty == false ? contextGoal! : "Not specified")
            - Current plan sessions: \(plannedSessions.isEmpty ? "None" : plannedSessions.joined(separator: " | "))
            - Recent sessions: \(recentSessions.isEmpty ? "None" : recentSessions.joined(separator: " | "))
            - Recent training summary: \(recentTrainingSummary.isEmpty ? "None" : recentTrainingSummary.joined(separator: " | "))
            - Exercise summaries: \(exerciseSummaries.isEmpty ? "None" : exerciseSummaries.joined(separator: " | "))
            - Relevant memory/context: \(memoryContext.isEmpty ? "None" : memoryContext.joined(separator: " | "))
            - Existing workout goals: \(existingGoals.isEmpty ? "None" : existingGoals.joined(separator: " | "))
            - User request: \(trimmedIntent?.isEmpty == false ? trimmedIntent! : "No extra request. Suggest the best fit from context.")
            """

            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "suggestions": [
                        "type": "array",
                        "maxItems": 2,
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string"],
                                "rationale": ["type": "string"],
                                "goalKindRaw": [
                                    "type": "string",
                                    "enum": WorkoutGoal.GoalKind.allCases.map(\.rawValue)
                                ],
                                "linkedWorkoutTypeRaw": [
                                    "type": "string",
                                    "enum": WorkoutMode.allCases.map(\.rawValue),
                                    "nullable": true
                                ],
                                "linkedActivityName": [
                                    "type": "string",
                                    "nullable": true
                                ],
                                "targetValue": [
                                    "type": "number",
                                    "nullable": true
                                ],
                                "targetUnit": [
                                    "type": "string",
                                    "nullable": true
                                ],
                                "periodUnitRaw": [
                                    "type": "string",
                                    "enum": WorkoutGoal.PeriodUnit.allCases.map(\.rawValue),
                                    "nullable": true
                                ],
                                "periodCount": [
                                    "type": "integer",
                                    "nullable": true
                                ],
                                "notes": [
                                    "type": "string",
                                    "nullable": true
                                ],
                                "targetDateISO8601": [
                                    "type": "string",
                                    "nullable": true
                                ],
                                "checkInCadenceDays": [
                                    "type": "integer",
                                    "nullable": true
                                ]
                            ],
                            "required": ["title", "rationale", "goalKindRaw"]
                        ]
                    ]
                ],
                "required": ["suggestions"]
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

            return try JSONDecoder().decode(WorkoutGoalSuggestionResponse.self, from: data).suggestions
        }
    }
}
