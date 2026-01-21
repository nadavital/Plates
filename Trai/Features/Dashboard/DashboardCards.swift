//
//  DashboardCards.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI

// MARK: - Greeting Card

struct GreetingCard: View {
    let name: String
    let goal: UserProfile.GoalType

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greeting), \(name)!")
                .font(.title2)
                .bold()

            HStack {
                Image(systemName: goal.iconName)
                Text("Goal: \(goal.displayName)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Calorie Progress Card

struct CalorieProgressCard: View {
    let consumed: Int
    let goal: Int
    var onTap: (() -> Void)?

    private var progress: Double {
        min(Double(consumed) / Double(goal), 1.0)
    }

    private var remaining: Int {
        max(goal - consumed, 0)
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: 16) {
                HStack {
                    Text("Calories")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(consumed) / \(goal)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                ProgressView(value: progress)
                    .tint(progress < 0.8 ? .green : progress < 1.0 ? .teal : .blue)

                HStack {
                    VStack(alignment: .leading) {
                        Text("\(consumed)")
                            .font(.title)
                            .bold()
                        Text("consumed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(remaining)")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.green)
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Breakdown Card

struct MacroBreakdownCard: View {
    let macroValues: [MacroType: Double]
    let macroGoals: [MacroType: Int]
    let enabledMacros: Set<MacroType>
    var onTap: (() -> Void)?

    /// Convenience initializer for legacy usage
    init(
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        proteinGoal: Int,
        carbsGoal: Int,
        fatGoal: Int,
        fiberGoal: Int = 30,
        sugarGoal: Int = 50,
        enabledMacros: Set<MacroType> = MacroType.defaultEnabled,
        onTap: (() -> Void)? = nil
    ) {
        self.macroValues = [
            .protein: protein,
            .carbs: carbs,
            .fat: fat,
            .fiber: fiber,
            .sugar: sugar
        ]
        self.macroGoals = [
            .protein: proteinGoal,
            .carbs: carbsGoal,
            .fat: fatGoal,
            .fiber: fiberGoal,
            .sugar: sugarGoal
        ]
        self.enabledMacros = enabledMacros
        self.onTap = onTap
    }

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: 16) {
                HStack {
                    Text("Macros")
                        .font(.headline)
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if orderedEnabledMacros.isEmpty {
                    emptyStateView
                } else {
                    HStack(spacing: 16) {
                        ForEach(orderedEnabledMacros) { macro in
                            MacroRingItem(
                                name: macro.displayName,
                                current: macroValues[macro] ?? 0,
                                goal: Double(macroGoals[macro] ?? 100),
                                color: macro.color
                            )
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("Tracking calories only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Today's Activity Card

struct TodaysActivityCard: View {
    let steps: Int
    let activeCalories: Int
    let exerciseMinutes: Int
    let workoutCount: Int
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Today's Activity")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if isLoading && steps == 0 && activeCalories == 0 {
                // Loading state
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        ActivityMetricPlaceholder()
                    }
                }
            } else {
                // Activity metrics grid
                HStack(spacing: 0) {
                    ActivityMetricItem(
                        icon: "figure.walk",
                        value: formatSteps(steps),
                        label: "Steps",
                        color: .green
                    )

                    Divider()
                        .frame(height: 40)

                    ActivityMetricItem(
                        icon: "flame.fill",
                        value: "\(activeCalories)",
                        label: "Active Cal",
                        color: .orange
                    )

                    Divider()
                        .frame(height: 40)

                    ActivityMetricItem(
                        icon: "figure.run",
                        value: "\(exerciseMinutes)",
                        label: "Exercise",
                        color: .cyan
                    )

                    Divider()
                        .frame(height: 40)

                    ActivityMetricItem(
                        icon: "dumbbell.fill",
                        value: "\(workoutCount)",
                        label: "Workouts",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 1000 {
            let thousands = Double(steps) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        return "\(steps)"
    }
}

// MARK: - Activity Metric Item

private struct ActivityMetricItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
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

// MARK: - Activity Metric Placeholder

private struct ActivityMetricPlaceholder: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 24, height: 24)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 32, height: 16)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Weight Trend Card

struct WeightTrendCard: View {
    let currentWeight: Double
    let targetWeight: Double?
    var useLbs: Bool = false

    private var displayWeight: Double {
        useLbs ? currentWeight * 2.20462 : currentWeight
    }

    private var displayTarget: Double? {
        guard let target = targetWeight else { return nil }
        return useLbs ? target * 2.20462 : target
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Weight")
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayWeight, format: .number.precision(.fractionLength(1)))
                        .font(.title)
                        .bold()

                    Text(weightUnit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let target = displayTarget {
                    Text("Target: \(target, format: .number.precision(.fractionLength(1))) \(weightUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .font(.title)
                    .foregroundStyle(.tint)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    let onLogFood: () -> Void
    let onAddWorkout: () -> Void
    let onLogWeight: () -> Void
    var workoutName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Log Food",
                    icon: "plus.circle.fill",
                    color: .green,
                    action: onLogFood
                )
                QuickActionButton(
                    title: "Start Workout",
                    subtitle: workoutName,
                    icon: "figure.run",
                    color: .orange,
                    action: onAddWorkout
                )
                QuickActionButton(
                    title: "Log Weight",
                    icon: "scalemass.fill",
                    color: .blue,
                    action: onLogWeight
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Trend Card

/// A compact card showing weekly workout summary with tap to expand
struct WorkoutTrendCard: View {
    let workouts: [LiveWorkout]
    var onTap: (() -> Void)?

    private var completedWorkouts: [LiveWorkout] {
        workouts.filter { $0.completedAt != nil }
    }

    private var last7DaysData: [TrendsService.DailyWorkout] {
        TrendsService.aggregateWorkoutsByDay(workouts: completedWorkouts, days: 7)
    }

    private var weeklyWorkoutCount: Int {
        last7DaysData.reduce(0) { $0 + $1.workoutCount }
    }

    private var weeklyVolume: Double {
        last7DaysData.reduce(0.0) { $0 + $1.totalVolume }
    }

    private var weeklyMinutes: Int {
        last7DaysData.reduce(0) { $0 + $1.totalDurationMinutes }
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Workout Trends")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("7 days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Mini bar chart showing workout days
                HStack(spacing: 4) {
                    ForEach(last7DaysData) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.workoutCount > 0 ? Color.orange : Color.secondary.opacity(0.2))
                                .frame(height: day.workoutCount > 0 ? 24 : 8)

                            Text(day.date, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 40)

                // Stats row
                HStack(spacing: 0) {
                    TrendStatItem(
                        value: "\(weeklyWorkoutCount)",
                        label: "Workouts",
                        color: .orange
                    )

                    Divider().frame(height: 30)

                    TrendStatItem(
                        value: formatVolume(weeklyVolume),
                        label: "Volume",
                        color: .purple
                    )

                    Divider().frame(height: 30)

                    TrendStatItem(
                        value: "\(weeklyMinutes)",
                        label: "Minutes",
                        color: .green
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

private struct TrendStatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

