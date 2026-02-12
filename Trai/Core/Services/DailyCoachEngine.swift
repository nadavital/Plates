//
//  DailyCoachEngine.swift
//  Trai
//
//  Computes message-first daily coaching recommendations for Dashboard.
//

import Foundation

enum DailyCoachEffortMode: String, CaseIterable, Identifiable {
    case consistency
    case balanced
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency: "Consistency"
        case .balanced: "Balanced"
        case .push: "Push"
        }
    }
}

enum DailyCoachWorkoutWindow: String, CaseIterable, Identifiable {
    case morning
    case lunch
    case evening
    case flexible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .lunch: "Midday"
        case .evening: "Evening"
        case .flexible: "Flexible"
        }
    }

    var label: String {
        switch self {
        case .morning: "6-11 AM"
        case .lunch: "11 AM-3 PM"
        case .evening: "6-9 PM"
        case .flexible: "Any time"
        }
    }

    var hours: (start: Int, end: Int) {
        switch self {
        case .morning: (6, 11)
        case .lunch: (11, 15)
        case .evening: (18, 21)
        case .flexible: (9, 21)
        }
    }
}

enum DailyCoachTomorrowFocus: String, CaseIterable, Identifiable {
    case workout
    case nutrition
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: "Workout"
        case .nutrition: "Nutrition"
        case .both: "Both"
        }
    }
}

struct DailyCoachPreferences {
    var effortMode: DailyCoachEffortMode
    var workoutWindow: DailyCoachWorkoutWindow
    var tomorrowFocus: DailyCoachTomorrowFocus
    var tomorrowWorkoutMinutes: Int
}

struct DailyCoachContext {
    let now: Date
    let hasWorkoutToday: Bool
    let hasActiveWorkout: Bool
    let caloriesConsumed: Int
    let calorieGoal: Int
    let proteinConsumed: Int
    let proteinGoal: Int
    let readyMuscleCount: Int
    let recommendedWorkoutName: String?
    let activeSignals: [CoachSignal]
    let trend: TraiPulseTrendSnapshot?
    let patternProfile: TraiPulsePatternProfile?
}

struct DailyCoachAction: Identifiable, Hashable {
    enum Kind: String {
        case startWorkout
        case logFood
        case openChat
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String?
}

struct DailyCoachSwapOption: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let action: DailyCoachAction
}

struct DailyCoachRecommendation {
    enum Phase {
        case morningPlan
        case onTrack
        case atRisk
        case rescue
        case completed
    }

    let phase: Phase
    let title: String
    let message: String
    let reasons: [String]
    let confidenceLabel: String
    let primaryAction: DailyCoachAction
    let secondaryAction: DailyCoachAction
    let swaps: [DailyCoachSwapOption]
    let question: TraiPulseQuestion?
    let tomorrowPreview: String
}

