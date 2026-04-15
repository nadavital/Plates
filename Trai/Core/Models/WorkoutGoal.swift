//
//  WorkoutGoal.swift
//  Trai
//

import Foundation
import SwiftData

@Model
final class WorkoutGoal {
    var id: UUID = UUID()
    var title: String = ""
    var goalKindRaw: String = GoalKind.milestone.rawValue
    var statusRaw: String = GoalStatus.active.rawValue
    var linkedWorkoutTypeRaw: String?
    var linkedActivityName: String?
    var targetValue: Double?
    var targetUnit: String = ""
    var periodUnitRaw: String?
    var periodCount: Int?
    var notes: String = ""
    var targetDate: Date?
    var checkInCadenceDays: Int?
    var baselineValue: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var lastCheckInPromptAt: Date?
    var lastCelebratedAt: Date?

    init() {}

    init(
        title: String,
        goalKind: GoalKind = .milestone,
        status: GoalStatus = .active,
        linkedWorkoutType: WorkoutMode? = nil,
        linkedActivityName: String? = nil,
        targetValue: Double? = nil,
        targetUnit: String = "",
        periodUnit: PeriodUnit? = nil,
        periodCount: Int? = nil,
        notes: String = "",
        targetDate: Date? = nil,
        checkInCadenceDays: Int? = nil,
        baselineValue: Double? = nil
    ) {
        self.title = title
        self.goalKindRaw = goalKind.rawValue
        self.statusRaw = status.rawValue
        self.linkedWorkoutTypeRaw = linkedWorkoutType?.rawValue
        self.linkedActivityName = linkedActivityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.periodUnitRaw = periodUnit?.rawValue
        self.periodCount = periodCount
        self.notes = notes
        self.targetDate = targetDate
        self.checkInCadenceDays = checkInCadenceDays
        self.baselineValue = baselineValue
    }
}

extension WorkoutGoal {
    enum GoalKind: String, CaseIterable, Identifiable {
        case milestone = "milestone"
        case frequency = "frequency"
        case duration = "duration"
        case distance = "distance"
        case weight = "weight"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .milestone: "Milestone"
            case .frequency: "Frequency"
            case .duration: "Duration"
            case .distance: "Distance"
            case .weight: "Weight"
            }
        }

        var iconName: String {
            switch self {
            case .milestone: "flag.checkered"
            case .frequency: "calendar.badge.clock"
            case .duration: "clock.badge"
            case .distance: "point.topleft.down.curvedto.point.bottomright.up"
            case .weight: "dumbbell.fill"
            }
        }

        var supportsNumericTarget: Bool {
            self != .milestone
        }

        var usesPeriodTarget: Bool {
            self == .frequency
        }
    }

    enum PeriodUnit: String, CaseIterable, Identifiable {
        case day = "day"
        case week = "week"
        case month = "month"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            }
        }
    }

    enum GoalStatus: String, CaseIterable, Identifiable {
        case active = "active"
        case completed = "completed"
        case paused = "paused"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .active: "Active"
            case .completed: "Completed"
            case .paused: "Paused"
            }
        }
    }

    var goalKind: GoalKind {
        get { GoalKind(rawValue: goalKindRaw) ?? .milestone }
        set { goalKindRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var linkedWorkoutType: WorkoutMode? {
        get { linkedWorkoutTypeRaw.flatMap(WorkoutMode.init(rawValue:)) }
        set { linkedWorkoutTypeRaw = newValue?.rawValue }
    }

    var periodUnit: PeriodUnit? {
        get { periodUnitRaw.flatMap(PeriodUnit.init(rawValue:)) }
        set { periodUnitRaw = newValue?.rawValue }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedActivityName: String? {
        let trimmed = linkedActivityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        status == .active
    }

    var effectiveCheckInCadenceDays: Int {
        if let checkInCadenceDays, checkInCadenceDays > 0 {
            return checkInCadenceDays
        }

        switch goalKind {
        case .milestone:
            return 21
        case .frequency:
            return periodUnit == .month ? 28 : 14
        case .duration, .distance, .weight:
            return 21
        }
    }

    var scopeSummary: String {
        if let activityName = trimmedActivityName, let linkedWorkoutType {
            return "\(linkedWorkoutType.displayName) • \(activityName)"
        }
        if let activityName = trimmedActivityName {
            return activityName
        }
        if let linkedWorkoutType {
            return linkedWorkoutType.displayName
        }
        return "Any session"
    }

    var trackingSummary: String? {
        switch goalKind {
        case .frequency:
            guard let targetValue, targetValue > 0 else { return nil }
            let roundedTarget = Int(targetValue.rounded())
            let periodLabel = periodLabelText
            return "\(roundedTarget)x per \(periodLabel)"
        case .milestone:
            return nil
        case .duration, .distance, .weight:
            guard let targetValue, targetValue > 0 else { return nil }
            return formattedTargetValue(targetValue, unit: targetUnit)
        }
    }

    var periodLabelText: String {
        let count = max(periodCount ?? 1, 1)
        let base = periodUnit ?? .week
        if count == 1 {
            return base.rawValue
        }
        return "\(count) \(base.rawValue)s"
    }

    var horizonSummary: String? {
        guard let targetDate else { return nil }
        return "By \(targetDate.formatted(date: .abbreviated, time: .omitted))"
    }

    func matches(workout: LiveWorkout) -> Bool {
        if let linkedWorkoutType, linkedWorkoutType != workout.type {
            return false
        }

        guard let activityName = trimmedActivityName?.goalNormalizedKey else {
            return true
        }

        let normalizedFocusAreas = Set(workout.focusAreas.map(\.goalNormalizedKey))
        if normalizedFocusAreas.contains(activityName) {
            return true
        }

        if workout.name.goalNormalizedKey == activityName {
            return true
        }

        return (workout.entries ?? []).contains {
            $0.exerciseName.goalNormalizedKey == activityName
        }
    }

    func matches(session: WorkoutSession) -> Bool {
        if let linkedWorkoutType, linkedWorkoutType != session.inferredWorkoutMode {
            return false
        }

        guard let activityName = trimmedActivityName?.goalNormalizedKey else {
            return true
        }

        return session.goalMatchingTokens.contains(activityName)
    }

    func markCompleted() {
        status = .completed
        completedAt = Date()
        updatedAt = Date()
    }

    func markActive() {
        status = .active
        completedAt = nil
        updatedAt = Date()
    }

    func markCheckedIn() {
        lastCheckInPromptAt = Date()
    }

    func markCelebrated() {
        lastCelebratedAt = Date()
    }

    private func formattedTargetValue(_ value: Double, unit: String) -> String {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedValue: String
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            formattedValue = "\(Int(value.rounded()))"
        } else {
            formattedValue = String(format: "%.1f", value)
        }
        return trimmedUnit.isEmpty ? formattedValue : "\(formattedValue) \(trimmedUnit)"
    }
}

extension String {
    var goalNormalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
