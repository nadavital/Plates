//
//  TraiWidgetsLiveActivity.swift
//  TraiWidgets
//
//  Live Activity for workout tracking on Lock Screen and Dynamic Island
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum LiveActivityTheme {
    static let traiSymbol = "circle.hexagongrid.circle"
    static let accent = Color.red
    static let muted = Color.secondary

    static func statusIcon(isPaused: Bool) -> String {
        isPaused ? "pause.fill" : traiSymbol
    }

    static func statusColor(isPaused: Bool) -> Color {
        isPaused ? muted : accent
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
                Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                    .font(.caption)
                    .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))
            }
            .widgetURL(URL(string: "trai://workout"))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

// MARK: - Lock Screen View

private struct LockScreenWorkoutView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>
    @Environment(\.activityFamily) private var activityFamily

    private var isSmallFamily: Bool {
        if #available(iOS 18.0, *) {
            return activityFamily == .small
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Status (no timer per user feedback)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                            .font(.caption)
                            .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

                        Text(context.attributes.workoutName)
                            .font(isSmallFamily ? .subheadline : .headline)
                            .lineLimit(1)
                    }

                    if let exercise = context.state.currentExercise {
                        HStack(spacing: 4) {
                            Text(exercise)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            // Show equipment if available
                            if !isSmallFamily, let equipment = context.state.currentEquipment {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(equipment)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            // Show current weight × reps if available
                            if let setDisplay = context.state.currentSetDisplay {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(setDisplay)
                                    .font(.caption)
                                    .foregroundStyle(LiveActivityTheme.accent)
                            }
                        }
                    }

                    // Show next exercise if available
                    if !isSmallFamily, let nextExercise = context.state.nextExercise {
                        HStack(spacing: 4) {
                            Text("Next:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(nextExercise)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Progress and sets
                VStack(alignment: .trailing, spacing: 6) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                            .frame(width: isSmallFamily ? 36 : 44, height: isSmallFamily ? 36 : 44)

                        Circle()
                            .trim(from: 0, to: context.state.progress)
                            .stroke(LiveActivityTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: isSmallFamily ? 36 : 44, height: isSmallFamily ? 36 : 44)
                            .rotationEffect(.degrees(-90))

                        Text("\(context.state.completedSets)")
                            .font(.system(isSmallFamily ? .caption2 : .caption, design: .rounded, weight: .bold))
                    }

                    Text(context.state.setsDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Volume if available
                    if let volume = context.state.volumeDisplay {
                        Text(volume)
                            .font(.caption2)
                            .foregroundStyle(LiveActivityTheme.accent)
                    }

                    // Heart rate display (shows "--" when unavailable)
                    if !isSmallFamily {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            if let hr = context.state.heartRate {
                                Text("\(hr)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("--")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            
            // Action buttons
            if !isSmallFamily {
                HStack(spacing: 12) {
                    Button(intent: AddSetIntent()) {
                        Label("Add Set", systemImage: "plus.circle.fill")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(LiveActivityTheme.accent)

                    Button(intent: TogglePauseIntent()) {
                        Label(
                            context.state.isPaused ? "Resume" : "Pause",
                            systemImage: context.state.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(context.state.isPaused ? LiveActivityTheme.accent : LiveActivityTheme.muted)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(LiveActivityTheme.accent)
    }
}

// MARK: - Dynamic Island Views

private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                .font(.title2)
                .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

            // Heart rate display (shows "--" when unavailable)
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                if let hr = context.state.heartRate {
                    Text("\(hr)")
                        .font(.caption2)
                } else {
                    Text("--")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Volume display (no timer per user feedback)
            if let volume = context.state.volumeDisplay {
                Text(volume)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(LiveActivityTheme.accent)
            }

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
                        .fill(LiveActivityTheme.accent)
                        .frame(width: geometry.size.width * context.state.progress)
                }
            }
            .frame(height: 6)

            HStack {
                // Current exercise with set info
                if let exercise = context.state.currentExercise {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Now:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(exercise)
                                .font(.caption)
                                .lineLimit(1)
                        }

                        if let setDisplay = context.state.currentSetDisplay {
                            Text(setDisplay)
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.accent)
                        }
                    }
                }

                Spacer()

                // Volume display
                if let volume = context.state.volumeDisplay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Volume")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(volume)
                            .font(.caption)
                            .foregroundStyle(LiveActivityTheme.accent)
                    }
                }
            }
        }
    }
}

private struct CompactLeadingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                .font(.caption)
                .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

            // Show current exercise instead of timer
            if let exercise = context.state.currentExercise {
                Text(exercise)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<TraiWorkoutAttributes>

    var body: some View {
        Text("\(context.state.completedSets)/\(context.state.totalSets)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(LiveActivityTheme.accent)
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
            currentEquipment: "Smith Machine",
            completedSets: 8,
            totalSets: 15,
            heartRate: 142,
            isPaused: false,
            currentWeightKg: 80,
            currentWeightLbs: 176,
            currentReps: 8,
            totalVolumeKg: 2450,
            totalVolumeLbs: 5401,
            nextExercise: "Incline Dumbbell Press"
        )
    }

    static var paused: TraiWorkoutAttributes.ContentState {
        TraiWorkoutAttributes.ContentState(
            elapsedSeconds: 2100,
            currentExercise: "Overhead Press",
            currentEquipment: nil,
            completedSets: 10,
            totalSets: 15,
            heartRate: 98,
            isPaused: true,
            currentWeightKg: 50,
            currentWeightLbs: 110,
            currentReps: 10,
            totalVolumeKg: 3200,
            totalVolumeLbs: 7055,
            nextExercise: "Lateral Raises"
        )
    }
}

#Preview("Notification", as: .content, using: TraiWorkoutAttributes.preview) {
    TraiWidgetsLiveActivity()
} contentStates: {
    TraiWorkoutAttributes.ContentState.active
    TraiWorkoutAttributes.ContentState.paused
}
