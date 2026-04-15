//
//  WorkoutGoalComponents.swift
//  Trai
//

import SwiftUI
import SwiftData

struct WorkoutGoalInsight: Identifiable {
    let goal: WorkoutGoal
    let progressText: String
    let supportingText: String?
    let progressFraction: Double?
    let currentValueText: String?
    let targetValueText: String?
    let baselineValueText: String?

    var id: UUID { goal.id }

    init(
        goal: WorkoutGoal,
        progressText: String,
        supportingText: String?,
        progressFraction: Double?,
        currentValueText: String?,
        targetValueText: String?,
        baselineValueText: String? = nil
    ) {
        self.goal = goal
        self.progressText = progressText
        self.supportingText = supportingText
        self.progressFraction = progressFraction
        self.currentValueText = currentValueText
        self.targetValueText = targetValueText
        self.baselineValueText = baselineValueText
    }
}

struct RecentWorkoutSignal: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let note: String
    let date: Date
}

enum WorkoutGoalProgressResolver {
    static func relevantGoals(
        for workout: LiveWorkout,
        goals: [WorkoutGoal],
        includeCompleted: Bool = true
    ) -> [WorkoutGoal] {
        goals
            .filter { goal in
                goal.matches(workout: workout) && (includeCompleted || goal.isActive)
            }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status == .active
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func insights(
        for workout: LiveWorkout,
        goals: [WorkoutGoal],
        workouts: [LiveWorkout],
        sessions: [WorkoutSession] = [],
        exerciseHistory: [ExerciseHistory],
        useLbs: Bool
    ) -> [WorkoutGoalInsight] {
        insights(
            goals: relevantGoals(for: workout, goals: goals),
            workouts: workouts,
            sessions: sessions,
            exerciseHistory: exerciseHistory,
            useLbs: useLbs
        )
    }

    static func insights(
        goals: [WorkoutGoal],
        workouts: [LiveWorkout],
        sessions: [WorkoutSession] = [],
        exerciseHistory: [ExerciseHistory],
        useLbs: Bool
    ) -> [WorkoutGoalInsight] {
        goals.map {
            insight(
                for: $0,
                workouts: workouts,
                sessions: sessions,
                exerciseHistory: exerciseHistory,
                useLbs: useLbs
            )
        }
    }

    static func recentSignals(
        for workout: LiveWorkout,
        workouts: [LiveWorkout],
        sessions: [WorkoutSession] = []
    ) -> [RecentWorkoutSignal] {
        let currentFocus = Set(workout.focusAreas.map(\.goalNormalizedKey))
        let currentActivities = Set((workout.entries ?? []).map { $0.exerciseName.goalNormalizedKey })

        let liveSignals: [RecentWorkoutSignal] = workouts
            .filter { candidate in
                candidate.id != workout.id && candidate.completedAt != nil
            }
            .filter { candidate in
                if candidate.type == workout.type {
                    return true
                }

                let candidateFocus = Set(candidate.focusAreas.map(\.goalNormalizedKey))
                if !candidateFocus.isDisjoint(with: currentFocus) {
                    return true
                }

                let candidateActivities = Set((candidate.entries ?? []).map { $0.exerciseName.goalNormalizedKey })
                return !candidateActivities.isDisjoint(with: currentActivities)
            }
            .compactMap { candidate -> RecentWorkoutSignal? in
                guard let note = latestNote(in: candidate), !note.isEmpty else { return nil }
                let subtitle = [candidate.displayFocusSummary, candidate.formattedDuration]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")

                return RecentWorkoutSignal(
                    title: candidate.name,
                    subtitle: subtitle,
                    note: note,
                    date: candidate.completedAt ?? candidate.startedAt
                )
            }
            .sorted { $0.date > $1.date }

        let sessionSignals = sessions
            .filter { candidate in
                if candidate.inferredWorkoutMode == workout.type {
                    return true
                }

                let candidateTokens = candidate.goalMatchingTokens
                if !candidateTokens.isDisjoint(with: currentActivities) {
                    return true
                }

                return candidateTokens.contains(where: { currentFocus.contains($0) })
            }
            .compactMap { signal(from: $0) }

        return Array((liveSignals + sessionSignals)
            .sorted { $0.date > $1.date }
            .prefix(3))
    }

    static func globalRecentSignals(
        from workouts: [LiveWorkout],
        sessions: [WorkoutSession] = []
    ) -> [RecentWorkoutSignal] {
        let liveSignals: [RecentWorkoutSignal] = workouts
            .filter { $0.completedAt != nil }
            .compactMap { workout -> RecentWorkoutSignal? in
                guard let note = latestNote(in: workout), !note.isEmpty else { return nil }
                let subtitle = [workout.type.displayName, workout.displayFocusSummary, workout.formattedDuration]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")

                return RecentWorkoutSignal(
                    title: workout.name,
                    subtitle: subtitle,
                    note: note,
                    date: workout.completedAt ?? workout.startedAt
                )
            }

        let sessionSignals = sessions.compactMap { signal(from: $0) }

        return Array((liveSignals + sessionSignals)
            .sorted { $0.date > $1.date }
            .prefix(3))
    }

    static func matchingCompletedWorkouts(
        for goal: WorkoutGoal,
        in workouts: [LiveWorkout]
    ) -> [LiveWorkout] {
        workouts
            .filter { $0.completedAt != nil && goal.matches(workout: $0) }
            .sorted {
                ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt)
            }
    }

    static func signals(
        for goal: WorkoutGoal,
        in workouts: [LiveWorkout],
        sessions: [WorkoutSession] = []
    ) -> [RecentWorkoutSignal] {
        let liveSignals = matchingCompletedWorkouts(for: goal, in: workouts)
            .compactMap { signal(from: $0) }

        let sessionSignals = matchingCompletedSessions(for: goal, in: sessions)
            .compactMap { signal(from: $0) }

        return Array((liveSignals + sessionSignals)
            .sorted { $0.date > $1.date }
            .prefix(5))
    }

