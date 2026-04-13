//
//  WorkoutGoalComponents.swift
//  Trai
//

import SwiftUI

struct WorkoutGoalInsight: Identifiable {
    let goal: WorkoutGoal
    let progressText: String
    let supportingText: String?
    let progressFraction: Double?
    let currentValueText: String?
    let targetValueText: String?

    var id: UUID { goal.id }
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

            return numericInsight(
                for: goal,
                currentBaseValue: currentKg,
                formattedCurrentValue: currentKg.map {
                    formatWeight(kg: $0, unit: goal.targetUnit, useLbsFallback: useLbs)
                },
                supportingText: latestSupportingNote ?? (trimmedGoalNotes.isEmpty ? nil : trimmedGoalNotes)
            )
        }
    }

    private static func numericInsight(
        for goal: WorkoutGoal,
        currentBaseValue: Double?,
        formattedCurrentValue: String?,
        supportingText: String?
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
        let targetValueText = formatTarget(targetValue, unit: goal.targetUnit)
        let currentValueText = formattedCurrentValue

        let progressFraction = currentDisplayValue.map { min(max($0 / targetValue, 0), 1) }
        let progressText: String
        if let currentValueText {
            progressText = "\(currentValueText) of \(targetValueText)"
        } else {
            progressText = "No logged progress yet"
        }

        return WorkoutGoalInsight(
            goal: goal,
            progressText: progressText,
            supportingText: supportingText,
            progressFraction: goal.status == .completed ? 1.0 : progressFraction,
            currentValueText: currentValueText,
            targetValueText: targetValueText
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
        let displayUnit = unit.isEmpty ? (useLbsFallback ? "lbs" : "kg") : unit
        let converted = convertedValue(for: kg, kind: .weight, unit: displayUnit)
        return formatTarget(converted, unit: displayUnit)
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
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
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
            HStack {
                Label("Working Toward", systemImage: "scope")
                    .font(.headline)

                Spacer()

                if showsAddGoal {
                    Button("Add Goal", systemImage: "plus") {
                        onAddGoal()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if insights.isEmpty {
                Text("Add a goal for this workout type or a specific activity to see progress here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 10) {
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onGoalTap?(insight.goal)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct RecentWorkoutSignalsCard: View {
    let signals: [RecentWorkoutSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Signals", systemImage: "text.quote")
                .font(.headline)

            Text("When there isn’t a perfect metric, recent notes still help Trai understand how this type of training is moving.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if signals.isEmpty {
                Text("No recent notes yet. Add a few short session notes and they’ll show up here as lightweight progression context.")
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
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
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
    let onCheckInWithTrai: (WorkoutGoal) -> Void
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
        Array(signals.prefix(canCreateGoalsWithTrai ? 4 : 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(canCreateGoalsWithTrai ? "Goals & Signals" : "Signals", systemImage: "scope")
                    .font(.headline)

                Spacer()

                Button(canCreateGoalsWithTrai ? "Set Goals" : "Trai Pro", systemImage: canCreateGoalsWithTrai ? "sparkles" : "lock.fill") {
                    if canCreateGoalsWithTrai {
                        onCreateGoalWithTrai()
                    } else {
                        onUnlockPro()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

            if let celebratedGoal {
                celebratedGoalCard(celebratedGoal)
            }

            if insights.isEmpty && signals.isEmpty {
                emptyStateCard
            } else if !canCreateGoalsWithTrai {
                lockedSignalsState
            } else {
                HStack(spacing: 8) {
                    summaryBadge(
                        title: activeGoalCount == 1 ? "1 active goal" : "\(activeGoalCount) active goals",
                        systemImage: "flag.2.crossed"
                    )

                    if !visibleSignals.isEmpty {
                        summaryBadge(
                            title: visibleSignals.count == 1 ? "1 recent signal" : "\(visibleSignals.count) recent signals",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                }

                if let featuredInsight {
                    featuredGoalCard(featuredInsight)
                }

                if let staleCheckInGoal {
                    staleCheckInCard(staleCheckInGoal)
                }

                if !supportingInsights.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(supportingInsights.prefix(4)) { insight in
                                supportingGoalCard(insight)
                            }
                        }
                    }
                }

                if !visibleSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Signals")
                            .font(.subheadline.weight(.semibold))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(visibleSignals) { signal in
                                    signalCard(signal)
                                }
                            }
                        }
                    }
                }
            }
        }
        .traiCard()
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "scope")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(canCreateGoalsWithTrai ? "Set Goals with Trai" : "Unlock Goal Coaching")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(canCreateGoalsWithTrai ? "Turn a route, lift, or routine into a goal." : "Trai Pro can turn training into trackable goals.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()
            }

            Text(canCreateGoalsWithTrai ? "Start with Trai when you're ready." : "Recent notes still show up here as signals.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TraiColors.brandGradient, in: RoundedRectangle(cornerRadius: 18))
    }

    private var lockedSignalsState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !visibleSignals.isEmpty {
                HStack(spacing: 8) {
                    summaryBadge(
                        title: visibleSignals.count == 1 ? "1 recent signal" : "\(visibleSignals.count) recent signals",
                        systemImage: "waveform.path.ecg"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Signals")
                        .font(.subheadline.weight(.semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(visibleSignals) { signal in
                                signalCard(signal)
                            }
                        }
                    }
                }
            }

            ProUpsellInlineCard(
                source: .workoutPlan,
                actionTitle: "Unlock Trai Pro",
                action: onUnlockPro
            )
        }
    }

    private func featuredGoalCard(_ insight: WorkoutGoalInsight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statusPill(insight.goal)

                        Text(insight.goal.scopeSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(insight.goal.trimmedTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(insight.progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: insight.goal.goalKind.iconName)
                    .font(.title2)
                    .foregroundStyle(insight.goal.status == .completed ? .green : TraiColors.flame)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
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

            if let supportingText = insight.supportingText {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    TraiColors.blaze.opacity(0.12),
                    Color.white.opacity(0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                onToggleCompletion(insight.goal)
            } label: {
                Image(systemName: insight.goal.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(insight.goal.status == .completed ? .green : .secondary)
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onGoalTap(insight.goal)
        }
    }

    private func staleCheckInCard(_ goal: WorkoutGoal) -> some View {
        Button {
            onCheckInWithTrai(goal)
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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

    private func supportingGoalCard(_ insight: WorkoutGoalInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: insight.goal.goalKind.iconName)
                    .font(.subheadline)
                    .foregroundStyle(insight.goal.status == .completed ? .green : .accentColor)

                Spacer()

                Button {
                    onToggleCompletion(insight.goal)
                } label: {
                    Image(systemName: insight.goal.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(insight.goal.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(insight.goal.trimmedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(insight.progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(insight.goal.scopeSummary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            onGoalTap(insight.goal)
        }
    }

    private func signalCard(_ signal: RecentWorkoutSignal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(signal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(signal.date, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(signal.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)

            if !signal.subtitle.isEmpty {
                Text(signal.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
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
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryBadge(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func statusPill(_ goal: WorkoutGoal) -> some View {
        Text(goal.status == .completed ? "Completed" : "Active")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (goal.status == .completed ? Color.green.opacity(0.16) : Color.accentColor.opacity(0.14)),
                in: Capsule()
            )
            .foregroundStyle(goal.status == .completed ? .green : .accentColor)
    }
}

struct WorkoutGoalDetailSheet: View {
    @Bindable var goal: WorkoutGoal
    let workouts: [LiveWorkout]
    let sessions: [WorkoutSession]
    let exerciseHistory: [ExerciseHistory]
    let useLbs: Bool
    let onToggleCompletion: (WorkoutGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: LiveWorkout?
    @State private var selectedSession: WorkoutSession?

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

    private var recentSessionCount: Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return relatedWorkouts.filter {
            ($0.completedAt ?? $0.startedAt) >= cutoffDate
        }.count
    }

    private var noteBackedSessionCount: Int {
        relatedSignals.count
    }

    private var momentumTitle: String {
        if goal.status == .completed {
            return "Goal completed"
        }
        if let progressFraction = insight.progressFraction, progressFraction >= 0.75 {
            return "Close to the target"
        }
        if recentSessionCount >= 4 {
            return "Strong recent momentum"
        }
        if recentSessionCount >= 2 || !storySignals.isEmpty {
            return "Momentum is building"
        }
        return "Just getting started"
    }

    private var momentumSubtitle: String {
        if goal.status == .completed {
            return "Keep logging sessions and notes so Trai can help you maintain it."
        }
        if let latestCompletedDate {
            return "You logged \(recentSessionCount) related \(recentSessionCount == 1 ? "session" : "sessions") in the last 30 days, most recently on \(latestCompletedDate.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Complete a related session or add a note and this view will start building a clearer progression story."
    }

    private var storySignals: [RecentWorkoutSignal] {
        Array(relatedSignals.prefix(3))
    }

    private var headlineMetricValue: String {
        if let currentValue = insight.currentValueText {
            return currentValue
        }
        return "\(relatedWorkouts.count + relatedSessions.count)"
    }

    private var headlineMetricLabel: String {
        if insight.currentValueText != nil {
            return "current progress"
        }
        let count = relatedWorkouts.count + relatedSessions.count
        return count == 1 ? "related session" : "related sessions"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    detailHeader

                    WorkoutGoalProgressCard(
                        insights: [insight],
                        showsAddGoal: false,
                        onAddGoal: {},
                        onToggleCompletion: onToggleCompletion
                    )

                    momentumSection

                    if !storySignals.isEmpty {
                        storySoFarSection
                    }

                    if !relatedSignals.isEmpty {
                        RecentWorkoutSignalsCard(signals: relatedSignals)
                    }

                    relatedSessionsSection
                }
                .padding()
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
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
        }
        .traiSheetBranding()
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        goalStatusPill(goal)

                        Text(goal.scopeSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(goal.trimmedTitle)
                        .font(.title2.weight(.semibold))

                    Text(insight.progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    if let latestCompletedDate {
                        Text("Latest related session \(latestCompletedDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Image(systemName: goal.goalKind.iconName)
                        .font(.title2)
                        .foregroundStyle(goal.status == .completed ? .green : TraiColors.flame)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(headlineMetricValue)
                            .font(.traiBold(24))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())

                        Text(headlineMetricLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !goal.trimmedNotes.isEmpty {
                Text(goal.trimmedNotes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                detailStat(title: "Sessions", value: "\(relatedWorkouts.count + relatedSessions.count)")

                if let progressText = insight.currentValueText {
                    detailStat(title: "Current", value: progressText)
                }

                if let targetText = insight.targetValueText {
                    detailStat(title: "Target", value: targetText)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    TraiColors.blaze.opacity(0.14),
                    Color.white.opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
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

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Momentum", systemImage: "figure.run")
                    .font(.headline)
                Spacer()
            }

            Text(momentumTitle)
                .font(.title3.weight(.semibold))

            Text(momentumSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                detailStat(title: "Last 30 Days", value: "\(recentSessionCount)")
                detailStat(title: "Sessions With Notes", value: "\(noteBackedSessionCount)")
                detailStat(
                    title: "Latest Update",
                    value: latestCompletedDate?.formatted(date: .abbreviated, time: .omitted) ?? "None yet"
                )
            }
        }
        .traiCard()
    }

    private var storySoFarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Story So Far", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Spacer()
            }

            Text("Recent notes often tell the clearest story for skill-based or custom training.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(Array(storySignals.enumerated()), id: \.element.id) { index, signal in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(index == 0 ? TraiColors.flame : Color.accentColor.opacity(0.7))
                                .frame(width: 10, height: 10)

                            if index < storySignals.count - 1 {
                                Rectangle()
                                    .fill(Color(.quaternaryLabel))
                                    .frame(width: 2)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(width: 12)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(signal.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(signal.date, format: .dateTime.month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !signal.subtitle.isEmpty {
                                Text(signal.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
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
        }
        .traiCard()
    }

    private var relatedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Related Sessions", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
            }

            if relatedWorkouts.isEmpty {
                if relatedSessions.isEmpty {
                    Text("No completed sessions match this goal yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !relatedWorkouts.isEmpty {
                ForEach(relatedWorkouts.prefix(6)) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: workout.type.iconName)
                                .font(.body)
                                .foregroundStyle(.accent)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text([workout.displayFocusSummary, workout.formattedDuration]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text((workout.completedAt ?? workout.startedAt), format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !relatedSessions.isEmpty {
                ForEach(relatedSessions.prefix(6)) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: session.iconName)
                                .font(.body)
                                .foregroundStyle(session.sourceIsHealthKit ? .red : .accent)
                                .frame(width: 32, height: 32)
                                .background(
                                    (session.sourceIsHealthKit ? Color.red : Color.accentColor).opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text([session.displayTypeName, session.formattedDuration, session.formattedDistance]
                                    .compactMap { $0 }
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(session.loggedAt, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .traiCard()
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
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

    @State private var title = ""
    @State private var goalKind: WorkoutGoal.GoalKind = .milestone
    @State private var scope: GoalScope = .session
    @State private var selectedWorkoutType: WorkoutMode
    @State private var activityName = ""
    @State private var targetValueText = ""
    @State private var targetUnit: String
    @State private var periodUnit: WorkoutGoal.PeriodUnit = .week
    @State private var periodCountText = "1"
    @State private var targetDateEnabled = false
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 42, to: Date()) ?? Date()
    @State private var checkInCadenceDaysText = ""
    @State private var notes = ""

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
        _selectedWorkoutType = State(initialValue: workoutType ?? .custom)
        _targetUnit = State(initialValue: Self.defaultUnit(for: .milestone, prefersMetricWeight: prefersMetricWeight))
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
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

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
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

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
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 16))
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
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notes", systemImage: "note.text")
                            .font(.headline)

                        TextEditor(text: $notes)
                            .frame(minHeight: 110)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let goal = WorkoutGoal(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            goalKind: goalKind,
                            linkedWorkoutType: selectedWorkoutType,
                            linkedActivityName: scope == .activity ? activityName : nil,
                            targetValue: goalKind.supportsNumericTarget ? Double(targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                            targetUnit: goalKind.supportsNumericTarget ? targetUnit : "",
                            periodUnit: goalKind.usesPeriodTarget ? periodUnit : nil,
                            periodCount: goalKind.usesPeriodTarget ? Int(periodCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1 : nil,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            targetDate: targetDateEnabled ? targetDate : nil,
                            checkInCadenceDays: Int(checkInCadenceDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
                        )
                        onSave(goal)
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
