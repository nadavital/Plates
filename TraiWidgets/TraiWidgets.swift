//
//  TraiWidgets.swift
//  TraiWidgets
//
//  Data-driven home screen widgets showing fitness progress
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - App Colors (matching main app MacroType colors)

extension Color {
    static let calorieColor = Color.red
    static let proteinColor = Color.blue
    static let carbsColor = Color.orange
    static let fatColor = Color.purple
}

private extension WidgetData.Macro {
    var color: Color {
        switch self {
        case .calories: .calorieColor
        case .protein: .proteinColor
        case .carbs: .carbsColor
        case .fat: .fatColor
        }
    }
}

// MARK: - Widget Data Reader

enum WidgetDataReader {
    static func loadData() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName),
              let jsonData = defaults.data(forKey: SharedStorageKeys.AppGroup.widgetData),
              let data = try? JSONDecoder().decode(WidgetData.self, from: jsonData) else {
            return .empty
        }
        return data
    }
}

// MARK: - Timeline Provider

struct TraiDataProvider: TimelineProvider {
    func placeholder(in context: Context) -> TraiWidgetEntry {
        TraiWidgetEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TraiWidgetEntry) -> Void) {
        let data = WidgetDataReader.loadData()
        completion(TraiWidgetEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TraiWidgetEntry>) -> Void) {
        let data = WidgetDataReader.loadData()
        var entry = TraiWidgetEntry(date: Date(), data: data)
        entry.relevance = calculateRelevance(data: data)

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func calculateRelevance(data: WidgetData) -> TimelineEntryRelevance? {
        let hour = Calendar.current.component(.hour, from: Date())
        var score: Float = 0.5

        if (7...9).contains(hour) || (12...14).contains(hour) || (18...20).contains(hour) {
            score += 0.3
        }

        if data.progress(for: .calories) > 0.7 && data.progress(for: .calories) < 1.0 {
            score += 0.2
        }

        if data.recommendedWorkout != nil && !data.todayWorkoutCompleted {
            score += 0.1
        }

        return TimelineEntryRelevance(score: score)
    }
}

// MARK: - Timeline Entry

struct TraiWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    var relevance: TimelineEntryRelevance?
}

// MARK: - Small Widget View
// Compact percentage rings + icon action buttons

struct SmallWidgetView: View {
    let entry: TraiWidgetEntry