    static func staleGoalsNeedingCheckIn(
        goals: [WorkoutGoal],
        workouts: [LiveWorkout],
        sessions: [WorkoutSession] = [],
        now: Date = Date()
    ) -> [WorkoutGoal] {
        goals
            .filter(\.isActive)
            .filter { goal in
                let latestWorkoutDate = matchingCompletedWorkouts(for: goal, in: workouts)
                    .compactMap { $0.completedAt ?? $0.startedAt }
                    .max()
                let latestSessionDate = matchingCompletedSessions(for: goal, in: sessions)
                    .map(\.loggedAt)
                    .max()

                let latestProgressDate = [latestWorkoutDate, latestSessionDate, goal.completedAt, goal.updatedAt, goal.lastCheckInPromptAt]
                    .compactMap { $0 }
                    .max() ?? goal.createdAt

                let daysSinceProgress = Calendar.current.dateComponents([.day], from: latestProgressDate, to: now).day ?? 0
                return daysSinceProgress >= goal.effectiveCheckInCadenceDays
            }
            .sorted { lhs, rhs in
                let lhsDate = [lhs.updatedAt, lhs.lastCheckInPromptAt, lhs.createdAt].compactMap { $0 }.max() ?? lhs.createdAt
                let rhsDate = [rhs.updatedAt, rhs.lastCheckInPromptAt, rhs.createdAt].compactMap { $0 }.max() ?? rhs.createdAt
                return lhsDate < rhsDate
            }
    }

