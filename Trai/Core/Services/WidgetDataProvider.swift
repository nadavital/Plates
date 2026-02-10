//
//  WidgetDataProvider.swift
//  Trai
//
//  Provides fitness data to widgets via App Groups UserDefaults
//

import Foundation
import SwiftData
import WidgetKit

/// Service to sync fitness data to widgets via App Groups
@MainActor @Observable
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let suiteName = SharedStorageKeys.AppGroup.suiteName
    private let dataKey = SharedStorageKeys.AppGroup.widgetData

    private init() {}

    // MARK: - Public Methods

    /// Update widget data from current app state
    func updateWidgetData(modelContext: ModelContext) {
        let data = buildWidgetData(modelContext: modelContext)
        saveWidgetData(data)

        // Tell WidgetKit to refresh all widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Read current widget data (for debugging)
    func readWidgetData() -> WidgetData? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let jsonData = defaults.data(forKey: dataKey),
              let data = try? JSONDecoder().decode(WidgetData.self, from: jsonData) else {
            return nil
        }
        return data
    }

    // MARK: - Private Methods

    private func buildWidgetData(modelContext: ModelContext) -> WidgetData {
        // Get user profile for goals
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profile = (try? modelContext.fetch(profileDescriptor))?.first

        let calorieGoal = profile?.effectiveCalorieGoal ?? 2000
        let proteinGoal = profile?.dailyProteinGoal ?? 150
        let carbsGoal = profile?.dailyCarbsGoal ?? 200
        let fatGoal = profile?.dailyFatGoal ?? 65

        // Get today's food entries
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.loggedAt >= startOfDay && entry.loggedAt < endOfDay
            }
        )
        let todayFoods = (try? modelContext.fetch(foodDescriptor)) ?? []

        let caloriesConsumed = todayFoods.reduce(0) { $0 + $1.calories }
        let proteinConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.proteinGrams) }
        let carbsConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.carbsGrams) }
        let fatConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.fatGrams) }

        // Get muscle recovery info
        let recoveryService = MuscleRecoveryService()
        let recoveryInfo = recoveryService.getRecoveryStatus(modelContext: modelContext)
        let readyMuscleCount = recoveryInfo.filter { $0.status == .ready }.count

        // Get recommended workout
        var recommendedWorkout: String?
        if let workoutPlan = profile?.workoutPlan {
            if let best = recoveryService.getBestTemplateForToday(plan: workoutPlan, modelContext: modelContext) {
                recommendedWorkout = best.template.name
            }
        }

        // Check if workout completed today
        let workoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { workout in
                workout.completedAt != nil && workout.completedAt! >= startOfDay
            }
        )
        let todayWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        let todayWorkoutCompleted = !todayWorkouts.isEmpty

        // Calculate workout streak
        let workoutStreak = calculateWorkoutStreak(modelContext: modelContext)

        return WidgetData(
            caloriesConsumed: caloriesConsumed,
            calorieGoal: calorieGoal,
            proteinConsumed: proteinConsumed,
            proteinGoal: proteinGoal,
            carbsConsumed: carbsConsumed,
            carbsGoal: carbsGoal,
            fatConsumed: fatConsumed,
            fatGoal: fatGoal,
            readyMuscleCount: readyMuscleCount,
            recommendedWorkout: recommendedWorkout,
            workoutStreak: workoutStreak,
            todayWorkoutCompleted: todayWorkoutCompleted,
            lastUpdated: Date()
        )
    }

    private func calculateWorkoutStreak(modelContext: ModelContext) -> Int {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: Date())
        var streak = 0

        // Check backwards day by day
        for _ in 0..<365 {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            let descriptor = FetchDescriptor<LiveWorkout>(
                predicate: #Predicate { workout in
                    workout.completedAt != nil &&
                    workout.completedAt! >= currentDate &&
                    workout.completedAt! < nextDay
                }
            )

            let workoutsOnDay = (try? modelContext.fetch(descriptor)) ?? []

            if workoutsOnDay.isEmpty {
                // Allow one rest day in streak
                if streak > 0 {
                    // Check if there was a workout the day before
                    let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate)!
                    let prevDescriptor = FetchDescriptor<LiveWorkout>(
                        predicate: #Predicate { workout in
                            workout.completedAt != nil &&
                            workout.completedAt! >= previousDay &&
                            workout.completedAt! < currentDate
                        }
                    )
                    let prevWorkouts = (try? modelContext.fetch(prevDescriptor)) ?? []
                    if prevWorkouts.isEmpty {
                        break // Two consecutive rest days ends streak
                    }
                } else if currentDate != calendar.startOfDay(for: Date()) {
                    // Not today and no workout = streak broken (unless it's today)
                    break
                }
            } else {
                streak += 1
            }

            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        return streak
    }

    private func saveWidgetData(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let jsonData = try? JSONEncoder().encode(data) else {
            return
        }
        defaults.set(jsonData, forKey: dataKey)
    }
}
