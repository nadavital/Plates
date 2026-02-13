//
//  TraiPulseTypes.swift
//  Trai
//
//  Domain types for Trai Pulse analysis and UI.
//

import Foundation

enum TraiPulseTimeWindow: String, CaseIterable, Hashable, Sendable {
    case earlyMorning
    case morning
    case midday
    case afternoon
    case evening
    case lateNight

    var label: String {
        switch self {
        case .earlyMorning: "Early Morning"
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .lateNight: "Late Night"
        }
    }

    var hourRange: (start: Int, end: Int) {
        switch self {
        case .earlyMorning: (5, 8)
        case .morning: (8, 11)
        case .midday: (11, 14)
        case .afternoon: (14, 17)
        case .evening: (17, 21)
        case .lateNight: (21, 24)
        }
    }
}

struct TraiPulsePatternProfile: Hashable, Sendable {
    let workoutWindowScores: [String: Double]
    let mealWindowScores: [String: Double]
    let commonProteinAnchors: [String]
    let adherenceNotes: [String]
    let actionAffinity: [String: Double]
    let confidence: Double

    static let empty = TraiPulsePatternProfile(
        workoutWindowScores: [:],
        mealWindowScores: [:],
        commonProteinAnchors: [],
        adherenceNotes: [],
        actionAffinity: [:],
        confidence: 0
    )

    func strongestWorkoutWindow(minScore: Double = 0.30) -> TraiPulseTimeWindow? {
        let best = workoutWindowScores.max { $0.value < $1.value }
        guard let key = best?.key,
              let window = TraiPulseTimeWindow(rawValue: key),
              (best?.value ?? 0) >= minScore else {
            return nil
        }
        return window
    }

    func strongestMealWindow(minScore: Double = 0.25) -> TraiPulseTimeWindow? {
        let best = mealWindowScores.max { $0.value < $1.value }
        guard let key = best?.key,
              let window = TraiPulseTimeWindow(rawValue: key),
              (best?.value ?? 0) >= minScore else {
            return nil
        }
        return window
    }

    func affinity(for action: TraiPulseAction.Kind) -> Double {
        actionAffinity[action.rawValue] ?? 0
    }
}

struct TraiPulseReminderCandidate: Hashable, Sendable {
    let id: String
    let title: String
    let time: String
    let hour: Int
    let minute: Int
}

struct TraiPulseContextPacket: Hashable, Sendable {
    let goal: String
    let constraints: [String]
    let patterns: [String]
    let anomalies: [String]
    let suggestedActions: [String]
    let estimatedTokens: Int
    let promptSummary: String
}

struct TraiPulseTrendSnapshot: Hashable, Sendable {
    let daysWindow: Int
    let daysWithFoodLogs: Int
    let proteinTargetHitDays: Int
    let calorieTargetHitDays: Int
    let workoutDays: Int
    let lowProteinStreak: Int
    let daysSinceWorkout: Int

    var loggingConsistency: Double {
        guard daysWindow > 0 else { return 0 }
        return Double(daysWithFoodLogs) / Double(daysWindow)
    }

    var proteinHitRate: Double {
        guard daysWindow > 0 else { return 0 }
        return Double(proteinTargetHitDays) / Double(daysWindow)
    }

    var calorieHitRate: Double {
        guard daysWindow > 0 else { return 0 }
        return Double(calorieTargetHitDays) / Double(daysWindow)
    }
}

struct TraiPulseAction: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case startWorkout
        case logFood
        case logFoodCamera
        case logWeight
        case openWeight
        case openCalorieDetail
        case openMacroDetail
        case openProfile
        case openWorkouts
        case openWorkoutPlan
        case openRecovery
        case startWorkoutTemplate
        case reviewNutritionPlan
        case reviewWorkoutPlan
        case completeReminder
    }

    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String?
    let metadata: [String: String]?

    init(id: UUID = UUID(), kind: Kind, title: String, subtitle: String?, metadata: [String: String]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
    }
}

struct TraiPulseReason: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let emphasis: Double
}

struct TraiPulseQuestionOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?

    init(id: String? = nil, title: String, subtitle: String? = nil) {
        self.id = id ?? title
        self.title = title
        self.subtitle = subtitle
    }
}

enum TraiPulseQuestionInputMode: Hashable, Sendable {
    case singleChoice
    case multipleChoice
    case slider(range: ClosedRange<Double>, step: Double, unit: String?)
    case note(maxLength: Int)
}

struct TraiPulseQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let prompt: String
    let mode: TraiPulseQuestionInputMode
    let options: [TraiPulseQuestionOption]
    let placeholder: String
    let isRequired: Bool
}

struct TraiPulseBrief: Sendable {
    enum Phase: Sendable {
        case morningPlan
        case onTrack
        case atRisk
        case rescue
        case completed
    }

    let phase: Phase
    let title: String
    let message: String
    let reasons: [TraiPulseReason]
    let confidence: Double
    let confidenceLabel: String
    let primaryAction: TraiPulseAction
    let secondaryAction: TraiPulseAction
    let question: TraiPulseQuestion
    let tomorrowPreview: String
}

