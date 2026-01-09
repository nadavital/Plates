//
//  WorkoutHistoryRows.swift
//  Plates
//
//  Row and group components for displaying workout history
//

import SwiftUI

// MARK: - Combined Workout Date Group

struct CombinedWorkoutDateGroup: View {
    let date: Date
    let sessions: [WorkoutSession]
    let liveWorkouts: [LiveWorkout]
    let onSessionTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDeleteSession: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                // Show in-app workouts first (LiveWorkout)
                ForEach(liveWorkouts) { workout in
                    LiveWorkoutHistoryRow(
                        workout: workout,
                        onTap: { onLiveWorkoutTap(workout) },
                        onDelete: { onDeleteLiveWorkout(workout) }
                    )
                }

                // Then show HealthKit/session workouts
                ForEach(sessions) { workout in
                    WorkoutHistoryRow(
                        workout: workout,
                        onTap: { onSessionTap(workout) },
                        onDelete: { onDeleteSession(workout) }
                    )
                }
            }
        }
    }
}

// MARK: - Live Workout History Row

struct LiveWorkoutHistoryRow: View {
    let workout: LiveWorkout
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    private var exerciseCount: Int {
        workout.entries?.count ?? 0
    }

    private var totalSets: Int {
        workout.entries?.reduce(0) { $0 + ($1.sets.count) } ?? 0
    }

    private var durationMinutes: Int {
        Int(workout.duration / 60)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
                Image(systemName: workout.type == .cardio ? "figure.run" : "dumbbell.fill")
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
                        if exerciseCount > 0 {
                            Text("\(exerciseCount) exercises")
                        }
                        if totalSets > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(totalSets) sets")
                        }
                        if durationMinutes > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(durationMinutes) min")
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
            .contentShape(Rectangle())
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(workout.name)\"? This cannot be undone.")
        }
    }
}

// MARK: - Workout Date Group

struct WorkoutDateGroup: View {
    let date: Date
    let workouts: [WorkoutSession]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onDelete: (WorkoutSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(workouts) { workout in
                WorkoutHistoryRow(
                    workout: workout,
                    onTap: { onWorkoutTap(workout) },
                    onDelete: { onDelete(workout) }
                )
            }
        }
    }
}

// MARK: - Workout History Row

struct WorkoutHistoryRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
                Image(systemName: workout.isStrengthTraining ? "dumbbell.fill" : "figure.run")
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
                        if workout.isStrengthTraining {
                            Text("\(workout.sets)×\(workout.reps)")
                        } else {
                            if let duration = workout.formattedDuration {
                                Text(duration)
                            }
                            if let distance = workout.formattedDistance {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(distance)
                            }
                        }

                        if let calories = workout.caloriesBurned {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(calories) kcal")
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
            .contentShape(Rectangle())
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(workout.displayName)\"? This cannot be undone.")
        }
    }
}

// MARK: - Empty Workout History

struct EmptyWorkoutHistory: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No workouts yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Start your first workout to see it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
