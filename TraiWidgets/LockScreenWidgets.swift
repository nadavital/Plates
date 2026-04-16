//
//  LockScreenWidgets.swift
//  TraiWidgets
//
//  Lock Screen widgets for at-a-glance fitness tracking
//

import SwiftUI
import WidgetKit

// MARK: - Colors (can't use extension from other file in Lock Screen context)

private let calorieColor = Color.red

// MARK: - Circular Widget (Calorie Gauge)

struct CalorieCircularWidget: Widget {
    let kind = "TraiCalorieCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TraiDataProvider()) { entry in
            CalorieCircularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calorie Ring")
        .description("Your daily calorie progress at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CalorieCircularView: View {
    let entry: TraiWidgetEntry

    var body: some View {
        Gauge(value: entry.data.calorieProgress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(Int(entry.data.calorieProgress * 100))")
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.red)
    }
}

// MARK: - Rectangular Widget (Stats Summary)

struct StatsRectangularWidget: Widget {
    let kind = "TraiStatsRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TraiDataProvider()) { entry in
            StatsRectangularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fitness Stats")
        .description("Calories, protein, and workout status.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct StatsRectangularView: View {
    let entry: TraiWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Calorie line
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                Text("\(entry.data.caloriesConsumed)/\(entry.data.calorieGoal) cal")
                    .font(.caption)
            }

            // Protein line
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                Text("\(entry.data.proteinConsumed)/\(entry.data.proteinGoal)g protein")
                    .font(.caption)
            }

            // Workout status
            HStack(spacing: 4) {
                if entry.data.todayWorkoutCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Workout done")
                        .font(.caption2)
                } else if let workout = entry.data.recommendedWorkout {
                    Image(systemName: "figure.run")
                        .font(.caption2)
                    Text(workout)
                        .font(.caption2)
                        .lineLimit(1)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2)
                    Text("\(entry.data.readyMuscleCount) muscles ready")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Inline Widget (Compact Stats)

struct StatsInlineWidget: Widget {
    let kind = "TraiStatsInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TraiDataProvider()) { entry in
            StatsInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Stats")
        .description("Compact calorie and protein progress.")
        .supportedFamilies([.accessoryInline])
    }
}

struct StatsInlineView: View {
    let entry: TraiWidgetEntry

    var body: some View {
        let calPct = Int(entry.data.calorieProgress * 100)
        let proPct = Int(entry.data.proteinProgress * 100)

        Text("\(calPct)% cal | \(proPct)% protein | \(entry.data.readyMuscleCount) ready")
    }
}


// MARK: - Previews

#if DEBUG
private enum LockScreenWidgetPreviewData {
    static let circularEntry = TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1450,
        calorieGoal: 2000,
        proteinConsumed: 95,
        proteinGoal: 150,
        carbsConsumed: 180,
        carbsGoal: 200,
        fatConsumed: 45,
        fatGoal: 65,
        readyMuscleCount: 5,
        recommendedWorkout: "Push Day",
        workoutStreak: 3,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    ))

    static let rectangularEntry = TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1450,
        calorieGoal: 2000,
        proteinConsumed: 120,
        proteinGoal: 150,
        carbsConsumed: 180,
        carbsGoal: 200,
        fatConsumed: 50,
        fatGoal: 65,
        readyMuscleCount: 5,
        recommendedWorkout: "Push Day",
        workoutStreak: 3,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    ))

    static let inlineEntry = TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1600,
        calorieGoal: 2000,
        proteinConsumed: 130,
        proteinGoal: 150,
        carbsConsumed: 190,
        carbsGoal: 200,
        fatConsumed: 60,
        fatGoal: 65,
        readyMuscleCount: 7,
        recommendedWorkout: nil,
        workoutStreak: 5,
        todayWorkoutCompleted: true,
        lastUpdated: Date()
    ))
}

struct LockScreenWidgets_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalorieCircularView(entry: LockScreenWidgetPreviewData.circularEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular")

            StatsRectangularView(entry: LockScreenWidgetPreviewData.rectangularEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular")

            StatsInlineView(entry: LockScreenWidgetPreviewData.inlineEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("Inline")
        }
    }
}
#endif
