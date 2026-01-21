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
        let totalVolume = data.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = data.reduce(0) { $0 + $1.totalSets }
        let totalMinutes = data.reduce(0) { $0 + $1.totalDurationMinutes }

        return WeekStats(
            workouts: totalWorkouts,
            volume: totalVolume,
            sets: totalSets,
            minutes: totalMinutes
        )
    }

    private struct WeekStats {
        let workouts: Int
        let volume: Double
        let sets: Int
        let minutes: Int
    }

    private var muscleGroupDistribution: [(group: String, count: Int)] {
        var distribution: [String: Int] = [:]

        for workout in completedWorkouts.prefix(20) {
            for muscle in workout.muscleGroups {
                distribution[muscle.displayName, default: 0] += 1
            }
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

                    // Volume trend
                    if weekStats.volume > 0 {
                        WorkoutTrendChart(
                            data: last7DaysData,
                            metric: .volume,
                            title: "Total Volume"
                        )
                    }

                    // Duration trend
                    WorkoutTrendChart(
                        data: last7DaysData,
                        metric: .duration,
                        title: "Workout Duration"
                    )

                    // Muscle group distribution
                    if !muscleGroupDistribution.isEmpty {
                        muscleDistributionCard
                    }

                    // Recent workouts
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("Workout Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if let onStartWorkout {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start Workout") {
                            dismiss()
                            onStartWorkout()
                        }
                    }
                }
            }
        }
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
                    icon: "figure.run",
                    color: .orange
                )

                Divider().frame(height: 40)

                StatItem(
                    value: formatVolume(weekStats.volume),
                    label: "Volume",
                    icon: "scalemass.fill",
                    color: .purple
                )

                Divider().frame(height: 40)

                StatItem(
                    value: "\(weekStats.sets)",
                    label: "Sets",
                    icon: "repeat",
                    color: .blue
                )

                Divider().frame(height: 40)

                StatItem(
                    value: "\(weekStats.minutes)",
                    label: "Minutes",
                    icon: "clock.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Muscle Distribution Card

    private var muscleDistributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscle Groups")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(muscleGroupDistribution.prefix(6), id: \.group) { item in
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
                    Image(systemName: "figure.run")
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

                    if workout.totalSets > 0 {
                        Label("\(workout.totalSets) sets", systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Muscle group chips
            if !workout.muscleGroups.isEmpty {
                HStack(spacing: 4) {
                    ForEach(workout.muscleGroups.prefix(2)) { muscle in
                        Text(muscle.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
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
