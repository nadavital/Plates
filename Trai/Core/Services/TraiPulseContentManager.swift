//
//  TraiPulseContentManager.swift
//  Trai
//
//  Manages compact Pulse content snapshots for dashboard rendering.
//

import Foundation

enum TraiPulseContentSource: String, Sendable {
    case modelManaged
}

enum TraiPulseSurfaceType: String, Sendable {
    case coachNote = "coach_note"
    case quickCheckin = "quick_checkin"
    case recoveryProbe = "recovery_probe"
    case timingNudge = "timing_nudge"
    case planProposal = "plan_proposal"
}

struct TraiPulsePlanProposal: Sendable {
    let id: String
    let title: String
    let rationale: String
    let impact: String
    let changes: [String]
    let applyLabel: String
    let reviewLabel: String
    let deferLabel: String
}

enum TraiPulsePlanProposalDecision: String, Sendable {
    case apply
    case review
    case later
}

enum TraiPulseContentPrompt: Sendable {
    case question(TraiPulseQuestion)
    case action(DailyCoachAction)
    case planProposal(TraiPulsePlanProposal)
}

struct TraiPulseContentSnapshot: Sendable {
    let source: TraiPulseContentSource
    let surfaceType: TraiPulseSurfaceType
    let title: String
    let message: String
    let prompt: TraiPulseContentPrompt?
}
