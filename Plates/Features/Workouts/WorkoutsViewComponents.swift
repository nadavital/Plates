//
//  WorkoutsViewComponents.swift
//  Plates
//
//  Supporting card components for WorkoutsView
//

import SwiftUI

// MARK: - Quick Start Card

struct QuickStartCard: View {
    let onStartBlankWorkout: () -> Void

    var body: some View {
        Button(action: onStartBlankWorkout) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Custom Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Add exercises as you go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active Workout Banner

struct ActiveWorkoutBanner: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Pulsing indicator
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.green.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in Progress")
                        .font(.subheadline)
                        .bold()
                    Text(workout.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(workout.formattedDuration)
                    .font(.headline)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.15))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.green.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Todays Workout Summary

struct TodaysWorkoutSummary: View {
    let workouts: [WorkoutSession]
    var liveWorkouts: [LiveWorkout] = []

    private var totalWorkoutCount: Int {
        workouts.count + liveWorkouts.count
    }

    private var totalDuration: Int {
        let sessionDuration = workouts.compactMap { $0.durationMinutes }.reduce(0) { $0 + Int($1) }
        let liveDuration = liveWorkouts.reduce(0) { $0 + Int($1.duration / 60) }
        return sessionDuration + liveDuration
    }

    private var totalCalories: Int {
        let sessionCalories = workouts.compactMap(\.caloriesBurned).reduce(0, +)
        let liveCalories = liveWorkouts.compactMap { $0.healthKitCalories.map { Int($0) } }.reduce(0, +)
        return sessionCalories + liveCalories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Activity", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
            }

            if totalWorkoutCount == 0 {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.secondary)
                    Text("No workouts yet today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 24) {
                    WorkoutStatItem(
                        value: "\(totalWorkoutCount)",
                        label: totalWorkoutCount == 1 ? "workout" : "workouts",
                        icon: "figure.run",
                        color: .orange
                    )

                    if totalDuration > 0 {
                        WorkoutStatItem(
                            value: "\(totalDuration)",
                            label: "minutes",
                            icon: "clock.fill",
                            color: .blue
                        )
                    }

                    if totalCalories > 0 {
                        WorkoutStatItem(
                            value: "\(totalCalories)",
                            label: "kcal",
                            icon: "flame.fill",
                            color: .red
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Stat Item

struct WorkoutStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ActiveWorkoutBanner(
                workout: {
                    let w = LiveWorkout(name: "Push Day", workoutType: .strength, targetMuscleGroups: [.chest, .shoulders, .triceps])
                    return w
                }(),
                onTap: {}
            )

            TodaysWorkoutSummary(workouts: [])
        }
        .padding()
    }
}
