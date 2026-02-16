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
        VStack(alignment: .leading, spacing: TraiSpacing.sm) {
            Text("\(greeting), \(name)!")
                .font(.traiBold(24))

            HStack {
                Image(systemName: goal.iconName)
                Text("Goal: \(goal.displayName)")
            }
            .font(.traiLabel())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .traiCard()
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

    private var progressColor: Color {
        progress < 0.8 ? .green : progress < 1.0 ? .teal : .blue
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: TraiSpacing.md) {
                HStack {
                    Text("Calories")
                        .font(.traiHeadline())
                    Spacer()
                    HStack(spacing: TraiSpacing.xs) {
                        Text("\(consumed) / \(goal)")
                            .font(.traiLabel())
                            .foregroundStyle(.secondary)
                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Gradient progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(progressColor.opacity(0.15))

                        Capsule()
                            .fill(TraiGradient.progress(progressColor))
                            .frame(width: max(geometry.size.width * progress, 4))
                            .shadow(color: progressColor.opacity(0.3), radius: 4, y: 1)
                    }
                }
                .frame(height: 8)

                HStack {
                    VStack(alignment: .leading) {
                        TraiAnimatedNumber(value: consumed, font: .traiBold(28))
                        Text("consumed")
                            .font(.traiLabel(11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        TraiAnimatedNumber(value: remaining, font: .traiBold(28), color: progressColor)
                        Text("remaining")
                            .font(.traiLabel(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .traiCard(glow: .nutrition)
        }
        .buttonStyle(TraiPressStyle())
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
            VStack(spacing: TraiSpacing.md) {
                HStack {
                    Text("Macros")
                        .font(.traiHeadline())
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
                    HStack(spacing: TraiSpacing.md) {
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
            .traiCard(glow: .macros)
        }
        .buttonStyle(TraiPressStyle())
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
        VStack(spacing: TraiSpacing.md) {
            HStack {
                Text("Today's Activity")
                    .font(.traiHeadline())
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if isLoading && steps == 0 && activeCalories == 0 {
                HStack(spacing: TraiSpacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        ActivityMetricPlaceholder()
                    }
                }
            } else {
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
        .traiCard(glow: .activity)
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
        VStack(spacing: TraiSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.3), radius: 3, y: 1)

            Text(value)
                .font(.traiBold(17))
                .monospacedDigit()
                .contentTransition(.numericText())

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
            VStack(alignment: .leading, spacing: TraiSpacing.xs) {
                Text("Current Weight")
                    .font(.traiHeadline())

                HStack(alignment: .firstTextBaseline, spacing: TraiSpacing.xs) {
                    Text(displayWeight, format: .number.precision(.fractionLength(1)))
                        .font(.traiBold(28))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: displayWeight))
                        .animation(TraiAnimation.standard, value: displayWeight)

                    Text(weightUnit)
                        .font(.traiLabel())
                        .foregroundStyle(.secondary)
                }

                if let target = displayTarget {
                    Text("Target: \(target, format: .number.precision(.fractionLength(1))) \(weightUnit)")
                        .font(.traiLabel(11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: TraiSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "scalemass.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .traiCard(glow: .body)
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    let onLogFood: () -> Void
    let onAddWorkout: () -> Void
    let onLogWeight: () -> Void
    var workoutName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TraiSpacing.sm + TraiSpacing.xs) {
            Text("Quick Actions")
                .font(.traiHeadline())

            HStack(spacing: TraiSpacing.sm + TraiSpacing.xs) {
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
        .traiCard(glow: .quickActions)
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
            VStack(spacing: TraiSpacing.sm + TraiSpacing.xs) {
                HStack {
                    Text("Workout Trends")
                        .font(.traiHeadline())
                    Spacer()
                    HStack(spacing: TraiSpacing.xs) {
                        Text("7 days")
                            .font(.traiLabel(11))
                            .foregroundStyle(.secondary)
                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Mini bar chart with gradient fills
                HStack(spacing: TraiSpacing.xs) {
                    ForEach(last7DaysData) { day in
                        VStack(spacing: TraiSpacing.xs) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    day.workoutCount > 0
                                        ? AnyShapeStyle(TraiGradient.action(.orange))
                                        : AnyShapeStyle(Color.secondary.opacity(0.15))
                                )
                                .frame(height: day.workoutCount > 0 ? 24 : 8)
                                .shadow(
                                    color: day.workoutCount > 0 ? Color.orange.opacity(0.25) : .clear,
                                    radius: 3, y: 1
                                )

                            Text(day.date, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 40)

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
            .traiCard(glow: .trends)
        }
        .buttonStyle(TraiPressStyle())
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
                .font(.traiBold(17))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

