//
//  TraiPulsePolicyEngine.swift
//  Trai
//
//  Safety rails for model-managed Pulse content.
//

import Foundation

enum TraiPulsePolicyEngine {
    private static let planSuggestionCooldown: TimeInterval = 7 * 24 * 60 * 60
    private static let lastPlanProposalShownKey = "pulse_last_plan_proposal_shown_at"
    private static let postWorkoutQuestionID = "readiness-post-workout"

    static func apply(
        _ snapshot: TraiPulseContentSnapshot,
        request: GeminiService.PulseContentRequest,
        now: Date = .now
    ) -> TraiPulseContentSnapshot {
        var adjusted = snapshot

        if case .some(.action(let action)) = adjusted.prompt,
           let validated = validateCompleteReminderAction(action, context: request.context) {
            adjusted = TraiPulseContentSnapshot(
                source: adjusted.source,
                surfaceType: adjusted.surfaceType,
                title: adjusted.title,
                message: adjusted.message,
                prompt: .action(validated)
            )
        } else if case .some(.action(let action)) = adjusted.prompt,
                  action.kind == .completeReminder {
            adjusted = TraiPulseContentSnapshot(
                source: adjusted.source,
                surfaceType: adjusted.surfaceType,
                title: adjusted.title,
                message: adjusted.message,
                prompt: nil
            )
        }

        if case .some(.planProposal(let proposal)) = adjusted.prompt {
            if !hasPlanProposalEvidence(request.context) {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .quickCheckin,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: .question(planCheckinQuestion(from: proposal))
                )
                return adjusted
            }

            let lastShown = UserDefaults.standard.double(forKey: lastPlanProposalShownKey)
            if lastShown > 0, now.timeIntervalSince1970 - lastShown < planSuggestionCooldown {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .coachNote,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: nil
                )
                return adjusted
            }

            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastPlanProposalShownKey)
        }

        if adjusted.surfaceType == .planProposal, case .some(.planProposal) = adjusted.prompt {
            return adjusted
        }

        if adjusted.surfaceType == .planProposal {
            adjusted = TraiPulseContentSnapshot(
                source: adjusted.source,
                surfaceType: .quickCheckin,
                title: adjusted.title,
                message: adjusted.message,
                prompt: adjusted.prompt
            )
        }

        if shouldInjectPostWorkoutQuestion(request: request, now: now) {
            if case .none = adjusted.prompt {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .quickCheckin,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: .question(postWorkoutFollowupQuestion())
                )
            } else if case .some(.action) = adjusted.prompt {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .quickCheckin,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: .question(postWorkoutFollowupQuestion())
                )
            }
        }

        if shouldPrioritizeMorningWeightLog(request.context, now: now) {
            let weightAction = preferredWeightAction(for: request.context)

            if case .none = adjusted.prompt {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .timingNudge,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: .action(weightAction)
                )
            } else if case .some(.action(let action)) = adjusted.prompt,
                      shouldReplaceActionWithWeight(action.kind) {
                adjusted = TraiPulseContentSnapshot(
                    source: adjusted.source,
                    surfaceType: .timingNudge,
                    title: adjusted.title,
                    message: adjusted.message,
                    prompt: .action(weightAction)
                )
            }
        }

        let ranked = TraiPulseActionRanker.rankActions(context: request.context, now: now, limit: 3)
        adjusted = applyDeterministicActionRanking(
            to: adjusted,
            ranked: ranked
        )
        adjusted = stampActionTelemetry(on: adjusted, ranked: ranked)

        return adjusted
    }

    private static func applyDeterministicActionRanking(
        to snapshot: TraiPulseContentSnapshot,
        ranked: [TraiPulseRankedAction]
    ) -> TraiPulseContentSnapshot {
        guard let top = ranked.first else { return snapshot }

        switch snapshot.prompt {
        case .none:
            guard top.score >= 0.74 else { return snapshot }
            let deterministicAction = withPulseMetadata(
                top.action,
                additions: ["pulse_reco_origin": "deterministic"]
            )
            return TraiPulseContentSnapshot(
                source: snapshot.source,
                surfaceType: preferredSurface(for: deterministicAction.kind),
                title: snapshot.title,
                message: snapshot.message,
                prompt: .action(deterministicAction)
            )
        case .some(.action(let current)):
            let currentScore = TraiPulseActionRanker.score(for: current, in: ranked)
            guard top.action.kind != current.kind else { return snapshot }
            guard top.score >= 0.78 else { return snapshot }
            guard (top.score - currentScore) >= 0.18 else { return snapshot }
            guard canReplaceAction(current, with: top.action) else { return snapshot }
            let deterministicAction = withPulseMetadata(
                top.action,
                additions: ["pulse_reco_origin": "deterministic"]
            )

            return TraiPulseContentSnapshot(
                source: snapshot.source,
                surfaceType: preferredSurface(for: deterministicAction.kind),
                title: snapshot.title,
                message: snapshot.message,
                prompt: .action(deterministicAction)
            )
        case .some(.question), .some(.planProposal):
            return snapshot
        }
    }

    private static func stampActionTelemetry(
        on snapshot: TraiPulseContentSnapshot,
        ranked: [TraiPulseRankedAction]
    ) -> TraiPulseContentSnapshot {
        guard case .some(.action(let action)) = snapshot.prompt else { return snapshot }

        var metadata = action.metadata ?? [:]
        if metadata["pulse_recommendation_id"] == nil {
            metadata["pulse_recommendation_id"] = UUID().uuidString
        }
        metadata["pulse_policy_version"] = "pulse_policy_v2"
        if metadata["pulse_reco_origin"] == nil {
            metadata["pulse_reco_origin"] = "model"
        }
        if let rankIndex = ranked.firstIndex(where: { $0.action.kind == action.kind }) {
            metadata["pulse_rank_position"] = String(rankIndex + 1)
            metadata["pulse_rank_score"] = String(format: "%.2f", ranked[rankIndex].score)
        }
        if metadata["pulse_candidate_set"] == nil {
            let candidateSet = ranked.prefix(3)
                .map { "\($0.action.kind.rawValue):\(String(format: "%.2f", $0.score))" }
                .joined(separator: ",")
            if !candidateSet.isEmpty {
                metadata["pulse_candidate_set"] = candidateSet
            }
        }

        let stamped = DailyCoachAction(
            kind: action.kind,
            title: action.title,
            subtitle: action.subtitle,
            metadata: metadata
        )
        return TraiPulseContentSnapshot(
            source: snapshot.source,
            surfaceType: snapshot.surfaceType,
            title: snapshot.title,
            message: snapshot.message,
            prompt: .action(stamped)
        )
    }

    private static func validateCompleteReminderAction(
        _ action: DailyCoachAction,
        context: DailyCoachContext
    ) -> DailyCoachAction? {
        guard action.kind == .completeReminder else { return action }

        let candidates = context.pendingReminderCandidates
        guard !candidates.isEmpty else { return nil }

        guard let metadata = action.metadata else {
            return candidates.count == 1 ? action : nil
        }

        let candidateIDs = Set(candidates.compactMap { UUID(uuidString: $0.id) })
        if let reminderID = metadata["reminder_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsedID = UUID(uuidString: reminderID),
           candidateIDs.contains(parsedID) {
            return action
        }

        return candidates.count == 1 ? action : nil
    }

    private static func hasPlanProposalEvidence(_ context: DailyCoachContext) -> Bool {
        if let trend = context.trend {
            if trend.lowProteinStreak >= 3 || trend.daysSinceWorkout >= 4 {
                return true
            }
        }

        if context.activeSignals.contains(where: { signal in
            (signal.domain == .pain || signal.domain == .recovery || signal.domain == .nutrition) &&
            signal.severity >= 0.65 &&
            signal.confidence >= 0.6
        }) {
            return true
        }

        return false
    }

    private static func planCheckinQuestion(from proposal: TraiPulsePlanProposal) -> TraiPulseQuestion {
        TraiPulseQuestion(
            id: "plan_checkin_\(proposal.id)",
            prompt: "Should we review your plan this week based on recent trends?",
            mode: .singleChoice,
            options: [
                TraiPulseQuestionOption(title: "Yes, review it"),
                TraiPulseQuestionOption(title: "Not now")
            ],
            placeholder: "Add context",
            isRequired: true
        )
    }

    private static func shouldInjectPostWorkoutQuestion(
        request: GeminiService.PulseContentRequest,
        now: Date
    ) -> Bool {
        guard request.blockedQuestionID != postWorkoutQuestionID else { return false }

        let context = request.context
        guard context.hasWorkoutToday, !context.hasActiveWorkout else { return false }
        if let lastWorkoutAt = context.lastActiveWorkoutAt {
            let elapsed = now.timeIntervalSince(lastWorkoutAt)
            guard elapsed >= (20 * 60) else { return false }
            guard elapsed <= (8 * 60 * 60) else { return false }
        } else {
            guard let lastWorkoutHour = context.lastActiveWorkoutHour else { return false }
            let currentHour = Calendar.current.component(.hour, from: now)
            let hourDelta = (currentHour - lastWorkoutHour + 24) % 24
            guard hourDelta <= 6 else { return false }
        }

        let alreadyCheckedIn = context.activeSignals.contains { signal in
            signal.source == .workoutCheckIn &&
            Calendar.current.isDate(signal.createdAt, inSameDayAs: now)
        }
        if alreadyCheckedIn { return false }

        let alreadyAnsweredPulseQuestion = context.activeSignals.contains { signal in
            signal.source == .dashboardNote &&
            signal.detail.contains("[PulseQuestion:\(postWorkoutQuestionID)]") &&
            Calendar.current.isDate(signal.createdAt, inSameDayAs: now)
        }

        return !alreadyAnsweredPulseQuestion
    }

    private static func postWorkoutFollowupQuestion() -> TraiPulseQuestion {
        TraiPulseQuestion(
            id: postWorkoutQuestionID,
            prompt: "How did this workout feel?",
            mode: .singleChoice,
            options: [
                TraiPulseQuestionOption(title: "Felt strong"),
                TraiPulseQuestionOption(title: "Hard but manageable"),
                TraiPulseQuestionOption(title: "Too fatigued"),
                TraiPulseQuestionOption(title: "Pain/discomfort")
            ],
            placeholder: "Optional note for your next session",
            isRequired: false
        )
    }

    private static func shouldPrioritizeMorningWeightLog(
        _ context: DailyCoachContext,
        now: Date
    ) -> Bool {
        guard !context.hasActiveWorkout else { return false }
        guard let daysSince = context.daysSinceLastWeightLog, daysSince > 0 else { return false }

        let hour = Calendar.current.component(.hour, from: now)
        guard (4..<12).contains(hour) else { return false }

        let hasMorningWindow = context.weightLikelyLogTimes.contains(where: { window in
            window.localizedStandardContains("Morning (4-9 AM)") ||
            window.localizedStandardContains("Late Morning (9-12 PM)")
        })
        let weekday = weekdayName(for: Calendar.current.component(.weekday, from: now))
        let isUsualDay = context.weightLoggedThisWeekDays.contains(weekday)
        let strongRoutine = context.weightLogRoutineScore >= 0.42

        return hasMorningWindow || isUsualDay || strongRoutine
    }

    private static func preferredWeightAction(for context: DailyCoachContext) -> DailyCoachAction {
        if let daysSince = context.daysSinceLastWeightLog, daysSince >= 8 {
            return DailyCoachAction(
                kind: .openWeight,
                title: "Review Weight Trend",
                subtitle: "Re-anchor your morning check-in"
            )
        }

        return DailyCoachAction(
            kind: .logWeight,
            title: "Log Morning Weight",
            subtitle: "Keep your routine streak"
        )
    }

    private static func shouldReplaceActionWithWeight(_ kind: DailyCoachAction.Kind) -> Bool {
        switch kind {
        case .startWorkout, .startWorkoutTemplate, .openWorkouts, .openWorkoutPlan:
            return true
        default:
            return false
        }
    }

    private static func canReplaceAction(_ current: DailyCoachAction, with replacement: DailyCoachAction) -> Bool {
        if current.kind == .completeReminder, replacement.kind != .completeReminder {
            return false
        }

        switch current.kind {
        case .logWeight, .openWeight:
            return false
        default:
            return true
        }
    }

    private static func preferredSurface(for kind: DailyCoachAction.Kind) -> TraiPulseSurfaceType {
        switch kind {
        case .logWeight, .openWeight, .completeReminder:
            return .timingNudge
        case .openRecovery:
            return .recoveryProbe
        default:
            return .coachNote
        }
    }

    private static func withPulseMetadata(
        _ action: DailyCoachAction,
        additions: [String: String]
    ) -> DailyCoachAction {
        var metadata = action.metadata ?? [:]
        for (key, value) in additions where !value.isEmpty {
            metadata[key] = value
        }
        return DailyCoachAction(
            kind: action.kind,
            title: action.title,
            subtitle: action.subtitle,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private static func weekdayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }
}