    static func matchingCompletedSessions(
        for goal: WorkoutGoal,
        in sessions: [WorkoutSession]
    ) -> [WorkoutSession] {
        sessions
            .filter { goal.matches(session: $0) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    private static func insight(
        for goal: WorkoutGoal,
        workouts: [LiveWorkout],
        sessions: [WorkoutSession],
        exerciseHistory: [ExerciseHistory],
        useLbs: Bool
    ) -> WorkoutGoalInsight {
        let matchingWorkouts = workouts.filter { workout in
            workout.completedAt != nil && goal.matches(workout: workout)
        }
        let matchingSessions = sessions.filter { goal.matches(session: $0) }

        let matchingEntries = matchingWorkouts.flatMap { workout in
            (workout.entries ?? []).filter { entry in
                guard let activityName = goal.trimmedActivityName?.goalNormalizedKey else {
                    return true
                }
                return entry.exerciseName.goalNormalizedKey == activityName
            }
        }

        let latestSupportingNote = latestNote(
            from: matchingEntries,
            fallbackTo: matchingWorkouts,
            or: matchingSessions
        )
        let trimmedGoalNotes = goal.trimmedNotes

        switch goal.goalKind {
        case .milestone:
            let progressText: String
            if goal.status == .completed {
                progressText = "Completed"
            } else if latestSupportingNote != nil {
                progressText = "Recent progress logged"
            } else {
                progressText = "Use notes and completed sessions to track this"
            }

            let supportingText = latestSupportingNote ?? (trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes)

            return WorkoutGoalInsight(
                goal: goal,
                progressText: progressText,
                supportingText: supportingText,
                progressFraction: goal.status == .completed ? 1.0 : nil,
                currentValueText: nil,
                targetValueText: nil
            )

        case .frequency:
            let frequencyProgress = frequencyProgress(
                for: goal,
                workouts: matchingWorkouts,
                sessions: matchingSessions,
                now: Date()
            )

            let targetValueText = goal.targetValue.map {
                "\(Int($0.rounded())) \(goal.targetUnit.isEmpty ? "sessions" : goal.targetUnit) / \(goal.periodLabelText)"
            }

            let progressText: String
            if let currentCount = frequencyProgress.currentCount {
                progressText = "\(currentCount) of \(targetValueText ?? "target")"
            } else {
                progressText = "No sessions logged in this period yet"
            }

            let supportingParts = [
                frequencyProgress.periodRangeText,
                latestSupportingNote,
                trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes
            ].compactMap { $0 }

            return WorkoutGoalInsight(
                goal: goal,
                progressText: progressText,
                supportingText: supportingParts.isEmpty ? nil : supportingParts.joined(separator: "\n"),
                progressFraction: goal.status == .completed ? 1.0 : frequencyProgress.progressFraction,
                currentValueText: frequencyProgress.currentCount.map { "\($0)" },
                targetValueText: targetValueText
            )

        case .duration:
            let currentSeconds: Double? = {
                let sessionMax = matchingSessions.compactMap { session -> Double? in
                    guard let durationMinutes = session.durationMinutes, durationMinutes > 0 else { return nil }
                    return durationMinutes * 60
                }.max()

                if goal.trimmedActivityName != nil {
                    let entryMax = matchingEntries.compactMap { entry -> Double? in
                        guard let durationSeconds = entry.durationSeconds, durationSeconds > 0 else { return nil }
                        return Double(durationSeconds)
                    }.max()
                    return max(entryMax ?? 0, sessionMax ?? 0) == 0 ? nil : max(entryMax ?? 0, sessionMax ?? 0)
                }

                let workoutMax = matchingWorkouts.map(\.duration).filter { $0 > 0 }.max()
                return max(workoutMax ?? 0, sessionMax ?? 0) == 0 ? nil : max(workoutMax ?? 0, sessionMax ?? 0)
            }()

            return numericInsight(
                for: goal,
                currentBaseValue: currentSeconds,
                formattedCurrentValue: currentSeconds.map { formatDuration(seconds: $0, unit: goal.targetUnit) },
                supportingText: latestSupportingNote ?? (trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes)
            )

        case .distance:
            let entryMeters = matchingEntries.compactMap { entry -> Double? in
                guard let distanceMeters = entry.distanceMeters, distanceMeters > 0 else { return nil }
                return distanceMeters
            }.max()
            let sessionMeters = matchingSessions.compactMap { session -> Double? in
                guard let distanceMeters = session.distanceMeters, distanceMeters > 0 else { return nil }
                return distanceMeters
            }.max()
            let currentMeters = max(entryMeters ?? 0, sessionMeters ?? 0) == 0 ? nil : max(entryMeters ?? 0, sessionMeters ?? 0)

            return numericInsight(
                for: goal,
                currentBaseValue: currentMeters,
                formattedCurrentValue: currentMeters.map { formatDistance(meters: $0, unit: goal.targetUnit) },
                supportingText: latestSupportingNote ?? (trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes)
            )

        case .weight:
            let currentKg: Double?
            let liveEntryMax = matchingEntries
                .flatMap(\.sets)
                .compactMap(\.weightKg)
                .filter { $0 > 0 }
                .max()
            if let activityName = goal.trimmedActivityName {
                let exerciseHistoryMax = exerciseHistory
                    .filter { $0.exerciseName.goalNormalizedKey == activityName.goalNormalizedKey }
                    .compactMap(\.bestSetWeightKg)
                    .max()
                let sessionMax = matchingSessions.compactMap(\.weightKg).max()
                let bestKnownWeight = max(exerciseHistoryMax ?? 0, sessionMax ?? 0, liveEntryMax ?? 0)
                currentKg = bestKnownWeight == 0 ? nil : bestKnownWeight
            } else {
                let sessionMax = matchingSessions.compactMap(\.weightKg).max()
                let bestKnownWeight = max(sessionMax ?? 0, liveEntryMax ?? 0)
                currentKg = bestKnownWeight == 0 ? nil : bestKnownWeight
            }

            // Auto-baseline: the weight you were at when you created this goal.
            // Uses the most recent matching workout at or before goal.createdAt, so progress
            // shows improvement since the goal was set, not since you started lifting.
            let autoBaselineKg: Double?
            if goal.baselineValue == nil {
                // matchingWorkouts is sorted newest-first; find closest one at/before creation
                let atCreation = matchingWorkouts.first {
                    ($0.completedAt ?? $0.startedAt) <= goal.createdAt
                }
                let activityNormalizedName = goal.trimmedActivityName?.goalNormalizedKey
                let entryWeights = (atCreation?.entries ?? [])
                    .filter { activityNormalizedName == nil || $0.exerciseName.goalNormalizedKey == activityNormalizedName }
                    .flatMap(\.sets)
                    .compactMap(\.weightKg)
                    .filter { $0 > 0 }
                autoBaselineKg = entryWeights.max()
            } else {
                autoBaselineKg = nil
            }

            return numericInsight(
                for: goal,
                currentBaseValue: currentKg,
                formattedCurrentValue: currentKg.map {
                    formatWeight(kg: $0, unit: goal.targetUnit, useLbsFallback: useLbs)
                },
                supportingText: latestSupportingNote ?? (trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes),
                autoBaselineBaseValue: autoBaselineKg
            )
        }
    }

    private static func numericInsight(
        for goal: WorkoutGoal,
        currentBaseValue: Double?,
        formattedCurrentValue: String?,
        supportingText: String?,
        autoBaselineBaseValue: Double? = nil
    ) -> WorkoutGoalInsight {
        guard let targetValue = goal.targetValue, targetValue > 0 else {
            return WorkoutGoalInsight(
                goal: goal,
                progressText: "Add a target to track progress",
                supportingText: supportingText,
                progressFraction: nil,
                currentValueText: formattedCurrentValue,
                targetValueText: nil
            )
        }

        let currentDisplayValue = currentBaseValue.map { convertedValue(for: $0, kind: goal.goalKind, unit: goal.targetUnit) }
        let autoBaselineDisplayValue: Double? = autoBaselineBaseValue.map { raw in
            let converted = convertedValue(for: raw, kind: goal.goalKind, unit: goal.targetUnit)
            // Round weight baselines the same way WeightUtility.format does (2.5 lbs / 0.5 kg increments)
            // so baseline display matches the current value display and avoids "130.1 lbs" artifacts.
            if goal.goalKind == .weight {
                let weightUnit: WeightUnit = (goal.targetUnit.lowercased() == "lbs" || goal.targetUnit.lowercased() == "lb") ? .lbs : .kg
                return WeightUtility.round(converted, unit: weightUnit)
            }
            return converted
        }
        let targetValueText = formatTarget(targetValue, unit: goal.targetUnit)
        let currentValueText = formattedCurrentValue

        // Effective baseline: prefer explicit user-set value, fall back to auto-derived from training history.
        // Without a baseline we can't tell how much progress was made
        // (e.g. 130 lbs on a 140 lb goal when you started at 130 is 0% progress, not 93%).
        let effectiveBaseline: Double? = goal.baselineValue ?? autoBaselineDisplayValue

        let progressFraction: Double?
        if goal.status == .completed {
            progressFraction = 1.0
        } else if let current = currentDisplayValue, let baseline = effectiveBaseline, targetValue != baseline {
            progressFraction = min(max((current - baseline) / (targetValue - baseline), 0), 1)
        } else {
            progressFraction = nil
        }

        let progressText: String
        if let currentValueText {
            progressText = "\(currentValueText) of \(targetValueText)"
        } else {
            progressText = "No logged progress yet"
        }

        let baselineValueText = effectiveBaseline.map { formatTarget($0, unit: goal.targetUnit) }

        return WorkoutGoalInsight(
            goal: goal,
            progressText: progressText,
            supportingText: supportingText,
            progressFraction: progressFraction,
            currentValueText: currentValueText,
            targetValueText: targetValueText,
            baselineValueText: baselineValueText
        )
    }

    private static func signal(from workout: LiveWorkout) -> RecentWorkoutSignal? {
        guard let note = latestNote(in: workout), !note.isEmpty else { return nil }
        let subtitle = [workout.type.displayName, workout.displayFocusSummary, workout.formattedDuration]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        return RecentWorkoutSignal(
            title: workout.name,
            subtitle: subtitle,
            note: note,
            date: workout.completedAt ?? workout.startedAt
        )
    }

    private static func signal(from session: WorkoutSession) -> RecentWorkoutSignal? {
        guard session.hasSignalNote else { return nil }
        let subtitle = [session.displayTypeName, session.formattedDuration, session.formattedDistance]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        return RecentWorkoutSignal(
            title: session.displayName,
            subtitle: subtitle,
            note: session.trimmedNotes,
            date: session.loggedAt
        )
    }

    private static func latestNote(in workout: LiveWorkout) -> String? {
        let workoutNote = workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workoutNote.isEmpty {
            return workoutNote
        }

        return latestNote(
            from: workout.entries ?? [],
            fallbackTo: []
        )
    }

    private static func latestNote(in session: WorkoutSession) -> String? {
        let note = session.trimmedNotes
        return note.isEmpty ? nil : note
    }

    private static func latestNote(
        from entries: [LiveWorkoutEntry],
        fallbackTo workouts: [LiveWorkout],
        or sessions: [WorkoutSession] = []
    ) -> String? {
        if let entryNote = entries
            .sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
            .map(\.notes)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return entryNote
        }

        return workouts
            .sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
            .compactMap { latestNote(in: $0) }
            .first
            ?? sessions
            .sorted(by: { $0.loggedAt > $1.loggedAt })
            .compactMap { latestNote(in: $0) }
            .first
    }

    private static func convertedValue(for baseValue: Double, kind: WorkoutGoal.GoalKind, unit: String) -> Double {
        switch kind {
        case .frequency:
            return baseValue
        case .duration:
            switch unit.lowercased() {
            case "hr", "hrs", "hour", "hours":
                return baseValue / 3600
            default:
                return baseValue / 60
            }
        case .distance:
            switch unit.lowercased() {
            case "mi", "mile", "miles":
                return baseValue / 1609.344
            case "m":
                return baseValue
            default:
                return baseValue / 1000
            }
        case .weight:
            switch unit.lowercased() {
            case "lbs", "lb":
                return baseValue * WeightUtility.kgToLbs
            default:
                return baseValue
            }
        case .milestone:
            return baseValue
        }
    }

    private static func formatDuration(seconds: Double, unit: String) -> String {
        let converted = convertedValue(for: seconds, kind: .duration, unit: unit)
        return formatTarget(converted, unit: unit.isEmpty ? "min" : unit)
    }

    private static func formatDistance(meters: Double, unit: String) -> String {
        let displayUnit = unit.isEmpty ? "km" : unit
        let converted = convertedValue(for: meters, kind: .distance, unit: displayUnit)
        return formatTarget(converted, unit: displayUnit)
    }

    private static func formatWeight(kg: Double, unit: String, useLbsFallback: Bool) -> String {
        let displayUnitStr = unit.isEmpty ? (useLbsFallback ? "lbs" : "kg") : unit
        let weightUnit: WeightUnit = (displayUnitStr.lowercased() == "lbs" || displayUnitStr.lowercased() == "lb") ? .lbs : .kg
        // Use WeightUtility so we get the same rounding (2.5 lbs / 0.5 kg) as everywhere else in the app.
        return WeightUtility.format(kg, displayUnit: weightUnit)
    }

    static func formatTarget(_ value: Double, unit: String) -> String {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedValue: String
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            formattedValue = "\(Int(value.rounded()))"
        } else {
            formattedValue = String(format: "%.1f", value)
        }
        return trimmedUnit.isEmpty ? formattedValue : "\(formattedValue) \(trimmedUnit)"
    }

