//
//  ChatWorkoutCards.swift
//  Plates
//
//  Workout suggestion and logging cards for chat
//

import SwiftUI

// MARK: - Suggested Workout Card

struct SuggestedWorkoutCard: View {
    let workout: SuggestedWorkoutEntry
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.accent)
                Text("Start Workout?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Workout details
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(workout.exercises.count) exercises", systemImage: "list.bullet")
                    Label("\(workout.durationMinutes) min", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !workout.targetMuscleGroups.isEmpty {
                    Text(workout.muscleGroupsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !workout.rationale.isEmpty {
                    Text(workout.rationale)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))

            // Action buttons
            HStack(spacing: 12) {
                Button("Dismiss", systemImage: "xmark") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Start Workout", systemImage: "play.fill") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Started Badge

struct WorkoutStartedBadge: View {
    let workoutName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Started: \(workoutName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Suggested Workout Log Card

struct SuggestedWorkoutLogCard: View {
    let workoutLog: SuggestedWorkoutLog
    var useLbs: Bool = false
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.circle)
                }
            }

            // Workout name and summary
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutLog.displayName)
                    .font(.headline)

                HStack(spacing: 6) {
                    if !workoutLog.exercises.isEmpty {
                        Text("\(workoutLog.exercises.count) exercises")
                    }
                    if workoutLog.totalSets > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(workoutLog.totalSets) sets")
                    }
                    if let duration = workoutLog.durationMinutes, duration > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(duration) min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Exercise list with set rows
            if !workoutLog.exercises.isEmpty {
                VStack(spacing: 0) {
                    ForEach(workoutLog.exercises) { exercise in
                        WorkoutLogExerciseRow(exercise: exercise, useLbs: useLbs)
                        if exercise.id != workoutLog.exercises.last?.id {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 10))
            }

            // Notes if any
            if let notes = workoutLog.notes, !notes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Action button
            Button {
                onAccept()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                    Text("Log Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Log Exercise Row

private struct WorkoutLogExerciseRow: View {
    let exercise: SuggestedWorkoutLog.LoggedExercise
    let useLbs: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exercise name
            Text(exercise.name)
                .font(.subheadline)
                .fontWeight(.medium)

            // Sets as rows (reps on left, weight on right)
            VStack(spacing: 4) {
                ForEach(exercise.sets.indices, id: \.self) { index in
                    let set = exercise.sets[index]
                    HStack {
                        Text("Set \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .leading)

                        Text("\(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let weight = set.weightKg, weight > 0 {
                            let displayWeight = useLbs ? Int(weight * 2.20462) : Int(weight)
                            let unit = useLbs ? "lbs" : "kg"
                            Text("\(displayWeight) \(unit)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Workout Log Saved Badge

struct WorkoutLogSavedBadge: View {
    let workoutType: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Logged: \(workoutType)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}
