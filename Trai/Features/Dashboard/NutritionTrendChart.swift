//
//  NutritionTrendChart.swift
//  Trai
//
//  Reusable chart component for nutrition trends.
//

import SwiftUI
import Charts

/// A line chart showing calorie or macro trends over time.
struct NutritionTrendChart: View {
    let data: [TrendsService.DailyNutrition]
    let goal: Int?
    let valueKeyPath: KeyPath<TrendsService.DailyNutrition, Double>
    let title: String
    let color: Color
    let unit: String

    init(
        data: [TrendsService.DailyNutrition],
        goal: Int?,
        metric: NutritionMetric,
        title: String? = nil
    ) {
        self.data = data
        self.goal = goal
        self.title = title ?? metric.title
        self.color = metric.color
        self.unit = metric.unit
        self.valueKeyPath = metric.keyPath
    }

    enum NutritionMetric {
        case calories
        case protein
        case carbs
        case fat
        case fiber
        case sugar

        var keyPath: KeyPath<TrendsService.DailyNutrition, Double> {
            switch self {
            case .calories: \.caloriesDouble
            case .protein: \.protein
            case .carbs: \.carbs
            case .fat: \.fat
            case .fiber: \.fiber
            case .sugar: \.sugar
            }
        }

        var title: String {
            switch self {
            case .calories: "Calories"
            case .protein: "Protein"
            case .carbs: "Carbs"
            case .fat: "Fat"
            case .fiber: "Fiber"
            case .sugar: "Sugar"
            }
        }

        var color: Color {
            switch self {
            case .calories: .orange
            case .protein: MacroType.protein.color
            case .carbs: MacroType.carbs.color
            case .fat: MacroType.fat.color
            case .fiber: MacroType.fiber.color
            case .sugar: MacroType.sugar.color
            }
        }

        var unit: String {
            switch self {
            case .calories: "kcal"
            default: "g"
            }
        }
    }

    private var daysWithData: [TrendsService.DailyNutrition] {
        data.filter { $0.entryCount > 0 }
    }

    private var average: Double {
        guard !daysWithData.isEmpty else { return 0 }
        let sum = daysWithData.reduce(0.0) { $0 + $1[keyPath: valueKeyPath] }
        return sum / Double(daysWithData.count)
    }

    private var trend: (direction: TrendsService.TrendDirection, percentChange: Double) {
        guard daysWithData.count >= 4 else { return (.stable, 0) }
        let midpoint = daysWithData.count / 2
        let firstHalf = Array(daysWithData.prefix(midpoint))
        let secondHalf = Array(daysWithData.suffix(midpoint))

        let firstAvg = firstHalf.reduce(0.0) { $0 + $1[keyPath: valueKeyPath] } / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0.0) { $0 + $1[keyPath: valueKeyPath] } / Double(secondHalf.count)

        return TrendsService.calculateTrend(recentAverage: secondAvg, previousAverage: firstAvg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and trend indicator
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                if daysWithData.count >= 4 {
                    TrendBadge(direction: trend.direction, change: trend.percentChange)
                }
            }

            // Chart
            if daysWithData.count > 1 {
                Chart {
                    ForEach(data) { day in
                        if day.entryCount > 0 {
                            LineMark(
                                x: .value("Date", day.date),
                                y: .value(title, day[keyPath: valueKeyPath])
                            )
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", day.date),
                                y: .value(title, day[keyPath: valueKeyPath])
                            )
                            .foregroundStyle(color)
                            .symbolSize(30)
                        }
                    }

                    if let goal {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Goal")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 4)
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
                                Text(date, format: .dateTime.day())
                                    .font(.caption2)
                            }
                        }
                    }
                }
            } else {
                // Not enough data
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("Log more days to see trends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            }

            // Average stat
            HStack {
                Text("Average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(average)) \(unit)")
                    .font(.caption)
                    .bold()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Trend Badge

struct TrendBadge: View {
    let direction: TrendsService.TrendDirection
    let change: Double

    private var color: Color {
        switch direction {
        case .up: .orange
        case .down: .blue
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

// MARK: - Helper Extension

extension TrendsService.DailyNutrition {
    var caloriesDouble: Double {
        Double(calories)
    }
}

#Preview {
    let sampleData: [TrendsService.DailyNutrition] = (0..<7).map { offset in
        TrendsService.DailyNutrition(
            date: Calendar.current.date(byAdding: .day, value: -6 + offset, to: Date())!,
            calories: Int.random(in: 1800...2200),
            protein: Double.random(in: 120...160),
            carbs: Double.random(in: 180...220),
            fat: Double.random(in: 50...70),
            fiber: Double.random(in: 20...35),
            sugar: Double.random(in: 30...50),
            entryCount: offset == 0 ? 0 : Int.random(in: 3...6)
        )
    }

    return VStack {
        NutritionTrendChart(data: sampleData, goal: 2000, metric: .calories)
        NutritionTrendChart(data: sampleData, goal: 150, metric: .protein)
    }
    .padding()
}
