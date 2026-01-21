//
//  TraiWidgets.swift
//  TraiWidgets
//
//  Quick Actions widget for home screen - 4 shortcuts to common actions
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        // Static widget - doesn't need frequent updates
        let entry = QuickActionsEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget View

struct QuickActionsWidgetView: View {
    var entry: QuickActionsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            mediumWidget
        }
    }

    // MARK: - Small Widget (2x2 grid)

    private var smallWidget: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                QuickActionCell(
                    title: "Food",
                    icon: "fork.knife",
                    color: .green,
                    url: "trai://logfood"
                )
                QuickActionCell(
                    title: "Weight",
                    icon: "scalemass.fill",
                    color: .blue,
                    url: "trai://logweight"
                )
            }
            HStack(spacing: 8) {
                QuickActionCell(
                    title: "Workout",
                    icon: "figure.run",
                    color: .orange,
                    url: "trai://workout"
                )
                QuickActionCell(
                    title: "Trai",
                    icon: "bubble.left.fill",
                    color: .purple,
                    url: "trai://chat"
                )
            }
        }
        .padding(12)
    }

    // MARK: - Medium Widget (horizontal row)

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                title: "Log Food",
                icon: "fork.knife",
                color: .green,
                url: "trai://logfood"
            )
            QuickActionButton(
                title: "Log Weight",
                icon: "scalemass.fill",
                color: .blue,
                url: "trai://logweight"
            )
            QuickActionButton(
                title: "Workout",
                icon: "figure.run",
                color: .orange,
                url: "trai://workout"
            )
            QuickActionButton(
                title: "Ask Trai",
                icon: "bubble.left.fill",
                color: .purple,
                url: "trai://chat"
            )
        }
        .padding()
    }
}

// MARK: - Quick Action Cell (for small widget)

private struct QuickActionCell: View {
    let title: String
    let icon: String
    let color: Color
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.15))
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}

// MARK: - Quick Action Button (for medium widget)

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Widget Configuration

struct TraiWidgets: Widget {
    let kind: String = "TraiQuickActions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Actions")
        .description("Quick access to log food, weight, start a workout, or chat with Trai.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TraiWidgets()
} timeline: {
    QuickActionsEntry(date: .now)
}

#Preview("Medium", as: .systemMedium) {
    TraiWidgets()
} timeline: {
    QuickActionsEntry(date: .now)
}
