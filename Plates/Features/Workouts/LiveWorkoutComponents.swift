//
//  LiveWorkoutComponents.swift
//  Plates
//
//  Core UI components for live workout tracking
//

import SwiftUI

// MARK: - Workout Timer Header

struct WorkoutTimerHeader: View {
    let workoutName: String
    let workoutStartedAt: Date
    let isTimerRunning: Bool
    let totalPauseDuration: TimeInterval
    let totalSets: Int
    let completedSets: Int
    let totalVolume: Double

    var body: some View {
        VStack(spacing: 16) {
            // Workout name and timer
            VStack(spacing: 4) {
                Text(workoutName)
                    .font(.headline)

                // Use TimelineView for smooth, scroll-friendly timer updates
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let elapsed = calculateElapsed(at: context.date)
                    Text(formatTime(elapsed))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }

            // Stats row
            HStack(spacing: 24) {
                TimerStat(
                    value: "\(completedSets)/\(totalSets)",
                    label: "Sets"
                )

                if totalVolume > 0 {
                    TimerStat(
                        value: formatVolume(totalVolume),
                        label: "Volume"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func calculateElapsed(at date: Date) -> TimeInterval {
        guard isTimerRunning else {
            // When paused, show the time at pause
            return date.timeIntervalSince(workoutStartedAt) - totalPauseDuration
        }
        return date.timeIntervalSince(workoutStartedAt) - totalPauseDuration
    }

    private func formatTime(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

// MARK: - Timer Stat

struct TimerStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add Exercise Button

struct AddExerciseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Add Exercise")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Bottom Bar

struct WorkoutBottomBar: View {
    let onEndWorkout: () -> Void
    let onAskTrai: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onAskTrai) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                    Text("Ask Trai")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onEndWorkout) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("End Workout")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