    private struct FrequencyProgressSnapshot {
        let currentCount: Int?
        let progressFraction: Double?
        let periodRangeText: String?
    }

    private static func frequencyProgress(
        for goal: WorkoutGoal,
        workouts: [LiveWorkout],
        sessions: [WorkoutSession],
        now: Date
    ) -> FrequencyProgressSnapshot {
        guard let targetValue = goal.targetValue, targetValue > 0 else {
            return FrequencyProgressSnapshot(currentCount: nil, progressFraction: nil, periodRangeText: nil)
        }

        let calendar = Calendar.current
        let periodCount = max(goal.periodCount ?? 1, 1)
        let periodUnit = goal.periodUnit ?? .week

        let periodStart: Date
        switch periodUnit {
        case .day:
            let startOfToday = calendar.startOfDay(for: now)
            periodStart = calendar.date(byAdding: .day, value: -(periodCount - 1), to: startOfToday) ?? startOfToday
        case .week:
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            periodStart = calendar.date(byAdding: .weekOfYear, value: -(periodCount - 1), to: currentWeek) ?? currentWeek
        case .month:
            let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            periodStart = calendar.date(byAdding: .month, value: -(periodCount - 1), to: currentMonth) ?? currentMonth
        }

        let workoutCount = workouts
            .filter { ($0.completedAt ?? $0.startedAt) >= periodStart }
            .count
        let sessionCount = sessions
            .filter { $0.loggedAt >= periodStart }
            .count
        let currentCount = workoutCount + sessionCount

        let progressFraction = min(max(Double(currentCount) / targetValue, 0), 1)
        let periodRangeText = "Current \(goal.periodLabelText) started \(periodStart.formatted(date: .abbreviated, time: .omitted))"

        return FrequencyProgressSnapshot(
            currentCount: currentCount,
            progressFraction: progressFraction,
            periodRangeText: periodRangeText
        )
    }
}

struct SessionGoalsCard: View {
    let goals: [WorkoutGoal]
    let onAddGoal: () -> Void
    let onToggleCompletion: (WorkoutGoal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Working Toward", systemImage: "scope")
                    .font(.headline)

                Spacer()

                Button("Add Goal", systemImage: "plus") {
                    onAddGoal()
                }
                .font(.caption.weight(.semibold))
            }

