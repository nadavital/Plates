//
//  TrendsService.swift
//  Trai
//
//  Created for trends visualization feature.
//

import Foundation
import SwiftData

/// Service for aggregating and analyzing trend data from food logs, workouts, and weight entries.
@MainActor
final class TrendsService {

    // MARK: - Types

    struct DailyNutrition: Identifiable {
        let id = UUID()
        let date: Date
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let sugar: Double
        let entryCount: Int

        static var empty: DailyNutrition {
            DailyNutrition(date: Date(), calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0, entryCount: 0)
        }
    }

    struct DailyWorkout: Identifiable {
        let id = UUID()
        let date: Date
        let workoutCount: Int
        let totalEntries: Int
        let totalVolume: Double
        let totalSets: Int
        let totalDurationMinutes: Int
    }

    struct WeeklyAverage {
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let sugar: Double
    }

    // MARK: - Nutrition Aggregation

    /// Aggregates food entries by day for a given date range.
    static func aggregateNutritionByDay(
        entries: [FoodEntry],
        days: Int,
        endDate: Date = Date()
    ) -> [DailyNutrition] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: endDate))!

        // Create a dictionary for each day
        var dailyData: [Date: DailyNutrition] = [:]

        // Initialize all days with zero values
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                let dayStart = calendar.startOfDay(for: date)
                dailyData[dayStart] = DailyNutrition(
                    date: dayStart,
                    calories: 0,
                    protein: 0,
                    carbs: 0,
                    fat: 0,
                    fiber: 0,
                    sugar: 0,
                    entryCount: 0
                )
            }
        }

        // Aggregate entries by day
        for entry in entries {
            let dayStart = calendar.startOfDay(for: entry.loggedAt)
            guard dayStart >= startDate else { continue }

            if let existing = dailyData[dayStart] {
                dailyData[dayStart] = DailyNutrition(
                    date: dayStart,
                    calories: existing.calories + entry.calories,
                    protein: existing.protein + entry.proteinGrams,
                    carbs: existing.carbs + entry.carbsGrams,
                    fat: existing.fat + entry.fatGrams,
                    fiber: existing.fiber + (entry.fiberGrams ?? 0),
                    sugar: existing.sugar + (entry.sugarGrams ?? 0),
                    entryCount: existing.entryCount + 1
                )
            }
        }

        // Return sorted by date
        return dailyData.values.sorted { $0.date < $1.date }
    }

    /// Calculates the average of daily nutrition over a period.
    static func calculateAverage(from dailyData: [DailyNutrition]) -> WeeklyAverage {
        let daysWithEntries = dailyData.filter { $0.entryCount > 0 }
        guard !daysWithEntries.isEmpty else {
            return WeeklyAverage(calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0)
        }

        let count = Double(daysWithEntries.count)
        return WeeklyAverage(
            calories: Int(daysWithEntries.reduce(0) { $0 + Double($1.calories) } / count),
            protein: daysWithEntries.reduce(0) { $0 + $1.protein } / count,
            carbs: daysWithEntries.reduce(0) { $0 + $1.carbs } / count,
            fat: daysWithEntries.reduce(0) { $0 + $1.fat } / count,
            fiber: daysWithEntries.reduce(0) { $0 + $1.fiber } / count,
            sugar: daysWithEntries.reduce(0) { $0 + $1.sugar } / count
        )
    }

    // MARK: - Workout Aggregation

    /// Aggregates workouts by day for a given date range.
    static func aggregateWorkoutsByDay(
        workouts: [LiveWorkout],
        days: Int,
        endDate: Date = Date()
    ) -> [DailyWorkout] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: endDate))!

        var dailyData: [Date: DailyWorkout] = [:]

        // Initialize all days
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                let dayStart = calendar.startOfDay(for: date)
                dailyData[dayStart] = DailyWorkout(
                    date: dayStart,
                    workoutCount: 0,
                    totalEntries: 0,
                    totalVolume: 0,
                    totalSets: 0,
                    totalDurationMinutes: 0
                )
            }
        }

        // Aggregate workouts
        for workout in workouts {
            let dayStart = calendar.startOfDay(for: workout.startedAt)
            guard dayStart >= startDate else { continue }

            let durationMinutes = Int(workout.duration / 60)
            let entryCount = workout.entries?.count ?? 0

            if let existing = dailyData[dayStart] {
                dailyData[dayStart] = DailyWorkout(
                    date: dayStart,
                    workoutCount: existing.workoutCount + 1,
                    totalEntries: existing.totalEntries + entryCount,
                    totalVolume: existing.totalVolume + workout.totalVolume,
                    totalSets: existing.totalSets + workout.totalSets,
                    totalDurationMinutes: existing.totalDurationMinutes + durationMinutes
                )
            }
        }

        return dailyData.values.sorted { $0.date < $1.date }
    }

    // MARK: - Trend Calculations

    /// Calculates the trend direction and percentage change.
    static func calculateTrend(
        recentAverage: Double,
        previousAverage: Double
    ) -> (direction: TrendDirection, percentChange: Double) {
        guard previousAverage > 0 else {
            return (.stable, 0)
        }

        let change = recentAverage - previousAverage
        let percentChange = (change / previousAverage) * 100

        let direction: TrendDirection
        if abs(percentChange) < 2 {
            direction = .stable
        } else if change > 0 {
            direction = .up
        } else {
            direction = .down
        }

        return (direction, percentChange)
    }

    enum TrendDirection {
        case up, down, stable

        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .stable: "arrow.right"
            }
        }
    }

    // MARK: - Helper Methods

    /// Returns the date range label for display.
    static func dateRangeLabel(days: Int) -> String {
        switch days {
        case 7: "Last 7 days"
        case 14: "Last 2 weeks"
        case 30: "Last 30 days"
        case 90: "Last 3 months"
        default: "Last \(days) days"
        }
    }

    /// Formats a date for chart axis labels.
    static func formatDateForAxis(_ date: Date, days: Int) -> String {
        let formatter = DateFormatter()
        if days <= 7 {
            formatter.dateFormat = "EEE"
        } else if days <= 30 {
            formatter.dateFormat = "d"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
