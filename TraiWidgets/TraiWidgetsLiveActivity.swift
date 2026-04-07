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
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.82)
    static let textTertiary = Color.white.opacity(0.62)
    static let muted = textSecondary
    static let background = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let actionForeground = Color.white

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
            .widgetURL(AppRoute.workout(templateName: nil).url)
        }
        .supplementalActivityFamilies([.small])
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

    private var isMediumFamily: Bool {
        if #available(iOS 18.0, *) {
            return activityFamily == .medium
        }
        return false
    }

    private var isSupplementalFamily: Bool { isSmallFamily }

    var body: some View {
        if isSmallFamily {
            smallFamilyBody
        } else {
            regularBody
        }
    }

    private var shortenedWorkoutName: String {
        let firstWord = context.attributes.workoutName
            .split(separator: " ")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstWord, !firstWord.isEmpty, firstWord.count <= 14 {
            return firstWord
        }

        return "Workout"
    }

    private func compactExerciseName(_ exercise: String) -> String {
        let firstWord = exercise
            .split(separator: " ")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstWord, !firstWord.isEmpty, firstWord.count <= 14 {
            return firstWord
        }

        return "Current set"
    }

    private var mediumFamilyBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                    .font(.caption)
                    .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

                VStack(alignment: .leading, spacing: 3) {
                    ViewThatFits(in: .horizontal) {
                        Text(context.attributes.workoutName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Text(shortenedWorkoutName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("Workout")
                            .font(.subheadline)
                            .lineLimit(1)
                    }

                    if let exercise = context.state.currentExercise {
                        ViewThatFits(in: .horizontal) {
                            Text(exercise)
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Text(compactExerciseName(exercise))
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                            Text("Current set")
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text("\(context.state.completedSets)/\(context.state.totalSets)")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityTheme.accent)
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LiveActivityTheme.textPrimary.opacity(0.2))
                    Capsule()
                        .fill(LiveActivityTheme.accent)
                        .frame(width: geometry.size.width * context.state.progress)
                }
            }
            .frame(height: 5)
        }
        .foregroundStyle(LiveActivityTheme.textPrimary)
        .padding(12)
        .traiLiveActivityContainerBackground()
        .activityBackgroundTint(LiveActivityTheme.background)
        .activitySystemActionForegroundColor(LiveActivityTheme.actionForeground)
    }

    private var smallFamilyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                    .font(.caption)
                    .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

                ViewThatFits(in: .horizontal) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Text(shortenedWorkoutName)
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: LiveActivityTheme.traiSymbol)
                        .font(.caption)
                }
            }

            if let exercise = context.state.currentExercise {
                ViewThatFits(in: .horizontal) {
                    Text(exercise)
                        .font(.caption2)
                        .foregroundStyle(LiveActivityTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(compactExerciseName(exercise))
                        .font(.caption2)
                        .foregroundStyle(LiveActivityTheme.textSecondary)
                        .lineLimit(1)
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(LiveActivityTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LiveActivityTheme.textPrimary.opacity(0.2))
                    Capsule()
                        .fill(LiveActivityTheme.accent)
                        .frame(width: geometry.size.width * context.state.progress)
                }
            }
            .frame(height: 5)

            Text("\(context.state.completedSets)/\(context.state.totalSets)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(LiveActivityTheme.textSecondary)
                .lineLimit(1)
        }
        .foregroundStyle(LiveActivityTheme.textPrimary)
        .padding(12)
        .traiLiveActivityContainerBackground()
        .activityBackgroundTint(LiveActivityTheme.background)
        .activitySystemActionForegroundColor(LiveActivityTheme.actionForeground)
    }

    private var regularBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: isMediumFamily ? 12 : 16) {
                // Status (no timer per user feedback)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: LiveActivityTheme.statusIcon(isPaused: context.state.isPaused))
                            .font(.caption)
                            .foregroundStyle(LiveActivityTheme.statusColor(isPaused: context.state.isPaused))

                        Text(context.attributes.workoutName)
                            .font(isMediumFamily ? .subheadline : .headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if let exercise = context.state.currentExercise {
                        HStack(spacing: 4) {
                            Text(exercise)
                                .font(.caption)
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            // Show equipment if available
                            if !isSupplementalFamily, let equipment = context.state.currentEquipment {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(LiveActivityTheme.textTertiary)
                                Text(equipment)
                                    .font(.caption2)
                                    .foregroundStyle(LiveActivityTheme.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }

                            // Show current weight × reps if available
                            if let setDisplay = context.state.currentSetDisplay {
                                Text("•")
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textTertiary)
                                Text(setDisplay)
                                .font(.caption)
                                .foregroundStyle(LiveActivityTheme.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }
                        }
                    }

                    // Show next exercise if available
                    if !isSupplementalFamily, let nextExercise = context.state.nextExercise {
                        HStack(spacing: 4) {
                            Text("Next:")
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textTertiary)
                            Text(nextExercise)
                                .font(.caption2)
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .layoutPriority(1)

                Spacer()

                // Progress and sets
                VStack(alignment: .trailing, spacing: 6) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(LiveActivityTheme.textPrimary.opacity(0.2), lineWidth: 4)
                            .frame(width: isMediumFamily ? 36 : 44, height: isMediumFamily ? 36 : 44)

                        Circle()
                            .trim(from: 0, to: context.state.progress)
                            .stroke(LiveActivityTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: isMediumFamily ? 36 : 44, height: isMediumFamily ? 36 : 44)
                            .rotationEffect(.degrees(-90))

                        Text("\(context.state.completedSets)")
                            .font(.system(isMediumFamily ? .caption2 : .caption, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }

                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(LiveActivityTheme.textSecondary)
                        .lineLimit(1)

                    // Volume if available
                    if let volume = context.state.volumeDisplay {
                        Text(volume)
                            .font(.caption2)
                            .foregroundStyle(LiveActivityTheme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    // Heart rate display (shows "--" when unavailable)
                    if !isSupplementalFamily {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            if let hr = context.state.heartRate {
                                Text("\(hr)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(LiveActivityTheme.textSecondary)
                            } else {
                                Text("--")
                                    .font(.caption2)
                                    .foregroundStyle(LiveActivityTheme.textTertiary)
                            }
                        }
                    }
                }
            }
            
            // Action buttons
            if !isSupplementalFamily {
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
        .foregroundStyle(LiveActivityTheme.textPrimary)
        .padding()
        .traiLiveActivityContainerBackground()
        .activityBackgroundTint(LiveActivityTheme.background)
        .activitySystemActionForegroundColor(LiveActivityTheme.actionForeground)
    }
}

private extension View {
    @ViewBuilder
    func traiLiveActivityContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                LiveActivityTheme.background
            }
        } else {
            self.background(LiveActivityTheme.background)
        }
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
                        .foregroundStyle(LiveActivityTheme.textTertiary)
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
                .foregroundStyle(LiveActivityTheme.textSecondary)
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
                        .fill(LiveActivityTheme.textPrimary.opacity(0.2))

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
                                .foregroundStyle(LiveActivityTheme.textSecondary)
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
                            .foregroundStyle(LiveActivityTheme.textSecondary)
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

#if DEBUG
struct TraiWidgetsLiveActivity_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            if #available(iOSApplicationExtension 16.2, *) {
                TraiWorkoutAttributes.preview
                    .previewContext(TraiWorkoutAttributes.ContentState.active, viewKind: .content)
                    .previewDisplayName("Notification")

                TraiWorkoutAttributes.preview
                    .previewContext(TraiWorkoutAttributes.ContentState.paused, viewKind: .content)
                    .previewDisplayName("Paused")
            }
        }
    }
}
#endif
