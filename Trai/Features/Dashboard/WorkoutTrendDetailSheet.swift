//
//  WorkoutTrendDetailSheet.swift
//  Trai
//
//  Detailed workout trends view shown when tapping workout card on dashboard.
//

import SwiftUI
import SwiftData

/// Sheet displaying detailed workout trends and recent workout history
struct WorkoutTrendDetailSheet: View {
    let workouts: [LiveWorkout]
    var onStartWorkout: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var completedWorkouts: [LiveWorkout] {
        workouts.filter { $0.completedAt != nil }
    }

    private var last7DaysData: [TrendsService.DailyWorkout] {
        TrendsService.aggregateWorkoutsByDay(workouts: completedWorkouts, days: 7)
    }

    private var weekStats: WeekStats {
        let data = last7DaysData
        let totalWorkouts = data.reduce(0) { $0 + $1.workoutCount }
        let totalItems = data.reduce(0) { $0 + $1.totalEntries }
        let totalVolume = data.reduce(0.0) { $0 + $1.totalVolume }
        let totalMinutes = data.reduce(0) { $0 + $1.totalDurationMinutes }

        return WeekStats(
            workouts: totalWorkouts,
            items: totalItems,
            volume: totalVolume,
            minutes: totalMinutes
        )
    }

    private struct WeekStats {
        let workouts: Int
        let items: Int
        let volume: Double
        let minutes: Int
    }

    private var sessionTypeDistribution: [(group: String, count: Int)] {
        var distribution: [String: Int] = [:]

        for workout in completedWorkouts.prefix(20) {
            distribution[workout.type.displayName, default: 0] += 1
        }

        return distribution.sorted { $0.value > $1.value }
            .map { (group: $0.key, count: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Week summary stats
                    weekSummaryCard

                    // Workout frequency chart
                    WorkoutTrendChart(
                        data: last7DaysData,
                        metric: .frequency,
                        title: "Workout Frequency"
                    )

                    WorkoutTrendChart(
                        data: last7DaysData,
                        metric: .items,
                        title: "Logged Workout Items"
                    )

                    // Duration trend
                    WorkoutTrendChart(
                        data: last7DaysData,
                        metric: .duration,
                        title: "Workout Duration"
                    )

                    if weekStats.volume > 0 {
                        WorkoutTrendChart(
                            data: last7DaysData,
                            metric: .volume,
                            title: "Strength Volume"
                        )
                    }

                    if !sessionTypeDistribution.isEmpty {
                        sessionTypeCard
                    }

                    // Recent workouts
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("Workout Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }

                if let onStartWorkout {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start Workout") {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                onStartWorkout()
                            }
                        }
                    }
                }
            }
        }
        .traiBackground()
    }

    // MARK: - Week Summary Card

    private var weekSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 0) {
                StatItem(
                    value: "\(weekStats.workouts)",
                    label: "Workouts",
                    icon: "figure.mixed.cardio",
                    color: .orange
                )

                Divider().frame(height: 40)

                StatItem(
                    value: "\(weekStats.items)",
                    label: "Items",
                    icon: "list.bullet.rectangle",
                    color: .blue
                )

                Divider().frame(height: 40)

                StatItem(
                    value: "\(weekStats.minutes)",
                    label: "Minutes",
                    icon: "clock.fill",
                    color: .green
                )

                if weekStats.volume > 0 {
                    Divider().frame(height: 40)

                    StatItem(
                        value: formatVolume(weekStats.volume),
                        label: "Strength Vol",
                        icon: "scalemass.fill",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Session Type Card

    private var sessionTypeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Types")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(sessionTypeDistribution.prefix(6), id: \.group) { item in
                    HStack {
                        Text(item.group)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.capsule)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workouts")
                .font(.headline)

            if completedWorkouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.mixed.cardio")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No workouts yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Start your first workout to track progress")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(completedWorkouts.prefix(5)) { workout in
                    RecentWorkoutRow(workout: workout)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recent Workout Row

private struct RecentWorkoutRow: View {
    let workout: LiveWorkout

    private var entryCount: Int {
        workout.entries?.count ?? 0
    }

    private var activitySummary: String? {
        if workout.totalSets > 0 {
            return "\(workout.totalSets) \(workout.totalSets == 1 ? "set" : "sets")"
        }

        guard entryCount > 0 else { return nil }
        return "\(entryCount) \(entryCount == 1 ? "item" : "items")"
    }

    private var secondaryChips: [String] {
        if !workout.focusAreas.isEmpty {
            return Array(workout.focusAreas.prefix(2))
        }

        if !workout.muscleGroups.isEmpty {
            return workout.muscleGroups.prefix(2).map(\.displayName)
        }

        return [workout.type.displayName]
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name.isEmpty ? "Workout" : workout.name)
                    .font(.subheadline)
                    .bold()

                HStack(spacing: 12) {
                    if let date = workout.completedAt {
                        Label(date.formatted(.dateTime.weekday().month().day()), systemImage: "calendar")
                    }

                    Label(workout.formattedDuration, systemImage: "clock")

                    if let activitySummary {
                        Label(activitySummary, systemImage: workout.totalSets > 0 ? "repeat" : "list.bullet.rectangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !secondaryChips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(secondaryChips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(.accent)
                            .clipShape(.capsule)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    WorkoutTrendDetailSheet(workouts: [])
}