    var body: some View {
        VStack(spacing: 10) {
            // Macro percentages in a row
            HStack(spacing: 12) {
                SmallMacroRing(macro: .calories, data: entry.data)
                SmallMacroRing(macro: .protein, data: entry.data)
            }

            Spacer()

            // Larger icon-only action buttons
            HStack(spacing: 12) {
                SmallWidgetActionButton(icon: "fork.knife", url: "trai://logfood", color: .green)
                SmallWidgetActionButton(icon: "figure.run", url: "trai://workout", color: .orange)
                SmallWidgetActionButton(icon: "circle.hexagongrid.circle", url: "trai://chat", color: .calorieColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget View
// 2x2 macro grid + workout row, buttons on side

struct MediumWidgetView: View {
    let entry: TraiWidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: Macros + Workout
            VStack(spacing: 6) {
                // 2x2 Macro grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    MediumMacroCell(macro: .calories, data: entry.data)
                    MediumMacroCell(macro: .protein, data: entry.data)
                    MediumMacroCell(macro: .carbs, data: entry.data)
                    MediumMacroCell(macro: .fat, data: entry.data)
                }

                // Workout status row
                HStack(spacing: 6) {
                    if entry.data.todayWorkoutCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Workout Complete")
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    } else if let workout = entry.data.recommendedWorkout {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.orange)
                        Text("Up Next: \(workout)")
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.secondary)
                        Text("Rest Day")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if entry.data.workoutStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                            Text("\(entry.data.workoutStreak)")
                        }
                        .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            // Right: Action buttons column
            VStack(spacing: 6) {
                MediumActionButton(icon: "fork.knife", url: "trai://logfood", color: .green)
                MediumActionButton(icon: "figure.run", url: "trai://workout", color: .orange)
                MediumActionButton(icon: "circle.hexagongrid.circle", url: "trai://chat", color: .calorieColor)
            }
            .frame(width: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large Widget View
// Dashboard with macro cards, workout section, action buttons

struct LargeWidgetView: View {
    let entry: TraiWidgetEntry

    private var workoutURL: URL {
        if let workout = entry.data.recommendedWorkout,
           let encoded = workout.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "trai://workout?template=\(encoded)")!
        }
        return URL(string: "trai://workout")!
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with streak
            HStack {
                Text("Today's Progress")
                    .font(.headline)

                Spacer()

                if entry.data.workoutStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(entry.data.workoutStreak) day streak")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            // Macros grid - 2x2 with subtle backgrounds
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                LargeMacroCard(macro: .calories, data: entry.data)
                LargeMacroCard(macro: .protein, data: entry.data)
                LargeMacroCard(macro: .carbs, data: entry.data)
                LargeMacroCard(macro: .fat, data: entry.data)
            }

            // Workout section (no background, cleaner)
            Link(destination: workoutURL) {
                HStack {
                    if entry.data.todayWorkoutCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout Complete")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Great job today!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let workout = entry.data.recommendedWorkout {
                        Image(systemName: "figure.run")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Up Next: \(workout)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Tap to start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "moon.zzz.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Day")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("Tap to start a workout")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Action buttons (clean, no heavy backgrounds)
            HStack(spacing: 10) {
                ActionButton(label: "Log Food", icon: "fork.knife", url: "trai://logfood", color: .green)
                ActionButton(label: "Log Weight", icon: "scalemass.fill", url: "trai://logweight", color: .blue)
                ActionButton(label: "Trai", icon: "circle.hexagongrid.circle", url: "trai://chat", color: .calorieColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

struct SmallMacroRing: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(data.progress(for: macro) * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .frame(width: 50, height: 50)

            Text(macro.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LargeSmallActionButton: View {
    let icon: String
    let label: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label)
                    .font(.system(.caption2, weight: .medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}

struct MediumMacroCell: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        HStack(spacing: 6) {
            // Ring with percentage inside
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(data.progress(for: macro) * 100))")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text(macro.label)
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
                Text("\(data.consumed(for: macro))\(macro.unit)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(macro.color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct CompactMacroRow: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        HStack(spacing: 6) {
            // Mini ring
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)

            Text(macro.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Text("\(data.consumed(for: macro))\(macro.unit)")
                .font(.system(.caption, design: .rounded, weight: .semibold))

            Text("/ \(data.goal(for: macro))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct MacroRow: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        HStack(spacing: 8) {
            // Ring
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(macro.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text("\(data.consumed(for: macro))\(macro.unit)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    Text("/ \(data.goal(for: macro))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LargeMacroCard: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        HStack(spacing: 10) {
            // Ring
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(data.progress(for: macro) * 100))%")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(macro.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(data.consumed(for: macro))\(macro.unit)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("\(data.remaining(for: macro))\(macro.unit) left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(macro.color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct LargeMacroRow: View {
    let macro: WidgetData.Macro
    let data: WidgetData

    var body: some View {
        HStack(spacing: 10) {
            // Ring
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: data.progress(for: macro))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(data.progress(for: macro) * 100))")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(macro.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(data.consumed(for: macro))\(macro.unit)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    Text("/ \(data.goal(for: macro))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

struct CleanActionButton: View {
    let label: String
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

struct SmallActionButton: View {
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(.circle)
        }
    }
}

struct SmallWidgetActionButton: View {
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(.circle)
        }
    }
}

struct MediumWidgetActionButton: View {
    let icon: String
    let label: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

struct MediumActionButton: View {
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .clipShape(.circle)
        }
    }
}

struct IconButton: View {
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(.circle)
        }
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}

// MARK: - Main Widget View

struct TraiWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: TraiWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct TraiWidgets: Widget {
    let kind: String = "TraiWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TraiDataProvider()) { entry in
            TraiWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Trai")
        .description("Track calories, protein, carbs, fat, and workouts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TraiWidgets()
} timeline: {
    TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1450,
        calorieGoal: 2000,
        proteinConsumed: 95,
        proteinGoal: 150,
        carbsConsumed: 180,
        carbsGoal: 250,
        fatConsumed: 45,
        fatGoal: 65,
        readyMuscleCount: 5,
        recommendedWorkout: "Push Day",
        workoutStreak: 3,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    ))
}

#Preview("Medium", as: .systemMedium) {
    TraiWidgets()
} timeline: {
    TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1450,
        calorieGoal: 2000,
        proteinConsumed: 120,
        proteinGoal: 150,
        carbsConsumed: 180,
        carbsGoal: 250,
        fatConsumed: 45,
        fatGoal: 65,
        readyMuscleCount: 5,
        recommendedWorkout: "Push Day",
        workoutStreak: 3,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    ))
}

#Preview("Large", as: .systemLarge) {
    TraiWidgets()
} timeline: {
    TraiWidgetEntry(date: .now, data: WidgetData(
        caloriesConsumed: 1650,
        calorieGoal: 2000,
        proteinConsumed: 130,
        proteinGoal: 150,
        carbsConsumed: 200,
        carbsGoal: 250,
        fatConsumed: 55,
        fatGoal: 65,
        readyMuscleCount: 7,
        recommendedWorkout: "Leg Day",
        workoutStreak: 5,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    ))
}
