//
//  WorkoutTrendChart.swift
//  Trai
//
//  Reusable chart component for workout trends.
//

import SwiftUI
import Charts

/// A bar/line chart showing workout trends over time.
struct WorkoutTrendChart: View {
    let data: [TrendsService.DailyWorkout]
    let metric: WorkoutMetric
    let title: String?

    init(
        data: [TrendsService.DailyWorkout],
        metric: WorkoutMetric,
        title: String? = nil
    ) {
        self.data = data
        self.metric = metric
        self.title = title
    }

    enum WorkoutMetric {
        case frequency
        case volume
        case sets
        case duration

        var keyPath: KeyPath<TrendsService.DailyWorkout, Double> {
            switch self {
            case .frequency: \.workoutCountDouble
            case .volume: \.totalVolume
            case .sets: \.totalSetsDouble
            case .duration: \.totalDurationDouble
            }
        }

        var displayTitle: String {
            switch self {
            case .frequency: "Workouts"
            case .volume: "Volume"
            case .sets: "Sets"
            case .duration: "Duration"
            }
        }

        var unit: String {
            switch self {
            case .frequency: "workouts"
            case .volume: "kg"
            case .sets: "sets"
            case .duration: "min"
            }
        }

        var color: Color {
            switch self {
            case .frequency: .orange
            case .volume: .purple
            case .sets: .blue
            case .duration: .green
            }
        }
    }

    private var daysWithData: [TrendsService.DailyWorkout] {
        data.filter { $0.workoutCount > 0 }
    }

    private var totalValue: Double {
        data.reduce(0.0) { $0 + $1[keyPath: metric.keyPath] }
    }

    private var average: Double {
        guard !daysWithData.isEmpty else { return 0 }
        let sum = daysWithData.reduce(0.0) { $0 + $1[keyPath: metric.keyPath] }
        return sum / Double(daysWithData.count)
    }

    private var trend: (direction: TrendsService.TrendDirection, percentChange: Double) {
        guard daysWithData.count >= 4 else { return (.stable, 0) }
        let midpoint = daysWithData.count / 2
        let firstHalf = Array(daysWithData.prefix(midpoint))
        let secondHalf = Array(daysWithData.suffix(midpoint))

        let firstAvg = firstHalf.reduce(0.0) { $0 + $1[keyPath: metric.keyPath] } / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0.0) { $0 + $1[keyPath: metric.keyPath] } / Double(secondHalf.count)

        return TrendsService.calculateTrend(recentAverage: secondAvg, previousAverage: firstAvg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and trend indicator
            HStack {
                Text(title ?? metric.displayTitle)
                    .font(.headline)

                Spacer()

                if daysWithData.count >= 4 {
                    WorkoutTrendBadge(direction: trend.direction, change: trend.percentChange)
                }
            }

            // Chart
            if daysWithData.count > 1 || metric == .frequency {
                chartView
            } else {
                emptyStateView
            }

            // Summary stat
            summaryView
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var chartView: some View {
        Chart {
            ForEach(data) { day in
                if metric == .frequency {
                    // Bar chart for frequency
                    BarMark(
                        x: .value("Date", day.date),
                        y: .value(metric.displayTitle, day[keyPath: metric.keyPath])
                    )
                    .foregroundStyle(day.workoutCount > 0 ? metric.color : Color.secondary.opacity(0.3))
                    .clipShape(.rect(cornerRadius: 4))
                } else if day.workoutCount > 0 {
                    // Line chart for other metrics
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value(metric.displayTitle, day[keyPath: metric.keyPath])
                    )
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", day.date),
                        y: .value(metric.displayTitle, day[keyPath: metric.keyPath])
                    )
                    .foregroundStyle(metric.color)
                    .symbolSize(30)
                }
            }
        }
        .frame(height: 150)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: data.count > 14 ? 7 : 1)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("Complete more workouts to see trends")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var summaryView: some View {
        HStack {
            if metric == .frequency {
                Text("This week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(totalValue)) \(metric.unit)")
                    .font(.caption)
                    .bold()
            } else {
                Text("Avg per workout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(average)) \(metric.unit)")
                    .font(.caption)
                    .bold()
            }
        }
    }
}

// MARK: - Trend Badge

struct WorkoutTrendBadge: View {
    let direction: TrendsService.TrendDirection
    let change: Double

    private var color: Color {
        switch direction {
        case .up: .green  // More workouts = good
        case .down: .orange
        case .stable: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: direction.icon)
                .font(.caption2)
            Text("\(abs(change), format: .number.precision(.fractionLength(0)))%")
                .font(.caption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(.capsule)
    }
}

// MARK: - Helper Extensions

extension TrendsService.DailyWorkout {
    var workoutCountDouble: Double {
        Double(workoutCount)
    }

    var totalSetsDouble: Double {
        Double(totalSets)
    }

    var totalDurationDouble: Double {
        Double(totalDurationMinutes)
    }
}

#Preview {
    let sampleData: [TrendsService.DailyWorkout] = (0..<7).map { offset in
        TrendsService.DailyWorkout(
            date: Calendar.current.date(byAdding: .day, value: -6 + offset, to: Date())!,
            workoutCount: offset % 2 == 0 ? 1 : 0,
            totalVolume: Double.random(in: 5000...15000),
            totalSets: Int.random(in: 15...30),
            totalDurationMinutes: Int.random(in: 45...90)
        )
    }

    return VStack {
        WorkoutTrendChart(data: sampleData, metric: .frequency)
        WorkoutTrendChart(data: sampleData, metric: .volume)
    }
    .padding()
}
