//
//  LiveWorkoutComponents.swift
//  Trai
//
//  Core UI components for live workout tracking
//

import SwiftUI

// MARK: - Workout Timer Header

struct WorkoutTimerHeader: View {
    let workoutStartedAt: Date
    let isTimerRunning: Bool
    let totalPauseDuration: TimeInterval
    let totalVolume: Double
    let onTogglePause: () -> Void

    // Optional Apple Watch data - only shown when available
    var heartRate: Double?
    var calories: Double?

    var body: some View {
        VStack(spacing: 16) {
            // Timer (centered)
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let elapsed = calculateElapsed(at: context.date)
                Text(formatTime(elapsed))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            // Pill-shaped pause/resume button
            Button(action: onTogglePause) {
                HStack(spacing: 6) {
                    Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                    Text(isTimerRunning ? "Pause" : "Resume")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(.capsule)
            }
            .buttonStyle(.plain)

            // Stats row - volume and optional watch data
            let hasWatchData = heartRate != nil || (calories ?? 0) > 0
            if totalVolume > 0 || hasWatchData {
                HStack(spacing: 24) {
                    if totalVolume > 0 {
                        TimerStat(
                            value: formatVolume(totalVolume),
                            label: "Volume"
                        )
                    }

                    if let hr = heartRate {
                        TimerStat(
                            value: "\(Int(hr))",
                            label: "BPM",
                            icon: "heart.fill",
                            iconColor: .red
                        )
                    }

                    if let cal = calories, cal > 0 {
                        TimerStat(
                            value: "\(Int(cal))",
                            label: "kcal",
                            icon: "flame.fill",
                            iconColor: .orange
                        )
                    }
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
    var icon: String?
    var iconColor: Color?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(iconColor ?? .primary)
                }
                Text(value)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
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
    let onAddExercise: () -> Void
    let onAskTrai: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onAskTrai) {
                HStack {
                    Image(systemName: "circle.hexagongrid.circle")
                    Text("Ask Trai")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onAddExercise) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