enum DailyCoachEngine {
    static func makeRecommendation(
        context: DailyCoachContext,
        preferences: DailyCoachPreferences,
        calendar: Calendar = .current
    ) -> DailyCoachRecommendation {
        let window = preferences.workoutWindow.hours
        let activeSignalSnapshots = context.activeSignals.activeSnapshots(now: context.now)
        let basePulseInput = TraiPulseInputContext(
            now: context.now,
            hasWorkoutToday: context.hasWorkoutToday,
            hasActiveWorkout: context.hasActiveWorkout,
            caloriesConsumed: context.caloriesConsumed,
            calorieGoal: context.calorieGoal,
            proteinConsumed: context.proteinConsumed,
            proteinGoal: context.proteinGoal,
            readyMuscleCount: context.readyMuscleCount,
            recommendedWorkoutName: context.recommendedWorkoutName,
            workoutWindowStartHour: window.start,
            workoutWindowEndHour: window.end,
            activeSignals: activeSignalSnapshots,
            tomorrowWorkoutMinutes: preferences.tomorrowWorkoutMinutes,
            trend: context.trend,
            patternProfile: context.patternProfile,
            contextPacket: nil
        )
        let packet = TraiPulseContextAssembler.assemble(
            patternProfile: context.patternProfile ?? .empty,
            activeSignals: activeSignalSnapshots,
            context: basePulseInput
        )
        let pulseInput = TraiPulseInputContext(
            now: basePulseInput.now,
            hasWorkoutToday: basePulseInput.hasWorkoutToday,
            hasActiveWorkout: basePulseInput.hasActiveWorkout,
            caloriesConsumed: basePulseInput.caloriesConsumed,
            calorieGoal: basePulseInput.calorieGoal,
            proteinConsumed: basePulseInput.proteinConsumed,
            proteinGoal: basePulseInput.proteinGoal,
            readyMuscleCount: basePulseInput.readyMuscleCount,
            recommendedWorkoutName: basePulseInput.recommendedWorkoutName,
            workoutWindowStartHour: basePulseInput.workoutWindowStartHour,
            workoutWindowEndHour: basePulseInput.workoutWindowEndHour,
            activeSignals: basePulseInput.activeSignals,
            tomorrowWorkoutMinutes: basePulseInput.tomorrowWorkoutMinutes,
            trend: basePulseInput.trend,
            patternProfile: basePulseInput.patternProfile,
            contextPacket: packet
        )
        let pulse = TraiPulseEngine.makeBrief(context: pulseInput)
        let phase = mapPhase(pulse.phase)
        let proteinRemaining = max(context.proteinGoal - context.proteinConsumed, 0)
        let workoutName = context.recommendedWorkoutName ?? "Recommended Session"

        var reasons = pulse.reasons.map(\.text)
        if let strongestSignal = context.activeSignals.active(now: context.now).max(by: { $0.severity < $1.severity }) {
            reasons.append(strongestSignal.title)
        }
        if proteinRemaining > 0 {
            reasons.append("\(proteinRemaining)g protein left")
        }
        if let firstPattern = packet.patterns.first {
            reasons.append(firstPattern)
        }

        let pulsePrimaryAction = mapAction(pulse.primaryAction)
        let pulseSecondaryAction = mapAction(pulse.secondaryAction)

        let fallbackWorkoutAction = DailyCoachAction(
            kind: .startWorkout,
            title: phase == .completed ? "Start Light Recovery" : "Start \(workoutName)",
            subtitle: phase == .completed ? "Optional" : nil
        )
        let fallbackNutritionAction = DailyCoachAction(
            kind: .logFood,
            title: phase == .completed ? "Log Recovery Meal" : "Log Next Meal",
            subtitle: phase == .completed ? "Close protein target" : nil
        )

        let primary: DailyCoachAction
        let secondary: DailyCoachAction

        switch preferences.tomorrowFocus {
        case .workout:
            primary = pulsePrimaryAction.kind == .startWorkout ? pulsePrimaryAction : fallbackWorkoutAction
            secondary = fallbackNutritionAction
        case .nutrition:
            primary = fallbackNutritionAction
            secondary = pulsePrimaryAction.kind == .startWorkout ? pulsePrimaryAction : fallbackWorkoutAction
        case .both:
            if phase == .completed {
                primary = fallbackNutritionAction
                secondary = pulseSecondaryAction
            } else {
                primary = pulsePrimaryAction
                secondary = fallbackNutritionAction
            }
        }

        let swaps = buildSwaps(
            phase: phase,
            preferences: preferences,
            recommendedWorkoutName: workoutName,
            proteinRemaining: proteinRemaining
        )

        return DailyCoachRecommendation(
            phase: phase,
            title: pulse.title,
            message: pulse.message,
            reasons: Array(reasons.prefix(3)),
            confidenceLabel: pulse.confidenceLabel,
            primaryAction: primary,
            secondaryAction: secondary,
            swaps: swaps,
            question: pulse.question,
            tomorrowPreview: pulse.tomorrowPreview
        )
    }

    private static func mapPhase(_ phase: TraiPulseBrief.Phase) -> DailyCoachRecommendation.Phase {
        switch phase {
        case .morningPlan: .morningPlan
        case .onTrack: .onTrack
        case .atRisk: .atRisk
        case .rescue: .rescue
        case .completed: .completed
        }
    }

    private static func mapAction(_ action: TraiPulseAction) -> DailyCoachAction {
        let kind: DailyCoachAction.Kind
        switch action.kind {
        case .startWorkout:
            kind = .startWorkout
        case .logFood:
            kind = .logFood
        case .openChat, .addNote, .viewRecovery:
            kind = .openChat
        }

        return DailyCoachAction(
            kind: kind,
            title: action.title,
            subtitle: action.subtitle
        )
    }

    private static func buildSwaps(
        phase: DailyCoachRecommendation.Phase,
        preferences: DailyCoachPreferences,
        recommendedWorkoutName: String,
        proteinRemaining: Int
    ) -> [DailyCoachSwapOption] {
        guard phase == .atRisk || phase == .rescue else {
            return []
        }

        let quickMinutes = min(max(preferences.tomorrowWorkoutMinutes / 2, 15), 30)
        let proteinBump = max(proteinRemaining, 30)

        return [
            DailyCoachSwapOption(
                title: "\(quickMinutes)-Minute Quick Lift",
                detail: "Short version of \(recommendedWorkoutName)",
                action: DailyCoachAction(kind: .startWorkout, title: "Start Quick Lift", subtitle: nil)
            ),
            DailyCoachSwapOption(
                title: "Walk + Protein Dinner",
                detail: "Aim for +\(proteinBump)g and light movement",
                action: DailyCoachAction(kind: .logFood, title: "Log Dinner Plan", subtitle: nil)
            ),
            DailyCoachSwapOption(
                title: "Coach-Led Swap",
                detail: "Generate a custom backup for tonight",
                action: DailyCoachAction(kind: .openChat, title: "Open Trai Coach", subtitle: nil)
            )
        ]
    }
}
