//
//  TraiPulseSurfaceComposer.swift
//  Trai
//
//  Prototype composer that maps Pulse state into dynamic interface specs.
//

import Foundation

enum TraiPulseSurfaceLayout: String, Sendable {
    case cinematic
    case conversational
    case compact
}

struct TraiPulseSurfaceActionSpec: Identifiable, Hashable, Sendable {
    enum Emphasis: String, Sendable {
        case primary
        case secondary
    }

    let id = UUID()
    let kind: DailyCoachAction.Kind
    let title: String
    let subtitle: String?
    let emphasis: Emphasis
}

struct TraiPulseSurfaceSpec: Sendable {
    let layout: TraiPulseSurfaceLayout
    let headerLine: String
    let headline: String
    let body: String
    let carryoverLine: String?
    let reasons: [String]
    let actions: [TraiPulseSurfaceActionSpec]
    let question: TraiPulseQuestion?
    let tomorrowLine: String
}

enum TraiPulseSurfaceComposer {
    static func compose(
        recommendation: DailyCoachRecommendation,
        contextNow: Date,
        recentAnswer: TraiPulseRecentAnswer?
    ) -> TraiPulseSurfaceSpec {
        let layout = layoutFor(phase: recommendation.phase, recentAnswer: recentAnswer)
        let header = headerLine(for: contextNow, phase: recommendation.phase)

        let carryoverLine = recentAnswer.map { TraiPulseResponseInterpreter.carryoverReason(for: $0) }
        let actions = actionSpecs(from: recommendation)

        return TraiPulseSurfaceSpec(
            layout: layout,
            headerLine: header,
            headline: recommendation.title,
            body: recommendation.message,
            carryoverLine: carryoverLine,
            reasons: Array(recommendation.reasons.prefix(layout == .compact ? 1 : 2)),
            actions: actions,
            question: recommendation.question,
            tomorrowLine: recommendation.tomorrowPreview
        )
    }

    private static func layoutFor(
        phase: DailyCoachRecommendation.Phase,
        recentAnswer: TraiPulseRecentAnswer?
    ) -> TraiPulseSurfaceLayout {
        if phase == .atRisk || phase == .rescue {
            return .cinematic
        }
        if recentAnswer != nil {
            return .conversational
        }
        return .compact
    }

    private static func headerLine(for date: Date, phase: DailyCoachRecommendation.Phase) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let timeLine: String
        switch hour {
        case 5..<11: timeLine = "Morning pulse"
        case 11..<16: timeLine = "Midday pulse"
        case 16..<21: timeLine = "Evening pulse"
        default: timeLine = "Night pulse"
        }

        let phaseLine: String
        switch phase {
        case .morningPlan: phaseLine = "plan"
        case .onTrack: phaseLine = "on track"
        case .atRisk: phaseLine = "decision point"
        case .rescue: phaseLine = "adaptive mode"
        case .completed: phaseLine = "recovery mode"
        }

        return "\(timeLine) - \(phaseLine)"
    }

    private static func actionSpecs(from recommendation: DailyCoachRecommendation) -> [TraiPulseSurfaceActionSpec] {
        var specs: [TraiPulseSurfaceActionSpec] = []

        specs.append(
            TraiPulseSurfaceActionSpec(
                kind: recommendation.primaryAction.kind,
                title: recommendation.primaryAction.title,
                subtitle: recommendation.primaryAction.subtitle,
                emphasis: .primary
            )
        )

        specs.append(
            TraiPulseSurfaceActionSpec(
                kind: recommendation.secondaryAction.kind,
                title: recommendation.secondaryAction.title,
                subtitle: recommendation.secondaryAction.subtitle,
                emphasis: .secondary
            )
        )

        return specs
    }
}
