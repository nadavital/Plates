//
//  AllWorkoutsSheet.swift
//  Trai
//
//  Full workout history sheet showing all workouts grouped by date
//

import SwiftUI

// MARK: - All Workouts Sheet

struct AllWorkoutsSheet: View {
    let workoutsByDate: [(date: Date, workouts: [WorkoutSession])]
    let liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])]
    let activeGoals: [WorkoutGoal]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDelete: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    @Environment(\.dismiss) private var dismiss

    private var allDates: [Date] {
        let sessionDates = Set(workoutsByDate.map { $0.date })
        let liveDates = Set(liveWorkoutsByDate.map { $0.date })
        return sessionDates.union(liveDates).sorted(by: >)
    }

    private func sessions(for date: Date) -> [WorkoutSession] {
        workoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    private func liveWorkouts(for date: Date) -> [LiveWorkout] {
        liveWorkoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allDates, id: \.self) { date in
                    Section {
                        // LiveWorkouts first
                        ForEach(liveWorkouts(for: date)) { workout in
                            LiveWorkoutListRow(workout: workout, activeGoals: activeGoals) {
                                onLiveWorkoutTap(workout)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteLiveWorkout(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        // WorkoutSessions
                        ForEach(sessions(for: date)) { workout in
                            WorkoutSessionListRow(workout: workout) {
                                onWorkoutTap(workout)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(date, format: .dateTime.weekday(.wide).month().day())
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Workout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .traiSheetBranding()
    }
}

// MARK: - Live Workout List Row (for List context)

private struct LiveWorkoutListRow: View {
    let workout: LiveWorkout
    let activeGoals: [WorkoutGoal]
    let onTap: () -> Void

    private var entryCount: Int { workout.entries?.count ?? 0 }
    private var strengthEntryCount: Int { workout.entries?.filter(\.isStrength).count ?? 0 }
    private var totalSets: Int { workout.entries?.reduce(0) { $0 + $1.sets.count } ?? 0 }
    private var completedActivityCount: Int {
        workout.entries?.filter { ($0.isCardio || $0.isGeneralActivity) && $0.completedAt != nil }.count ?? 0
    }
    private var durationMinutes: Int { Int(workout.duration / 60) }
    private var matchedGoalCount: Int { activeGoals.filter { $0.matches(workout: workout) }.count }

    private var focusSummary: String? {
        let summary = workout.displayFocusSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.caseInsensitiveCompare(workout.name) != .orderedSame else { return nil }
        return summary
    }

    private var summarySegments: [String] {
        var segments: [String] = []

        if workout.type.prefersStructuredEntries || strengthEntryCount > 0 {
            if entryCount > 0 {
                segments.append("\(entryCount) \(entryCount == 1 ? "exercise" : "exercises")")
            }
            if totalSets > 0 {
                segments.append("\(totalSets) \(totalSets == 1 ? "set" : "sets")")
            }
        } else {
            if entryCount > 0 {
                segments.append("\(entryCount) \(entryCount == 1 ? "activity" : "activities")")
            }
            if completedActivityCount > 0 {
                segments.append("\(completedActivityCount) done")
            }
        }

        if durationMinutes > 0 {
            segments.append("\(durationMinutes) min")
        }

        return segments
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: workout.type.iconName)
                    .font(.body)
                    .foregroundStyle(.accent)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let focusSummary {
                        Text(focusSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    WorkoutHistoryInsightBadges(
                        matchedGoalCount: matchedGoalCount,
                        hasSignalNote: workout.hasHistorySignalNote
                    )

                    HStack(spacing: 6) {
                        ForEach(Array(summarySegments.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(segment)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Session List Row (for List context)

private struct WorkoutSessionListRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void

    private var detailSegments: [String] {
        var segments: [String] = []

        if workout.isStrengthTraining {
            segments.append("\(workout.sets)×\(workout.reps)")
        } else {
            segments.append(workout.displayTypeName)

            if let duration = workout.formattedDuration {
                segments.append(duration)
            }
            if let distance = workout.formattedDistance {
                segments.append(distance)
            }
        }

        if let calories = workout.caloriesBurned {
            segments.append("\(calories) kcal")
        }

        return segments
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: workout.iconName)
                    .font(.body)
                    .foregroundStyle(workout.sourceIsHealthKit ? .red : .accent)
                    .frame(width: 32, height: 32)
                    .background((workout.sourceIsHealthKit ? Color.red : Color.accentColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    WorkoutHistoryInsightBadges(
                        matchedGoalCount: 0,
                        hasSignalNote: workout.hasSignalNote
                    )

                    HStack(spacing: 6) {
                        ForEach(Array(detailSegments.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(segment)
                                .foregroundStyle(segment.hasSuffix("kcal") ? .red : .secondary)
                        }

                        if workout.sourceIsHealthKit {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
