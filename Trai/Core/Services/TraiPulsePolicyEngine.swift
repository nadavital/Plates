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

        return adjusted
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
}