struct TraiPulseInputContext: Sendable {
    let now: Date
    let hasWorkoutToday: Bool
    let hasActiveWorkout: Bool
    let caloriesConsumed: Int
    let calorieGoal: Int
    let proteinConsumed: Int
    let proteinGoal: Int
    let readyMuscleCount: Int
    let recommendedWorkoutName: String?
    let workoutWindowStartHour: Int
    let workoutWindowEndHour: Int
    let activeSignals: [CoachSignalSnapshot]
    let tomorrowWorkoutMinutes: Int
    let trend: TraiPulseTrendSnapshot?
    let patternProfile: TraiPulsePatternProfile?
    let contextPacket: TraiPulseContextPacket?
    let reminderCompletionRate: Double?
    let recentMissedReminderCount: Int?
    let daysSinceLastWeightLog: Int?
    let weightLoggedThisWeek: Bool?
    let weightLoggedThisWeekDays: [String]
    let weightLikelyLogTimes: [String]
    let weightRecentRangeKg: Double?
    let weightLogRoutineScore: Double
    let todaysExerciseMinutes: Int?
    let lastActiveWorkoutHour: Int?
    let likelyReminderTimes: [String]
    let likelyWorkoutTimes: [String]
    let planReviewTrigger: String?
    let planReviewMessage: String?
    let planReviewDaysSince: Int?
    let planReviewWeightDeltaKg: Double?
    let pendingReminderCandidates: [TraiPulseReminderCandidate]
    let pendingReminderCandidateScores: [String: Double]

    init(
        now: Date,
        hasWorkoutToday: Bool,
        hasActiveWorkout: Bool,
        caloriesConsumed: Int,
        calorieGoal: Int,
        proteinConsumed: Int,
        proteinGoal: Int,
        readyMuscleCount: Int,
        recommendedWorkoutName: String?,
        workoutWindowStartHour: Int,
        workoutWindowEndHour: Int,
        activeSignals: [CoachSignalSnapshot],
        tomorrowWorkoutMinutes: Int,
        trend: TraiPulseTrendSnapshot?,
        patternProfile: TraiPulsePatternProfile?,
        reminderCompletionRate: Double? = nil,
        recentMissedReminderCount: Int? = nil,
        daysSinceLastWeightLog: Int? = nil,
        weightLoggedThisWeek: Bool? = nil,
        weightLoggedThisWeekDays: [String] = [],
        weightLikelyLogTimes: [String] = [],
        weightRecentRangeKg: Double? = nil,
        weightLogRoutineScore: Double = 0.0,
        todaysExerciseMinutes: Int? = nil,
        lastActiveWorkoutHour: Int? = nil,
        likelyReminderTimes: [String] = [],
        likelyWorkoutTimes: [String] = [],
        planReviewTrigger: String? = nil,
        planReviewMessage: String? = nil,
        planReviewDaysSince: Int? = nil,
        planReviewWeightDeltaKg: Double? = nil,
        pendingReminderCandidates: [TraiPulseReminderCandidate] = [],
        pendingReminderCandidateScores: [String: Double] = [:],
        contextPacket: TraiPulseContextPacket?
    ) {
        self.now = now
        self.hasWorkoutToday = hasWorkoutToday
        self.hasActiveWorkout = hasActiveWorkout
        self.caloriesConsumed = caloriesConsumed
        self.calorieGoal = calorieGoal
        self.proteinConsumed = proteinConsumed
        self.proteinGoal = proteinGoal
        self.readyMuscleCount = readyMuscleCount
        self.recommendedWorkoutName = recommendedWorkoutName
        self.workoutWindowStartHour = workoutWindowStartHour
        self.workoutWindowEndHour = workoutWindowEndHour
        self.activeSignals = activeSignals
        self.tomorrowWorkoutMinutes = tomorrowWorkoutMinutes
        self.trend = trend
        self.patternProfile = patternProfile
        self.reminderCompletionRate = reminderCompletionRate
        self.recentMissedReminderCount = recentMissedReminderCount
        self.daysSinceLastWeightLog = daysSinceLastWeightLog
        self.weightLoggedThisWeek = weightLoggedThisWeek
        self.weightLoggedThisWeekDays = weightLoggedThisWeekDays
        self.weightLikelyLogTimes = weightLikelyLogTimes
        self.weightRecentRangeKg = weightRecentRangeKg
        self.weightLogRoutineScore = weightLogRoutineScore
        self.todaysExerciseMinutes = todaysExerciseMinutes
        self.lastActiveWorkoutHour = lastActiveWorkoutHour
        self.likelyReminderTimes = likelyReminderTimes
        self.likelyWorkoutTimes = likelyWorkoutTimes
        self.planReviewTrigger = planReviewTrigger
        self.planReviewMessage = planReviewMessage
        self.planReviewDaysSince = planReviewDaysSince
        self.planReviewWeightDeltaKg = planReviewWeightDeltaKg
        self.pendingReminderCandidates = pendingReminderCandidates
        self.pendingReminderCandidateScores = pendingReminderCandidateScores
        self.contextPacket = contextPacket
    }
}
