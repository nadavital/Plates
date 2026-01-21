//
//  TraiWidgetsLiveActivity.swift
//  TraiWidgets
//
//  Live Activity for workout tracking on Lock Screen and Dynamic Island
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Activity Attributes

/// Attributes for the Trai workout Live Activity
struct TraiWorkoutAttributes: ActivityAttributes {
    /// Static content that doesn't change during the workout
    let workoutName: String
    let targetMuscles: [String]
    let startedAt: Date

    /// Dynamic content that updates during the workout
    struct ContentState: Codable, Hashable {
        let elapsedSeconds: Int
        let currentExercise: String?
        let completedSets: Int
        let totalSets: Int
        let heartRate: Int?
        let isPaused: Bool

        /// Formatted elapsed time string (MM:SS or H:MM:SS)
        var formattedTime: String {
            let hours = elapsedSeconds / 3600
            let minutes = (elapsedSeconds % 3600) / 60
            let seconds = elapsedSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// Progress as a fraction (0.0 to 1.0)
        var progress: Double {
            guard totalSets > 0 else { return 0 }
            return Double(completedSets) / Double(totalSets)
        }

        /// Sets display string (e.g., "8/12 sets")
        var setsDisplay: String {
            "\(completedSets)/\(totalSets) sets"
        }
    }
}

// MARK: - Live Activity Widget

struct TraiWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TraiWorkoutAttributes.self) { context in
            // Lock Screen / Banner view
            LockScreenWorkoutView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.workoutName)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .font(.caption)
                    .foregroundStyle(context.state.isPaused ? .orange : .green)
            }
            .widgetURL(URL(string: "trai://workout"))
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenWorkoutView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Timer and status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                        .font(.caption)
                        .foregroundStyle(context.state.isPaused ? .orange : .green)

                    Text(context.attributes.workoutName)
                        .font(.headline)
                        .lineLimit(1)
                }

                Text(context.state.formattedTime)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundStyle(context.state.isPaused ? .orange : .primary)

                if let exercise = context.state.currentExercise {
                    Text(exercise)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Progress and sets
            VStack(alignment: .trailing, spacing: 8) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        .frame(width: 44, height: 44)

                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))

                    Text("\(context.state.completedSets)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }

                Text(context.state.setsDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Heart rate if available
                if let hr = context.state.heartRate {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("\(hr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color(.systemBackground))
    }
}

// MARK: - Dynamic Island Views

private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                .font(.title2)
                .foregroundStyle(context.state.isPaused ? .orange : .green)

            if let hr = context.state.heartRate {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text("\(hr)")
                        .font(.caption2)
                }
            }
        }
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.formattedTime)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(context.state.isPaused ? .orange : .primary)

            Text(context.state.setsDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExpandedBottomView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    Capsule()
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * context.state.progress)
                }
            }
            .frame(height: 6)

            // Current exercise
            if let exercise = context.state.currentExercise {
                HStack {
                    Text("Now:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(exercise)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }
}

private struct CompactLeadingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                .font(.caption)
                .foregroundStyle(context.state.isPaused ? .orange : .green)

            Text(context.state.formattedTime)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .monospacedDigit()
        }
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        Text("\(context.state.completedSets)/\(context.state.totalSets)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.orange)
    }
}

// MARK: - Previews

extension TraiWorkoutAttributes {
    static var preview: TraiWorkoutAttributes {
        TraiWorkoutAttributes(
            workoutName: "Push Day",
            targetMuscles: ["Chest", "Shoulders", "Triceps"],
            startedAt: Date()
        )
    }
}

extension TraiWorkoutAttributes.ContentState {
    static var active: TraiWorkoutAttributes.ContentState {
        TraiWorkoutAttributes.ContentState(
            elapsedSeconds: 1847,
            currentExercise: "Bench Press",
            completedSets: 8,
            totalSets: 15,
            heartRate: 142,
            isPaused: false
        )
    }

    static var paused: TraiWorkoutAttributes.ContentState {
        TraiWorkoutAttributes.ContentState(
            elapsedSeconds: 2100,
            currentExercise: "Overhead Press",
            completedSets: 10,
            totalSets: 15,
            heartRate: 98,
            isPaused: true
        )
    }
}

#Preview("Notification", as: .content, using: TraiWorkoutAttributes.preview) {
    TraiWidgetsLiveActivity()
} contentStates: {
    TraiWorkoutAttributes.ContentState.active
    TraiWorkoutAttributes.ContentState.paused
}
