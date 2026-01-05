//
//  CheckInService.swift
//  Plates
//
//  Service for aggregating weekly data and managing check-in flow
//

import Foundation
import SwiftData

@MainActor @Observable
final class CheckInService {

    // MARK: - Daily Data (for chart)

    struct DailyData: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let dayName: String
        let calories: Int
        let calorieGoal: Int
        let protein: Double
        let proteinGoal: Int
        let wasTracked: Bool

        var adherencePercent: Double {
            guard calorieGoal > 0 else { return 0 }
            return Double(calories) / Double(calorieGoal)
        }

        var isWithinTarget: Bool {
            let variance = abs(adherencePercent - 1.0)
            return variance <= 0.1 // Within 10%
        }
    }

    // MARK: - Week Comparison

    struct WeekComparison: Sendable {
        let calorieChange: Int // This week avg - last week avg
        let proteinChange: Double
        let workoutChange: Int
        let daysTrackedChange: Int

        var calorieChangePercent: Int {
            guard calorieChange != 0 else { return 0 }
            return calorieChange > 0 ? Int((Double(calorieChange) / Double(abs(calorieChange))) * 100) : -100
        }
    }

    // MARK: - Detected Wins

    struct DetectedWins: Sendable {
        let items: [String]
        let hasAnyWins: Bool

        static var empty: DetectedWins {
            DetectedWins(items: [], hasAnyWins: false)
        }
    }

    // MARK: - Detected Patterns

    struct DetectedPatterns: Sendable {
        let insights: [String]

        static var empty: DetectedPatterns {
            DetectedPatterns(insights: [])
        }
    }

    // MARK: - Weekly Summary (Enhanced)

    struct WeeklySummary: Sendable {
        let weekStartDate: Date
        let weekEndDate: Date
        let daysTracked: Int
        let totalDays: Int

        // Nutrition
        let totalCalories: Int
        let averageDailyCalories: Int
        let totalProtein: Double
        let averageProtein: Double
        let totalCarbs: Double
        let totalFat: Double
        let calorieGoal: Int
        let proteinGoal: Int
        let calorieAdherence: Double
        let proteinAdherence: Double

        // Daily breakdown for chart
        let dailyData: [DailyData]

        // Workouts
        let workoutsCompleted: Int
        let workoutTypes: [String]
        let totalWorkoutMinutes: Int

        // Weight
        let startingWeight: Double?
        let currentWeight: Double?
        let weightChange: Double?
        let lastWeighInDate: Date?
        let daysSinceWeighIn: Int?

        // Food highlights
        let foodHighlights: [String]
        let mealCount: Int

        // Comparison & insights
        let weekComparison: WeekComparison?
        let detectedWins: DetectedWins
        let detectedPatterns: DetectedPatterns

        /// Whether user has weighed in this week
        var hasRecentWeighIn: Bool {
            guard let days = daysSinceWeighIn else { return false }
            return days <= 7
        }

        /// Formatted weight change string
        var weightChangeFormatted: String? {
            guard let change = weightChange else { return nil }
            let sign = change >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.1f", change)) kg"
        }

        /// Summary line for header
        var summaryLine: String {
            if daysTracked == 0 {
                return "No tracking data this week"
            } else if daysTracked < 3 {
                return "Limited data (\(daysTracked) days tracked)"
            } else {
                return "\(daysTracked) of 7 days tracked"
            }
        }

        /// Description for AI context
        var contextDescription: String {
            var parts: [String] = []

            parts.append("Days tracked: \(daysTracked)/7")
            if daysTracked > 0 {
                parts.append("Avg daily calories: \(averageDailyCalories) (goal: \(calorieGoal), \(Int(calorieAdherence * 100))% adherence)")
                parts.append("Avg daily protein: \(Int(averageProtein))g (goal: \(proteinGoal)g, \(Int(proteinAdherence * 100))% adherence)")
            }
            parts.append("Meals logged: \(mealCount)")
            parts.append("Workouts: \(workoutsCompleted)")

            if !workoutTypes.isEmpty {
                parts.append("Workout types: \(workoutTypes.joined(separator: ", "))")
            }

            if let change = weightChangeFormatted {
                parts.append("Weight change: \(change)")
            }

            if !foodHighlights.isEmpty {
                parts.append("Common foods: \(foodHighlights.joined(separator: ", "))")
            }

            return parts.joined(separator: "\n")
        }
    }

    // MARK: - Get Weekly Summary

    func getWeeklySummary(
        profile: UserProfile,
        foodEntries: [FoodEntry],
        workouts: [WorkoutSession],
        liveWorkouts: [LiveWorkout],
        weightEntries: [WeightEntry]
    ) -> WeeklySummary {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️ getWeeklySummary: Starting...")
        print("   - foodEntries: \(foodEntries.count), workouts: \(workouts.count), weights: \(weightEntries.count)")

        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!

        // Filter to this week and last week
        let weeklyFood = foodEntries.filter { $0.loggedAt >= weekStart }
        let lastWeekFood = foodEntries.filter { $0.loggedAt >= twoWeeksAgo && $0.loggedAt < weekStart }
        let weeklyWorkouts = workouts.filter { $0.loggedAt >= weekStart }
        let lastWeekWorkouts = workouts.filter { $0.loggedAt >= twoWeeksAgo && $0.loggedAt < weekStart }
        let weeklyLiveWorkouts = liveWorkouts.filter { $0.startedAt >= weekStart }
        let lastWeekLiveWorkouts = liveWorkouts.filter {
            $0.startedAt >= twoWeeksAgo && $0.startedAt < weekStart
        }
        let allWeights = weightEntries.sorted { $0.loggedAt < $1.loggedAt }
        let weeklyWeights = allWeights.filter { $0.loggedAt >= weekStart }

        // Build daily data for chart (excluding 0-calorie days from averages)
        let dailyData = buildDailyData(
            from: weeklyFood,
            weekStart: weekStart,
            calorieGoal: profile.dailyCalorieGoal,
            proteinGoal: profile.dailyProteinGoal,
            calendar: calendar
        )

        // Only count days that were actually tracked (non-zero calories)
        let trackedDays = dailyData.filter { $0.wasTracked }
        let daysTracked = trackedDays.count

        // Calculate nutrition stats (only from tracked days)
        let totalCalories = trackedDays.reduce(0) { $0 + $1.calories }
        let totalProtein = trackedDays.reduce(0.0) { $0 + $1.protein }
        let totalCarbs = weeklyFood.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat = weeklyFood.reduce(0.0) { $0 + $1.fatGrams }

        let avgCalories = daysTracked > 0 ? totalCalories / daysTracked : 0
        let avgProtein = daysTracked > 0 ? totalProtein / Double(daysTracked) : 0

        // Adherence (only from tracked days)
        let calorieGoal = profile.dailyCalorieGoal
        let proteinGoal = profile.dailyProteinGoal
        let expectedCalories = calorieGoal * daysTracked
        let expectedProtein = proteinGoal * daysTracked
        let calorieAdherence = expectedCalories > 0 ? Double(totalCalories) / Double(expectedCalories) : 0
        let proteinAdherence = expectedProtein > 0 ? totalProtein / Double(expectedProtein) : 0

        // Workouts
        let totalWorkouts = weeklyWorkouts.count + weeklyLiveWorkouts.count
        var workoutTypes: [String] = []
        workoutTypes.append(contentsOf: weeklyWorkouts.map { $0.displayName })
        workoutTypes.append(contentsOf: weeklyLiveWorkouts.compactMap { $0.workoutType })
        let uniqueTypes = Array(Set(workoutTypes))

        let workoutMinutes = weeklyLiveWorkouts.reduce(0) { total, workout in
            if let end = workout.completedAt {
                return total + Int(end.timeIntervalSince(workout.startedAt) / 60)
            }
            return total
        }

        // Weight tracking
        let weeklyWeightStart = weeklyWeights.first?.weightKg
        let currentWeight = allWeights.last?.weightKg ?? profile.currentWeightKg
        let weightChange: Double? = if let start = weeklyWeightStart, let end = currentWeight {
            end - start
        } else {
            nil
        }

        let lastWeighIn = allWeights.last?.loggedAt
        let daysSinceWeighIn: Int? = if let last = lastWeighIn {
            calendar.dateComponents([.day], from: last, to: now).day
        } else {
            nil
        }

        // Food highlights
        let foodNames = weeklyFood.map { $0.name.lowercased() }
        var frequency: [String: Int] = [:]
        for name in foodNames {
            frequency[name, default: 0] += 1
        }
        let topFoods = frequency.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }

        // Week comparison
        let weekComparison = buildWeekComparison(
            thisWeekFood: weeklyFood,
            lastWeekFood: lastWeekFood,
            thisWeekWorkouts: totalWorkouts,
            lastWeekWorkouts: lastWeekWorkouts.count + lastWeekLiveWorkouts.count,
            thisWeekDaysTracked: daysTracked,
            lastWeekFood: lastWeekFood,
            calendar: calendar
        )

        // Detect wins
        let wins = detectWins(
            daysTracked: daysTracked,
            calorieAdherence: calorieAdherence,
            proteinAdherence: proteinAdherence,
            workoutsCompleted: totalWorkouts,
            dailyData: trackedDays,
            weekComparison: weekComparison
        )

        // Detect patterns
        let patterns = detectPatterns(
            dailyData: dailyData,
            weeklyFood: weeklyFood,
            calendar: calendar
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ getWeeklySummary: Completed in \(String(format: "%.3f", elapsed))s")

        return WeeklySummary(
            weekStartDate: weekStart,
            weekEndDate: now,
            daysTracked: daysTracked,
            totalDays: 7,
            totalCalories: totalCalories,
            averageDailyCalories: avgCalories,
            totalProtein: totalProtein,
            averageProtein: avgProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            calorieGoal: calorieGoal,
            proteinGoal: proteinGoal,
            calorieAdherence: calorieAdherence,
            proteinAdherence: proteinAdherence,
            dailyData: dailyData,
            workoutsCompleted: totalWorkouts,
            workoutTypes: uniqueTypes,
            totalWorkoutMinutes: workoutMinutes,
            startingWeight: weeklyWeightStart,
            currentWeight: currentWeight,
            weightChange: weightChange,
            lastWeighInDate: lastWeighIn,
            daysSinceWeighIn: daysSinceWeighIn,
            foodHighlights: Array(topFoods),
            mealCount: weeklyFood.count,
            weekComparison: weekComparison,
            detectedWins: wins,
            detectedPatterns: patterns
        )
    }

    // MARK: - Build Daily Data

    private func buildDailyData(
        from foodEntries: [FoodEntry],
        weekStart: Date,
        calorieGoal: Int,
        proteinGoal: Int,
        calendar: Calendar
    ) -> [DailyData] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var dailyData: [DailyData] = []

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let dayEntries = foodEntries.filter { $0.loggedAt >= dayStart && $0.loggedAt < dayEnd }
            let dayCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let dayProtein = dayEntries.reduce(0.0) { $0 + $1.proteinGrams }

            dailyData.append(DailyData(
                date: date,
                dayName: dayFormatter.string(from: date),
                calories: dayCalories,
                calorieGoal: calorieGoal,
                protein: dayProtein,
                proteinGoal: proteinGoal,
                wasTracked: dayCalories > 0
            ))
        }

        return dailyData
    }

    // MARK: - Build Week Comparison

    private func buildWeekComparison(
        thisWeekFood: [FoodEntry],
        lastWeekFood: [FoodEntry],
        thisWeekWorkouts: Int,
        lastWeekWorkouts: Int,
        thisWeekDaysTracked: Int,
        lastWeekFood lastWeekFoodEntries: [FoodEntry],
        calendar: Calendar
    ) -> WeekComparison? {
        // Calculate last week's tracked days
        let lastWeekDays = Set(lastWeekFoodEntries.map { calendar.startOfDay(for: $0.loggedAt) })
        let lastWeekDaysTracked = lastWeekDays.count

        guard lastWeekDaysTracked > 0 else { return nil }

        let thisWeekTotalCal = thisWeekFood.reduce(0) { $0 + $1.calories }
        let lastWeekTotalCal = lastWeekFoodEntries.reduce(0) { $0 + $1.calories }

        let thisWeekAvgCal = thisWeekDaysTracked > 0 ? thisWeekTotalCal / thisWeekDaysTracked : 0
        let lastWeekAvgCal = lastWeekTotalCal / lastWeekDaysTracked

        let thisWeekProtein = thisWeekFood.reduce(0.0) { $0 + $1.proteinGrams }
        let lastWeekProtein = lastWeekFoodEntries.reduce(0.0) { $0 + $1.proteinGrams }

        let thisWeekAvgProtein = thisWeekDaysTracked > 0 ? thisWeekProtein / Double(thisWeekDaysTracked) : 0
        let lastWeekAvgProtein = lastWeekProtein / Double(lastWeekDaysTracked)

        return WeekComparison(
            calorieChange: thisWeekAvgCal - lastWeekAvgCal,
            proteinChange: thisWeekAvgProtein - lastWeekAvgProtein,
            workoutChange: thisWeekWorkouts - lastWeekWorkouts,
            daysTrackedChange: thisWeekDaysTracked - lastWeekDaysTracked
        )
    }

    // MARK: - Detect Wins

    private func detectWins(
        daysTracked: Int,
        calorieAdherence: Double,
        proteinAdherence: Double,
        workoutsCompleted: Int,
        dailyData: [DailyData],
        weekComparison: WeekComparison?
    ) -> DetectedWins {
        var wins: [String] = []

        // Consistency wins
        if daysTracked >= 7 {
            wins.append("Logged every day this week!")
        } else if daysTracked >= 5 {
            wins.append("Tracked \(daysTracked) out of 7 days")
        }

        // Calorie adherence wins
        if calorieAdherence >= 0.95 && calorieAdherence <= 1.05 {
            wins.append("Hit your calorie target almost perfectly")
        } else if calorieAdherence >= 0.9 && calorieAdherence <= 1.1 {
            wins.append("Stayed within 10% of calorie goal")
        }

        // Protein wins
        if proteinAdherence >= 0.9 {
            wins.append("Crushed your protein goal")
        } else if proteinAdherence >= 0.8 {
            wins.append("Strong protein intake")
        }

        // Workout wins
        if workoutsCompleted >= 5 {
            wins.append("5+ workouts this week!")
        } else if workoutsCompleted >= 3 {
            wins.append("Got \(workoutsCompleted) workouts in")
        }

        // Days within target
        let daysOnTarget = dailyData.filter { $0.isWithinTarget }.count
        if daysOnTarget >= 5 {
            wins.append("\(daysOnTarget) days within calorie target")
        }

        // Improvement wins
        if let comparison = weekComparison {
            if comparison.workoutChange > 0 {
                wins.append("More workouts than last week")
            }
            if comparison.daysTrackedChange > 0 {
                wins.append("Better tracking than last week")
            }
            if comparison.proteinChange > 10 {
                wins.append("Protein up from last week")
            }
        }

        return DetectedWins(items: wins, hasAnyWins: !wins.isEmpty)
    }

    // MARK: - Detect Patterns

    private func detectPatterns(
        dailyData: [DailyData],
        weeklyFood: [FoodEntry],
        calendar: Calendar
    ) -> DetectedPatterns {
        var patterns: [String] = []

        // Weekend vs weekday pattern
        let weekdays = dailyData.filter { day in
            let weekday = calendar.component(.weekday, from: day.date)
            return weekday >= 2 && weekday <= 6 // Mon-Fri
        }
        let weekends = dailyData.filter { day in
            let weekday = calendar.component(.weekday, from: day.date)
            return weekday == 1 || weekday == 7 // Sat-Sun
        }

        let weekdayAvg = weekdays.isEmpty ? 0 : weekdays.filter { $0.wasTracked }.reduce(0) { $0 + $1.calories } / max(1, weekdays.filter { $0.wasTracked }.count)
        let weekendAvg = weekends.isEmpty ? 0 : weekends.filter { $0.wasTracked }.reduce(0) { $0 + $1.calories } / max(1, weekends.filter { $0.wasTracked }.count)

        if weekendAvg > 0 && weekdayAvg > 0 {
            let diff = weekendAvg - weekdayAvg
            if diff > 300 {
                patterns.append("Weekends tend to be higher calorie (+\(diff) avg)")
            } else if diff < -300 {
                patterns.append("Weekdays tend to be higher calorie")
            }
        }

        // Tracking consistency pattern
        let trackedDays = dailyData.filter { $0.wasTracked }
        let untrackedDays = dailyData.filter { !$0.wasTracked }

        if untrackedDays.count >= 3 {
            let untrackedDayNames = untrackedDays.map { $0.dayName }.joined(separator: ", ")
            patterns.append("Missed tracking on \(untrackedDayNames)")
        }

        // Protein consistency
        let proteinDays = trackedDays.filter { $0.protein >= Double($0.proteinGoal) * 0.9 }
        if proteinDays.count < trackedDays.count / 2 && trackedDays.count >= 3 {
            patterns.append("Protein was below target most days")
        }

        return DetectedPatterns(insights: patterns)
    }

    // MARK: - Create Check-In

    func createCheckIn(for profile: UserProfile, summary: WeeklySummary, sessionId: UUID) -> WeeklyCheckIn {
        let checkIn = WeeklyCheckIn()

        let calendar = Calendar.current
        checkIn.weekNumber = calendar.component(.weekOfYear, from: Date())

        checkIn.totalCaloriesConsumed = summary.totalCalories
        checkIn.averageDailyCalories = summary.averageDailyCalories
        checkIn.totalProteinGrams = summary.totalProtein
        checkIn.daysTracked = summary.daysTracked
        checkIn.workoutsCompleted = summary.workoutsCompleted
        checkIn.startingWeightKg = summary.startingWeight
        checkIn.endingWeightKg = summary.currentWeight
        checkIn.calorieGoal = summary.calorieGoal
        checkIn.calorieAdherence = summary.calorieAdherence
        checkIn.chatSessionId = sessionId

        return checkIn
    }

    // MARK: - Complete Check-In

    func completeCheckIn(
        _ checkIn: WeeklyCheckIn,
        aiSummary: String,
        aiInsights: String,
        aiRecommendations: String,
        userEnergyLevel: Int? = nil,
        userWentWell: String? = nil,
        userChallenges: String? = nil,
        userFocusNextWeek: String? = nil
    ) {
        checkIn.aiSummary = aiSummary
        checkIn.aiInsights = aiInsights
        checkIn.aiRecommendations = aiRecommendations
        checkIn.isCompleted = true
        checkIn.completedAt = Date()

        // Store user reflection data if provided
        if let energy = userEnergyLevel {
            checkIn.userEnergyLevel = energy
        }
        if let wentWell = userWentWell, !wentWell.isEmpty {
            checkIn.userWentWell = wentWell
        }
        if let challenges = userChallenges, !challenges.isEmpty {
            checkIn.userChallenges = challenges
        }
        if let focus = userFocusNextWeek, !focus.isEmpty {
            checkIn.userFocusNextWeek = focus
        }
    }

    // MARK: - Record Plan Changes

    func recordPlanChanges(
        _ checkIn: WeeklyCheckIn,
        previousCalories: Int,
        newCalories: Int,
        previousProtein: Int,
        newProtein: Int,
        rationale: String
    ) {
        checkIn.planChangesApplied = true
        checkIn.previousCalories = previousCalories
        checkIn.newCalories = newCalories
        checkIn.previousProtein = previousProtein
        checkIn.newProtein = newProtein
        checkIn.changeRationale = rationale
    }
}
