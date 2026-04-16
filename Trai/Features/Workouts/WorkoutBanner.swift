//
//  WorkoutBanner.swift
//  Trai
//
//  Compact banner shown above tab bar when a workout is in progress
//

import SwiftUI

/// Compact banner view shown above tab bar when workout is active
struct WorkoutBanner: View {
    let workout: LiveWorkout
    let onTap: () -> Void
    let onEnd: () -> Void

    private struct BannerStats {
        let entryCount: Int
        let completedSets: Int
        let completedActivities: Int
        let strengthEntryCount: Int
    }

    private var stats: BannerStats {
        let entries = workout.entries ?? []
        let completedSets = entries.reduce(0) { total, entry in
            total + (entry.completedSets?.count ?? 0)
        }
        let completedActivities = entries.filter { ($0.isCardio || $0.isGeneralActivity) && $0.completedAt != nil }.count
        let strengthEntryCount = entries.filter(\.isStrength).count
        return BannerStats(
            entryCount: entries.count,
            completedSets: completedSets,
            completedActivities: completedActivities,
            strengthEntryCount: strengthEntryCount
        )
    }

    private var usesFlexibleSessionPresentation: Bool {
        let stats = stats
        return !workout.type.prefersStructuredEntries && stats.completedSets == 0
    }

    private func entrySummaryText(for stats: BannerStats) -> String? {
        guard stats.entryCount > 0 else { return nil }

        if usesFlexibleSessionPresentation || stats.strengthEntryCount == 0 {
            return "\(stats.entryCount) \(stats.entryCount == 1 ? "activity" : "activities")"
        }

        return "\(stats.entryCount) \(stats.entryCount == 1 ? "exercise" : "exercises")"
    }

    private func completionSummaryText(for stats: BannerStats) -> String? {
        if usesFlexibleSessionPresentation || stats.strengthEntryCount == 0 {
            guard stats.completedActivities > 0 else { return nil }
            return "\(stats.completedActivities) done"
        }

        guard stats.completedSets > 0 else { return nil }
        return "\(stats.completedSets) \(stats.completedSets == 1 ? "set" : "sets")"
    }

    private func formattedTime(at date: Date) -> String {
        let elapsedTime = date.timeIntervalSince(workout.startedAt)
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        let stats = stats

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
                    if let entrySummary = entrySummaryText(for: stats) {
                        Text(entrySummary)
                    }
                    if entrySummaryText(for: stats) != nil {
                        Text("•")
                            .foregroundStyle(.tertiary)
                    }
                    TimelineView(.periodic(from: workout.startedAt, by: 1.0)) { context in
                        Text(formattedTime(at: context.date))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Sets completed badge
            if let completionSummary = completionSummaryText(for: stats) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(completionSummary)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activeWorkoutBanner")
        .onTapGesture(perform: onTap)
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
                entry.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 60, lbs: 132.5), completed: true, isWarmup: false))
                entry.addSet(LiveWorkoutEntry.SetData(reps: 8, weight: CleanWeight(kg: 70, lbs: 155), completed: true, isWarmup: false))
                workout.entries = [entry]
                return workout
            }(),
            onTap: {},
            onEnd: {}
        )
        .background(Color(.systemBackground))
    }
}
