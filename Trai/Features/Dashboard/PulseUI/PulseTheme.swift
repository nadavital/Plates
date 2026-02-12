//
//  PulseTheme.swift
//  Trai
//
//  Shared style tokens for the Dashboard Pulse surface.
//

import SwiftUI

enum PulseTheme {
    static let cardRadius: CGFloat = 16
    static let chipRadius: CGFloat = 14
    static let chipPaddingH: CGFloat = 13
    static let chipPaddingV: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let elementSpacing: CGFloat = 8

    static var accent: Color { .accentColor }

    static var palette: [Color] {
        TraiLensPalette.energy.colors
    }

    static func surfaceTint(_ surfaceType: TraiPulseSurfaceType) -> Color {
        switch surfaceType {
        case .coachNote: palette[1]
        case .quickCheckin: palette[0]
        case .recoveryProbe: palette[2]
        case .timingNudge: palette[3]
        case .planProposal: .accentColor
        }
    }

    static func phaseTint(_ phase: DailyCoachRecommendation.Phase) -> Color {
        switch phase {
        case .morningPlan: .orange
        case .onTrack: .accentColor
        case .atRisk: .yellow
        case .rescue: .red
        case .completed: .green
        }
    }
}