            if goals.isEmpty {
                Text("Add an optional goal for this session type or a specific activity. Trai can use it during the workout, and completed sessions can show note-based progress toward it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(goals.prefix(3)) { goal in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: goal.goalKind.iconName)
                            .font(.subheadline)
                            .foregroundStyle(goal.status == .completed ? .green : .accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.trimmedTitle)
                                .font(.subheadline.weight(.semibold))

                            Text(goal.scopeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !goal.trimmedNotes.isEmpty {
                                Text(goal.trimmedNotes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Button {
                            onToggleCompletion(goal)
                        } label: {
                            Image(systemName: goal.status == .completed ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(goal.status == .completed ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .traiCard()
    }
}

struct WorkoutGoalProgressCard: View {
    let insights: [WorkoutGoalInsight]
    var showsAddGoal: Bool = true
    let onAddGoal: () -> Void
    let onToggleCompletion: (WorkoutGoal) -> Void
    var onGoalTap: ((WorkoutGoal) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsAddGoal {
                TraiSectionHeader("Working Toward", icon: "scope") {
                    Button("Add Goal", systemImage: "plus", action: onAddGoal)
                        .buttonStyle(.traiTertiary(size: .compact, height: 32))
                }
            } else {
                TraiSectionHeader("Working Toward", icon: "scope")
            }

            if insights.isEmpty {
                Text("Add a goal for this workout type or a specific activity to see progress here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    goalRow(insight)
                }
            }
        }
        .traiCard()
    }

    private func goalRow(_ insight: WorkoutGoalInsight) -> some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.goal.goalKind.iconName)
                    .font(.subheadline)
                    .foregroundStyle(insight.goal.status == .completed ? .green : .accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.goal.trimmedTitle)
                        .font(.subheadline.weight(.semibold))

                    Text(insight.goal.scopeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if insight.goal.goalKind == .milestone {
                    Button {
                        onToggleCompletion(insight.goal)
                    } label: {
                        Text(insight.goal.status == .completed ? "Done" : "Mark Done")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (insight.goal.status == .completed ? Color.green : Color.accentColor)
                                    .opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(insight.goal.status == .completed ? .green : .accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let progressFraction = insight.progressFraction {
                ProgressView(value: progressFraction)
                    .tint(insight.goal.status == .completed ? .green : .accentColor)
            }

            Text(insight.progressText)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let supportingText = insight.supportingText {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)

        if let onGoalTap {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    onGoalTap(insight.goal)
                }
        } else {
            content
        }
    }
}

struct RecentWorkoutSignalsCard: View {
    let signals: [RecentWorkoutSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TraiSectionHeader("Recent Signals", icon: "text.quote")

            if signals.isEmpty {
                Text("No recent notes yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(signals) { signal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(signal.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(signal.date, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !signal.subtitle.isEmpty {
                            Text(signal.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(signal.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .traiCard()
    }
}

struct WorkoutGoalsOverviewSection: View {
    let insights: [WorkoutGoalInsight]
    let signals: [RecentWorkoutSignal]
    let celebratedGoal: WorkoutGoal?
    let canCreateGoalsWithTrai: Bool
    let onCreateGoalWithTrai: () -> Void
    let onUnlockPro: () -> Void
    let staleCheckInGoal: WorkoutGoal?
    let onGoalTap: (WorkoutGoal) -> Void
    let onToggleCompletion: (WorkoutGoal) -> Void

    private var activeGoalCount: Int {
        insights.filter { $0.goal.status == .active }.count
    }

    private var featuredInsight: WorkoutGoalInsight? {
        insights.first { $0.goal.status == .active } ?? insights.first
    }

    private var supportingInsights: [WorkoutGoalInsight] {
        guard let featuredInsight else { return [] }
        return insights.filter { $0.id != featuredInsight.id }
    }

    private var visibleSignals: [RecentWorkoutSignal] {
        Array(signals.prefix(canCreateGoalsWithTrai ? 2 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canCreateGoalsWithTrai {
                TraiSectionHeader("Goals & Signals", icon: "scope") {
                    Button("Set Goals", action: onCreateGoalWithTrai)
                        .buttonStyle(.traiTertiary(size: .compact, height: 32))
                }
            } else {
                TraiSectionHeader("Signals", icon: "scope")
            }

            if let celebratedGoal {
                celebratedGoalCard(celebratedGoal)
            }

            if insights.isEmpty && signals.isEmpty {
                emptyStateCard
            } else if !canCreateGoalsWithTrai {
                lockedSignalsState
            } else {
                if let featuredInsight {
                    featuredGoalCard(featuredInsight)
                }

                if let staleCheckInGoal {
                    staleCheckInCard(staleCheckInGoal)
                }

                if let firstSignal = visibleSignals.first {
                    signalRow(firstSignal)
                }
            }
        }
        .traiCard(glow: .activity)
    }

    private var emptyStateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(canCreateGoalsWithTrai ? "Set goals with Trai" : "Unlock goal coaching")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(canCreateGoalsWithTrai ? "Turn a route, lift, or routine into something trackable." : "Trai Pro can turn training into trackable goals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }

    private var lockedSignalsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let firstSignal = visibleSignals.first {
                signalRow(firstSignal)
            }

            ProUpsellInlineCard(
                source: .workoutPlan,
                actionTitle: "Unlock Trai Pro",
                action: onUnlockPro
            )
        }
    }

    private func featuredGoalCard(_ insight: WorkoutGoalInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.goal.goalKind.iconName)
                    .font(.headline)
                    .foregroundStyle(insight.goal.status == .completed ? .green : TraiColors.flame)
                    .frame(width: 36, height: 36)
                    .background(
                        (insight.goal.status == .completed ? Color.green.opacity(0.12) : TraiColors.flame.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.goal.trimmedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(insight.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if let progressFraction = insight.progressFraction {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progressFraction)
                        .tint(insight.goal.status == .completed ? .green : TraiColors.flame)

                    HStack {
                        if let current = insight.currentValueText {
                            compactMetric(label: "Current", value: current)
                        }
                        if let target = insight.targetValueText {
                            compactMetric(label: "Target", value: target)
                        }
                    }
                }
            }

            if insight.goal.goalKind == .milestone {
                Button {
                    onToggleCompletion(insight.goal)
                } label: {
                    Label(
                        insight.goal.status == .completed ? "Completed" : "Mark Done",
                        systemImage: insight.goal.status == .completed ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(insight.goal.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            onGoalTap(insight.goal)
        }
    }

    private func staleCheckInCard(_ goal: WorkoutGoal) -> some View {
        Button {
            onGoalTap(goal)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "message.badge.waveform.fill")
                    .font(.headline)
                    .foregroundStyle(TraiColors.brandAccent)
                    .frame(width: 38, height: 38)
                    .background(TraiColors.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Time to check in")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(goal.trimmedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Trai can review or refresh it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(TraiPressStyle())
    }

    private func celebratedGoalCard(_ goal: WorkoutGoal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(TraiColors.flame, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Goal achieved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(goal.trimmedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text("Completed from recent training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [TraiColors.flame.opacity(0.18), Color.accentColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func signalRow(_ signal: RecentWorkoutSignal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !signal.subtitle.isEmpty {
                        Text(signal.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(signal.date, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(signal.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }

    private func compactMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ActivityItem: Identifiable {
    let id = UUID()
    let date: Date
    let name: String
    let detail: String
    let workout: LiveWorkout?
    let session: WorkoutSession?
}

struct WorkoutGoalDetailSheet: View {
    @Bindable var goal: WorkoutGoal
    let workouts: [LiveWorkout]
    let sessions: [WorkoutSession]
    let exerciseHistory: [ExerciseHistory]
    let useLbs: Bool
    let onToggleCompletion: (WorkoutGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @State private var selectedWorkout: LiveWorkout?
    @State private var selectedSession: WorkoutSession?
    @State private var showingCheckIn = false
    @State private var showingEditGoal = false
    @State private var showDeleteConfirmation = false

    private var insight: WorkoutGoalInsight {
        WorkoutGoalProgressResolver.insights(
            goals: [goal],
            workouts: workouts,
            sessions: sessions,
            exerciseHistory: exerciseHistory,
            useLbs: useLbs
        ).first ?? WorkoutGoalInsight(
            goal: goal,
            progressText: "No progress yet",
            supportingText: nil,
            progressFraction: nil,
            currentValueText: nil,
            targetValueText: nil
        )
    }

    private var relatedWorkouts: [LiveWorkout] {
        WorkoutGoalProgressResolver.matchingCompletedWorkouts(for: goal, in: workouts)
    }

    private var relatedSessions: [WorkoutSession] {
        WorkoutGoalProgressResolver.matchingCompletedSessions(for: goal, in: sessions)
    }

    private var relatedSignals: [RecentWorkoutSignal] {
        WorkoutGoalProgressResolver.signals(for: goal, in: workouts, sessions: sessions)
    }

    private var latestCompletedDate: Date? {
        let workoutDate = relatedWorkouts.first?.completedAt ?? relatedWorkouts.first?.startedAt
        let sessionDate = relatedSessions.first?.loggedAt
        switch (workoutDate, sessionDate) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private var allSessionDates: [Date] {
        // Only count sessions after the goal was created
        let workoutDates = relatedWorkouts
            .compactMap { $0.completedAt ?? $0.startedAt }
            .filter { $0 >= goal.createdAt }
        let sessionDates = relatedSessions
            .map(\.loggedAt)
            .filter { $0 >= goal.createdAt }
        return workoutDates + sessionDates
    }

    private var recentActivityItems: [ActivityItem] {
        // Only sessions after the goal was created
        let workoutItems = relatedWorkouts
            .filter { ($0.completedAt ?? $0.startedAt) >= goal.createdAt }
            .map { w in
                ActivityItem(
                    date: w.completedAt ?? w.startedAt,
                    name: w.name,
                    detail: [w.displayFocusSummary, w.formattedDuration].filter { !$0.isEmpty }.joined(separator: " • "),
                    workout: w,
                    session: nil
                )
            }
        let sessionItems = relatedSessions
            .filter { $0.loggedAt >= goal.createdAt }
            .map { s in
                ActivityItem(
                    date: s.loggedAt,
                    name: s.displayName,
                    detail: [s.displayTypeName, s.formattedDuration, s.formattedDistance].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "),
                    workout: nil,
                    session: s
                )
            }
        return (workoutItems + sessionItems).sorted { $0.date > $1.date }
    }

    private var goalAccentColor: Color {
        goal.status == .completed ? .green : TraiColors.flame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    detailHeader
                    activitySection
                    if !recentActivityItems.isEmpty {
                        sessionsSection
                    }
                    if !relatedSignals.isEmpty || !goal.trimmedNotes.isEmpty {
                        notesSection
                    }
                }
                .padding()
            }
            .traiBackground()
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit Goal", systemImage: "pencil") {
                            showingEditGoal = true
                        }
                        Button("Delete Goal", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                LiveWorkoutDetailSheet(workout: workout, useLbs: useLbs)
                    .traiSheetBranding()
            }
            .sheet(item: $selectedSession) { session in
                WorkoutDetailSheet(workout: session)
                    .traiSheetBranding()
            }
            .sheet(isPresented: $showingCheckIn) {
                WorkoutGoalCheckInView(
                    goal: goal,
                    insight: insight,
                    workouts: workouts,
                    sessions: sessions
                )
                .traiSheetBranding()
            }
            .sheet(isPresented: $showingEditGoal) {
                AddWorkoutGoalSheet(
                    editGoal: goal,
                    activitySuggestions: [],
                    prefersMetricWeight: !useLbs
                )
                .traiSheetBranding()
            }
            .confirmationDialog("Delete Goal", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(goal)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(goal.trimmedTitle)\" and all its progress.")
            }
        }
        .traiSheetBranding()
        .proUpsellPresenter()
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [goalAccentColor, goalAccentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: goal.goalKind.iconName)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if goal.status == .completed {
                            goalStatusPill(goal)
                        }
                        Text(goal.scopeSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(goal.trimmedTitle)
                        .font(.traiHeadline(17))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }

            if let progressFraction = insight.progressFraction {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progressFraction)
                        .tint(goalAccentColor)

                    HStack {
                        Text(insight.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let target = insight.targetValueText {
                            Text(target)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(goalAccentColor)
                        }
                    }
                }
            } else {
                Text(insight.progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if goal.goalKind == .milestone {
                Button {
                    onToggleCompletion(goal)
                } label: {
                    Label(
                        goal.status == .completed ? "Completed" : "Mark Done",
                        systemImage: goal.status == .completed ? "checkmark.circle.fill" : "circle"
                    )
                }
                .buttonStyle(.traiSecondary(color: goal.status == .completed ? .green : goalAccentColor, fullWidth: true))
            }

            Button("Check in with Trai", systemImage: "circle.hexagongrid.circle") {
                if monetizationService?.canAccessAIFeatures ?? true {
                    showingCheckIn = true
                } else {
                    proUpsellCoordinator?.present(source: .workoutPlan)
                }
            }
            .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true))
        }
        .padding(16)
        .traiCard(glow: .workout, cornerRadius: 20, contentPadding: 0)
    }

    private func goalStatusPill(_ goal: WorkoutGoal) -> some View {
        Text(goal.status == .completed ? "Completed" : "Active")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (goal.status == .completed ? Color.green.opacity(0.16) : Color.accentColor.opacity(0.14)),
                in: Capsule()
            )
            .foregroundStyle(goal.status == .completed ? .green : Color.accentColor)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let totalCount = relatedWorkouts.count + relatedSessions.count
            TraiSectionHeader("Activity", icon: "chart.bar.fill") {
                if totalCount > 0 {
                    Text("\(totalCount) session\(totalCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if allSessionDates.isEmpty {
                Text("No completed sessions match this goal yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SessionWeeklyBars(sessionDates: allSessionDates)

                HStack {
                    Text("Past 8 weeks")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let latestDate = latestCompletedDate {
                        Text("Latest \(latestDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .traiCard()
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraiSectionHeader("Sessions", icon: "clock.arrow.circlepath")

            ForEach(Array(recentActivityItems.prefix(5))) { item in
                if let workout = item.workout {
                    LiveWorkoutHistoryRow(
                        workout: workout,
                        activeGoals: [goal],
                        onTap: { selectedWorkout = workout },
                        onDelete: {}
                    )
                } else if let session = item.session {
                    WorkoutHistoryRow(
                        workout: session,
                        onTap: { selectedSession = session },
                        onDelete: {}
                    )
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TraiSectionHeader("Notes", icon: "text.quote")
                .padding(.bottom, 12)

            if !goal.trimmedNotes.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.hexagongrid.circle")
                        .font(.subheadline)
                        .foregroundStyle(TraiColors.brandAccent)
                        .frame(width: 32, height: 32)
                        .background(TraiColors.brandAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Goal notes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let promptDate = goal.lastCheckInPromptAt {
                                Text(promptDate, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(goal.trimmedNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }

                if !relatedSignals.isEmpty {
                    Divider().padding(.vertical, 12)
                }
            }

            ForEach(Array(relatedSignals.prefix(4).enumerated()), id: \.element.id) { index, signal in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(signal.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(signal.date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(signal.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .traiCard()
    }
}

private struct SessionWeeklyBars: View {
    let sessionDates: [Date]

    private let weekCount = 8
    private let maxBarHeight: CGFloat = 44
    private let minBarHeight: CGFloat = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(weekData, id: \.0) { _, count, label in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(count > 0 ? TraiColors.flame : Color(.tertiarySystemFill))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(for: count))
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func barHeight(for count: Int) -> CGFloat {
        let maxCount = weekData.map(\.1).max() ?? 1
        guard maxCount > 0 else { return minBarHeight }
        return max(minBarHeight, maxBarHeight * CGFloat(count) / CGFloat(maxCount))
    }

    private var weekData: [(Int, Int, String)] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<weekCount).map { i in
            let weekOffset = -(weekCount - 1 - i)
            let anchorDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today) ?? today
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: anchorDate) else {
                return (i, 0, "")
            }
            let count = sessionDates.filter { $0 >= weekInterval.start && $0 < weekInterval.end }.count
            let label = weekInterval.start.formatted(.dateTime.month(.abbreviated))
            return (i, count, label)
        }
    }
}

struct AddWorkoutGoalSheet: View {
    private enum GoalScope: String, CaseIterable, Identifiable {
        case session
        case activity

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .session: "Session"
            case .activity: "Activity"
            }
        }
    }

    private func goalStatusPill(_ goal: WorkoutGoal) -> some View {
        Text(goal.status == .completed ? "Completed" : "Active")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (goal.status == .completed ? Color.green.opacity(0.16) : Color.accentColor.opacity(0.14)),
                in: Capsule()
            )
            .foregroundStyle(goal.status == .completed ? .green : Color.accentColor)
    }

    @Environment(\.dismiss) private var dismiss

    let workoutType: WorkoutMode?
    let activitySuggestions: [String]
    let prefersMetricWeight: Bool
    let onSave: (WorkoutGoal) -> Void
    private let editingGoal: WorkoutGoal?

    @State private var title = ""
    @State private var goalKind: WorkoutGoal.GoalKind = .milestone
    @State private var scope: GoalScope = .session
    @State private var selectedWorkoutType: WorkoutMode
    @State private var activityName = ""
    @State private var targetValueText = ""
    @State private var baselineValueText = ""
    @State private var targetUnit: String
    @State private var periodUnit: WorkoutGoal.PeriodUnit = .week
    @State private var periodCountText = "1"
    @State private var targetDateEnabled = false
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 42, to: Date()) ?? Date()
    @State private var checkInCadenceDaysText = ""
    @State private var notes = ""

    /// Create a new goal.
    init(
        workoutType: WorkoutMode?,
        activitySuggestions: [String],
        prefersMetricWeight: Bool,
        onSave: @escaping (WorkoutGoal) -> Void
    ) {
        self.workoutType = workoutType
        self.activitySuggestions = activitySuggestions
        self.prefersMetricWeight = prefersMetricWeight
        self.onSave = onSave
        self.editingGoal = nil
        _selectedWorkoutType = State(initialValue: workoutType ?? .custom)
        _targetUnit = State(initialValue: Self.defaultUnit(for: .milestone, prefersMetricWeight: prefersMetricWeight))
    }

    /// Edit an existing goal. Changes are written directly to the `@Model` object on save.
    init(
        editGoal existing: WorkoutGoal,
        activitySuggestions: [String],
        prefersMetricWeight: Bool,
        onSave: @escaping (WorkoutGoal) -> Void = { _ in }
    ) {
        self.workoutType = existing.linkedWorkoutType
        self.activitySuggestions = activitySuggestions
        self.prefersMetricWeight = prefersMetricWeight
        self.onSave = onSave
        self.editingGoal = existing
        _title = State(initialValue: existing.title)
        _goalKind = State(initialValue: existing.goalKind)
        _scope = State(initialValue: existing.trimmedActivityName != nil ? .activity : .session)
        _selectedWorkoutType = State(initialValue: existing.linkedWorkoutType ?? .custom)
        _activityName = State(initialValue: existing.linkedActivityName ?? "")
        _targetValueText = State(initialValue: Self.formatDoubleForField(existing.targetValue))
        _baselineValueText = State(initialValue: Self.formatDoubleForField(existing.baselineValue))
        _targetUnit = State(
            initialValue: existing.targetUnit.isEmpty
                ? Self.defaultUnit(for: existing.goalKind, prefersMetricWeight: prefersMetricWeight)
                : existing.targetUnit
        )
        _periodUnit = State(initialValue: existing.periodUnit ?? .week)
        _periodCountText = State(initialValue: existing.periodCount.map { "\($0)" } ?? "1")
        _targetDateEnabled = State(initialValue: existing.targetDate != nil)
        _targetDate = State(initialValue: existing.targetDate ?? Calendar.current.date(byAdding: .day, value: 42, to: Date()) ?? Date())
        _checkInCadenceDaysText = State(initialValue: existing.checkInCadenceDays.map { "\($0)" } ?? "")
        _notes = State(initialValue: existing.notes)
    }

    private static func formatDoubleForField(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value.rounded()))"
            : String(format: "%.1f", value)
    }

    private var unitOptions: [String] {
        switch goalKind {
        case .milestone:
            return []
        case .frequency:
            return ["sessions"]
        case .duration:
            return ["min", "hr"]
        case .distance:
            return prefersMetricWeight ? ["km", "m"] : ["mi", "km"]
        case .weight:
            return prefersMetricWeight ? ["kg", "lbs"] : ["lbs", "kg"]
        }
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (scope == .activity && activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
        (goalKind.supportsNumericTarget && Double(targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Goal", systemImage: "scope")
                            .font(.headline)

                        TextField("e.g. Send the blue V5 clean, Hold a 60 minute flow, Hit 225 on bench", text: $title)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(WorkoutGoal.GoalKind.allCases) { kind in
                                    Button {
                                        goalKind = kind
                                        targetUnit = Self.defaultUnit(for: kind, prefersMetricWeight: prefersMetricWeight)
                                    } label: {
                                        Label(kind.displayName, systemImage: kind.iconName)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                (goalKind == kind ? Color.accentColor : Color(.tertiarySystemFill)),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(goalKind == kind ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .traiCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Track Against", systemImage: "figure.walk.motion")
                            .font(.headline)

                        Picker("Scope", selection: $scope) {
                            ForEach(GoalScope.allCases) { goalScope in
                                Text(goalScope.displayName).tag(goalScope)
                            }
                        }
                        .pickerStyle(.segmented)

                        if workoutType == nil {
                            Picker("Session Type", selection: $selectedWorkoutType) {
                                ForEach(WorkoutMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Label(selectedWorkoutType.displayName, systemImage: selectedWorkoutType.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(scope == .session ? "This goal will follow your \(selectedWorkoutType.displayName.lowercased()) sessions." : "Attach this goal to a specific activity name so recent notes and metrics are more focused.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if scope == .activity {
                            TextField("Activity name", text: $activityName)
                                .padding(12)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                            if !activitySuggestions.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(activitySuggestions, id: \.self) { suggestion in
                                        Button(suggestion) {
                                            activityName = suggestion
                                        }
                                        .font(.caption)
                                        .buttonStyle(.traiSecondary(size: .compact, fullWidth: false))
                                    }
                                }
                            }
                        }
                    }
                    .traiCard()

                    if goalKind.supportsNumericTarget {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Target", systemImage: "target")
                                .font(.headline)

                            HStack(spacing: 10) {
                                TextField("Target value", text: $targetValueText)
                                    .keyboardType(.decimalPad)
                                    .padding(12)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                                Picker("Unit", selection: $targetUnit) {
                                    ForEach(unitOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if goalKind != .frequency {
                                TextField(
                                    "Starting point (optional, e.g. \(targetUnit.isEmpty ? "130" : "130 \(targetUnit)"))",
                                    text: $baselineValueText
                                )
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                                Text("Used to calculate real progress — how far you've come, not just where you are.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if goalKind == .frequency {
                                HStack(spacing: 10) {
                                    TextField("Period count", text: $periodCountText)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                                    Picker("Period", selection: $periodUnit) {
                                        ForEach(WorkoutGoal.PeriodUnit.allCases) { option in
                                            Text(option.displayName).tag(option)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                        .traiCard()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Timing", systemImage: "calendar")
                            .font(.headline)

                        Toggle("Add a soft target date", isOn: $targetDateEnabled)

                        if targetDateEnabled {
                            DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }

                        TextField("Check in every X days (optional)", text: $checkInCadenceDaysText)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .traiCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notes", systemImage: "note.text")
                            .font(.headline)

                        TextEditor(text: $notes)
                            .frame(minHeight: 110)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .traiCard()
                }
                .padding()
            }
            .navigationTitle(editingGoal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let baseline = goalKind != .frequency
                            ? Double(baselineValueText.trimmingCharacters(in: .whitespacesAndNewlines))
                            : nil

                        if let existing = editingGoal {
                            existing.title = trimmedTitle
                            existing.goalKindRaw = goalKind.rawValue
                            existing.linkedWorkoutTypeRaw = selectedWorkoutType.rawValue
                            existing.linkedActivityName = scope == .activity
                                ? activityName.trimmingCharacters(in: .whitespacesAndNewlines)
                                : nil
                            existing.targetValue = goalKind.supportsNumericTarget
                                ? Double(targetValueText.trimmingCharacters(in: .whitespacesAndNewlines))
                                : nil
                            existing.targetUnit = goalKind.supportsNumericTarget ? targetUnit : ""
                            existing.periodUnitRaw = goalKind.usesPeriodTarget ? periodUnit.rawValue : nil
                            existing.periodCount = goalKind.usesPeriodTarget
                                ? Int(periodCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
                                : nil
                            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                            existing.targetDate = targetDateEnabled ? targetDate : nil
                            existing.checkInCadenceDays = Int(checkInCadenceDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
                            existing.baselineValue = baseline
                            existing.updatedAt = Date()
                        } else {
                            let newGoal = WorkoutGoal(
                                title: trimmedTitle,
                                goalKind: goalKind,
                                linkedWorkoutType: selectedWorkoutType,
                                linkedActivityName: scope == .activity ? activityName : nil,
                                targetValue: goalKind.supportsNumericTarget ? Double(targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                                targetUnit: goalKind.supportsNumericTarget ? targetUnit : "",
                                periodUnit: goalKind.usesPeriodTarget ? periodUnit : nil,
                                periodCount: goalKind.usesPeriodTarget ? Int(periodCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1 : nil,
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                targetDate: targetDateEnabled ? targetDate : nil,
                                checkInCadenceDays: Int(checkInCadenceDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                                baselineValue: baseline
                            )
                            onSave(newGoal)
                        }
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isSaveDisabled)
                    .tint(.accentColor)
                }
            }
        }
        .traiSheetBranding()
    }

    private static func defaultUnit(for kind: WorkoutGoal.GoalKind, prefersMetricWeight: Bool) -> String {
        switch kind {
        case .milestone:
            return ""
        case .frequency:
            return "sessions"
        case .duration:
            return "min"
        case .distance:
            return prefersMetricWeight ? "km" : "mi"
        case .weight:
            return prefersMetricWeight ? "kg" : "lbs"
        }
    }
}
