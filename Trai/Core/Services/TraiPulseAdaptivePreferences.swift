//
//  TraiPulseAdaptivePreferences.swift
//  Trai
//
//  Infers Pulse coaching preferences from user behavior and recent context.
//

import Foundation

enum TraiCoachTone: String, CaseIterable, Identifiable, Sendable {
    case encouraging
    case balanced
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encouraging: "Encouraging"
        case .balanced: "Balanced"
        case .direct: "Direct"
        }
    }
}

enum TraiPulseAdaptivePreferences {
    static func makePreferences(context: DailyCoachContext) -> DailyCoachPreferences {
        DailyCoachPreferences(
            effortMode: inferEffortMode(for: context),
            workoutWindow: inferWorkoutWindow(for: context),
            tomorrowFocus: inferTomorrowFocus(for: context),
            tomorrowWorkoutMinutes: inferTomorrowWorkoutMinutes(for: context)
        )
    }

    static func inferWorkoutWindow(for context: DailyCoachContext) -> DailyCoachWorkoutWindow {
        if let strongest = context.patternProfile?.strongestWorkoutWindow(minScore: 0.34) {
            switch strongest {
            case .earlyMorning, .morning:
                return .morning
            case .midday, .afternoon:
                return .lunch
            case .evening:
                return .evening
            case .lateNight:
                return .flexible
            }
        }

        let hour = Calendar.current.component(.hour, from: context.now)
        if hour < 11 { return .morning }
        if hour < 16 { return .lunch }
        if hour <= 21 { return .evening }
        return .flexible
    }

    static func inferTomorrowFocus(for context: DailyCoachContext) -> DailyCoachTomorrowFocus {
        guard let trend = context.trend else { return .both }
        if trend.daysSinceWorkout >= 3, trend.lowProteinStreak < 2 {
            return .workout
        }
        if trend.lowProteinStreak >= 2, trend.daysSinceWorkout < 3 {
            return .nutrition
        }
        return .both
    }

    static func inferTomorrowWorkoutMinutes(for context: DailyCoachContext) -> Int {
        if context.hasWorkoutToday {
            return 30
        }
        if let trend = context.trend, trend.daysSinceWorkout >= 4 {
            return 25
        }
        return 40
    }

    static func inferEffortMode(for context: DailyCoachContext) -> DailyCoachEffortMode {
        guard let trend = context.trend else { return .balanced }
        if trend.daysSinceWorkout >= 4 || trend.lowProteinStreak >= 3 {
            return .consistency
        }
        if trend.workoutDays >= 4 && trend.proteinHitRate >= 0.6 {
            return .push
        }
        return .balanced
    }
}
