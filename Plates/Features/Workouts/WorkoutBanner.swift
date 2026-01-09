//
//  WorkoutBanner.swift
//  Plates
//
//  Compact banner shown above tab bar when a workout is in progress
//

import SwiftUI

/// Compact banner view shown above tab bar when workout is active
struct WorkoutBanner: View {
    let workout: LiveWorkout
    let onTap: () -> Void
    let onEnd: () -> Void

    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var exerciseCount: Int {
        workout.entries?.count ?? 0
    }

    private var completedSets: Int {
        workout.entries?.reduce(0) { total, entry in
            total + (entry.completedSets?.count ?? 0)
        } ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing indicator
            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(.green.opacity(0.4), lineWidth: 2)
                        .scaleEffect(1.5)
                }

            // Workout info
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if exerciseCount > 0 {
                        Text("\(exerciseCount) exercises")
                    }
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(formattedTime)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Sets completed badge
            if completedSets > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("\(completedSets) sets")
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }

            // End button
            Button(action: onEnd) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        // Calculate initial elapsed time
        elapsedTime = Date().timeIntervalSince(workout.startedAt)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(workout.startedAt)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        WorkoutBanner(
            workout: {
                let workout = LiveWorkout(
                    name: "Push Day",
                    workoutType: .strength,
                    targetMuscleGroups: [.chest, .shoulders, .triceps]
                )
                let entry = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
                entry.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 60, completed: true, isWarmup: false))
                entry.addSet(LiveWorkoutEntry.SetData(reps: 8, weightKg: 70, completed: true, isWarmup: false))
                workout.entries = [entry]
                return workout
            }(),
            onTap: {},
            onEnd: {}
        )
        .background(Color(.systemBackground))
    }
}
