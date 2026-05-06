//
//  WorkoutHistorySection.swift
//  Trai
//
//  Section component showing recent workouts with "See All" functionality
//

import SwiftUI

// MARK: - Workout History Section

struct WorkoutHistorySection: View {
    private enum PreviewItem: Identifiable {
        case live(LiveWorkout)
        case session(WorkoutSession)

        var id: String {
            switch self {
            case .live(let workout):
                return "live-\(workout.id.uuidString)"
            case .session(let workout):
                return "session-\(workout.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .live(let workout):
                return workout.completedAt ?? workout.startedAt
            case .session(let workout):
                return workout.loggedAt
            }
        }
    }

    let workoutsByDate: [(date: Date, workouts: [WorkoutSession])]
    let liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])]
    let activeGoals: [WorkoutGoal]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDelete: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    @State private var showAllWorkouts = false

    private var previewItems: [PreviewItem] {
        let liveItems = liveWorkoutsByDate
            .flatMap(\.workouts)
            .map(PreviewItem.live)
        let sessionItems = workoutsByDate
            .flatMap(\.workouts)
            .map(PreviewItem.session)

        return (liveItems + sessionItems)
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { $0 }
    }

    /// Total workout count for "See All" button
    private var totalWorkoutCount: Int {
        let sessionCount = workoutsByDate.reduce(0) { $0 + $1.workouts.count }
        let liveCount = liveWorkoutsByDate.reduce(0) { $0 + $1.workouts.count }
        return sessionCount + liveCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with See All button
            HStack {
                Label("Recent Workouts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.headline)
                Spacer()
                if totalWorkoutCount > 5 {
                    Button {
                        showAllWorkouts = true
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(.accent)
                    }
                }
            }

            if previewItems.isEmpty {
                EmptyWorkoutHistory()
            } else {
                VStack(spacing: 8) {
                    ForEach(previewItems) { item in
                        switch item {
                        case .live(let workout):
                            CompactLiveWorkoutRow(
                                workout: workout,
                                onTap: { onLiveWorkoutTap(workout) }
                            )
                        case .session(let workout):
                            CompactWorkoutSessionRow(
                                workout: workout,
                                onTap: { onWorkoutTap(workout) }
                            )
                        }
                    }
                }
            }
        }
        .traiCard()
        .sheet(isPresented: $showAllWorkouts) {
            AllWorkoutsSheet(
                workoutsByDate: workoutsByDate,
                liveWorkoutsByDate: liveWorkoutsByDate,
                activeGoals: activeGoals,
                onWorkoutTap: onWorkoutTap,
                onLiveWorkoutTap: onLiveWorkoutTap,
                onDelete: onDelete,
                onDeleteLiveWorkout: onDeleteLiveWorkout
            )
        }
    }
}

// MARK: - Compact Live Workout Row

private struct CompactLiveWorkoutRow: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    private var entryCount: Int { workout.entries?.count ?? 0 }
    private var strengthEntryCount: Int { workout.entries?.filter(\.isStrength).count ?? 0 }
    private var totalSets: Int { workout.entries?.reduce(0) { $0 + $1.sets.count } ?? 0 }
    private var completedActivityCount: Int {
        workout.entries?.filter { ($0.isCardio || $0.isGeneralActivity) && $0.completedAt != nil }.count ?? 0
    }
    private var durationMinutes: Int { Int(workout.duration / 60) }

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
                // Icon with colored background
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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Workout Session Row

private struct CompactWorkoutSessionRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void

    private var detailSegments: [String] {
        var segments: [String] = []

        if workout.isStrengthTraining {
            if workout.sets > 0 {
                segments.append("\(workout.sets) \(workout.sets == 1 ? "set" : "sets")")
            }
            if workout.reps > 0 {
                segments.append("\(workout.reps) reps")
            }
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
                // Icon with colored background
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
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
