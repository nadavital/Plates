//
//  GeminiFunctionExecutor+PlanWorkout.swift
//  Plates
//
//  Plan and workout function execution
//

import Foundation
import SwiftData

extension GeminiFunctionExecutor {

    // MARK: - Plan Functions

    func executeGetUserPlan() -> ExecutionResult {
        guard let profile = userProfile else {
            return .dataResponse(FunctionResult(
                name: "get_user_plan",
                response: ["error": "No user profile found"]
            ))
        }

        return .dataResponse(FunctionResult(
            name: "get_user_plan",
            response: [
                "goal": profile.goal.rawValue,
                "daily_targets": [
                    "calories": profile.dailyCalorieGoal,
                    "protein": profile.dailyProteinGoal,
                    "carbs": profile.dailyCarbsGoal,
                    "fat": profile.dailyFatGoal
                ],
                "activity_level": profile.activityLevel,
                "current_weight_kg": profile.currentWeightKg ?? 0,
                "target_weight_kg": profile.targetWeightKg ?? 0
            ]
        ))
    }

    func executeUpdateUserPlan(_ args: [String: Any]) -> ExecutionResult {
        let suggestion = PlanUpdateSuggestion(
            calories: args["calories"] as? Int,
            proteinGrams: args["protein_grams"] as? Int,
            carbsGrams: args["carbs_grams"] as? Int,
            fatGrams: args["fat_grams"] as? Int,
            goal: args["goal"] as? String,
            rationale: args["rationale"] as? String
        )

        return .suggestedPlanUpdate(suggestion)
    }

    // MARK: - Workout Functions

    func executeGetRecentWorkouts(_ args: [String: Any]) -> ExecutionResult {
        let calendar = Calendar.current
        let today = Date()
        let limit = args["limit"] as? Int ?? 10

        // Check if date range is specified
        let hasDateRange = args["date"] != nil || args["days_back"] != nil || args["range_days"] != nil

        var workouts: [WorkoutSession] = []
        var dateDescription = "recent"

        if hasDateRange {
            let (startDate, endDate, description) = determineWorkoutDateRange(
                args: args,
                calendar: calendar,
                today: today
            )
            dateDescription = description

            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            workouts = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            // Default: get recent workouts with limit
            let descriptor = FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            workouts = (try? modelContext.fetch(descriptor)) ?? []
            workouts = Array(workouts.prefix(limit))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"

        let formattedWorkouts = workouts.map { workout -> [String: Any] in
            return [
                "id": workout.id.uuidString,
                "name": workout.displayName,
                "type": workout.isStrengthTraining ? "strength" : "cardio",
                "date": dateFormatter.string(from: workout.loggedAt),
                "duration_minutes": workout.durationMinutes ?? 0,
                "sets": workout.sets,
                "reps": workout.reps,
                "weight_kg": workout.weightKg ?? 0
            ]
        }

        return .dataResponse(FunctionResult(
            name: "get_recent_workouts",
            response: [
                "date_range": dateDescription,
                "workouts": formattedWorkouts,
                "count": workouts.count
            ]
        ))
    }

    /// Determines the date range for workout queries
    private func determineWorkoutDateRange(
        args: [String: Any],
        calendar: Calendar,
        today: Date
    ) -> (startDate: Date, endDate: Date, description: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Option 1: Specific date provided
        if let dateString = args["date"] as? String,
           let specificDate = dateFormatter.date(from: dateString) {
            let startOfDay = calendar.startOfDay(for: specificDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            if rangeDays == 1 {
                return (startOfDay, endOfRange, dateString)
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(dateString) to \(endDateString)")
            }
        }

        // Option 2: Days back from today
        if let daysBack = args["days_back"] as? Int {
            let targetDate = calendar.date(byAdding: .day, value: -daysBack, to: today)!
            let startOfDay = calendar.startOfDay(for: targetDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            let startDateString = dateFormatter.string(from: startOfDay)
            if rangeDays == 1 {
                let dayName = daysBack == 1 ? "yesterday" : "\(daysBack) days ago"
                return (startOfDay, endOfRange, "\(startDateString) (\(dayName))")
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(startDateString) to \(endDateString)")
            }
        }

        // Default with range_days only: start from today and go back
        let rangeDays = (args["range_days"] as? Int) ?? 7
        let startDate = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: calendar.startOfDay(for: today))!
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: calendar.startOfDay(for: today))
        return (startDate, endOfRange, "\(startDateString) to \(endDateString)")
    }

    func executeLogWorkout(_ args: [String: Any]) -> ExecutionResult {
        guard let type = args["type"] as? String else {
            return .dataResponse(FunctionResult(
                name: "log_workout",
                response: ["error": "Missing workout type"]
            ))
        }

        let workoutName = args["name"] as? String  // Trai-generated name
        let durationMinutes = args["duration_minutes"] as? Int
        let notes = args["notes"] as? String

        // Parse exercises with per-set data
        var exercises: [SuggestedWorkoutLog.LoggedExercise] = []
        if let exercisesData = args["exercises"] as? [[String: Any]] {
            for exerciseData in exercisesData {
                guard let name = exerciseData["name"] as? String else { continue }

                var sets: [SuggestedWorkoutLog.LoggedExercise.SetData] = []

                // New format: sets is an array of {reps, weight_kg}
                if let setsArray = exerciseData["sets"] as? [[String: Any]] {
                    for setData in setsArray {
                        let reps = setData["reps"] as? Int ?? 10
                        let weight = setData["weight_kg"] as? Double
                        sets.append(SuggestedWorkoutLog.LoggedExercise.SetData(
                            reps: reps,
                            weightKg: weight
                        ))
                    }
                }
                // Legacy format: sets/reps as integers
                else if let setCount = exerciseData["sets"] as? Int {
                    let reps = exerciseData["reps"] as? Int ?? 10
                    let weight = exerciseData["weight_kg"] as? Double
                    for _ in 0..<setCount {
                        sets.append(SuggestedWorkoutLog.LoggedExercise.SetData(
                            reps: reps,
                            weightKg: weight
                        ))
                    }
                }

                if !sets.isEmpty {
                    exercises.append(SuggestedWorkoutLog.LoggedExercise(
                        name: name,
                        sets: sets
                    ))
                }
            }
        }

        // Return suggestion for user approval (don't save yet)
        let suggestion = SuggestedWorkoutLog(
            name: workoutName,
            workoutType: type,
            durationMinutes: durationMinutes,
            exercises: exercises,
            notes: notes
        )

        return .suggestedWorkoutLog(suggestion)
    }

    // MARK: - Weight Functions

    func executeGetWeightHistory(_ args: [String: Any]) -> ExecutionResult {
        let calendar = Calendar.current
        let today = Date()
        let limit = args["limit"] as? Int ?? 10

        // Check if date range is specified
        let hasDateRange = args["date"] != nil || args["days_back"] != nil || args["range_days"] != nil

        var entries: [WeightEntry] = []
        var dateDescription = "recent"

        if hasDateRange {
            let (startDate, endDate, description) = determineWeightDateRange(
                args: args,
                calendar: calendar,
                today: today
            )
            dateDescription = description

            let descriptor = FetchDescriptor<WeightEntry>(
                predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            entries = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            // Default: get recent entries with limit
            let descriptor = FetchDescriptor<WeightEntry>(
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            entries = (try? modelContext.fetch(descriptor)) ?? []
            entries = Array(entries.prefix(limit))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"

        let formattedEntries = entries.map { entry -> [String: Any] in
            var result: [String: Any] = [
                "id": entry.id.uuidString,
                "weight_kg": entry.weightKg,
                "weight_lbs": entry.weightLbs,
                "date": dateFormatter.string(from: entry.loggedAt)
            ]
            if let bodyFat = entry.bodyFatPercentage {
                result["body_fat_percentage"] = bodyFat
            }
            if let leanMass = entry.calculatedLeanMassKg {
                result["lean_mass_kg"] = leanMass
            }
            return result
        }

        // Calculate trends if we have multiple entries
        var trends: [String: Any]?
        if entries.count >= 2 {
            let oldest = entries.last!
            let newest = entries.first!
            let weightChange = newest.weightKg - oldest.weightKg
            let daysBetween = calendar.dateComponents([.day], from: oldest.loggedAt, to: newest.loggedAt).day ?? 1

            trends = [
                "weight_change_kg": weightChange,
                "weight_change_lbs": weightChange * 2.20462,
                "days_tracked": daysBetween,
                "direction": weightChange > 0 ? "gained" : weightChange < 0 ? "lost" : "maintained"
            ]
        }

        // Include current and target weight from profile
        var profileInfo: [String: Any] = [:]
        if let profile = userProfile {
            if let currentWeight = profile.currentWeightKg {
                profileInfo["current_weight_kg"] = currentWeight
            }
            if let targetWeight = profile.targetWeightKg {
                profileInfo["target_weight_kg"] = targetWeight
                if let currentWeight = profile.currentWeightKg {
                    profileInfo["remaining_to_target_kg"] = currentWeight - targetWeight
                }
            }
        }

        var response: [String: Any] = [
            "date_range": dateDescription,
            "entries": formattedEntries,
            "count": entries.count
        ]

        if let trends {
            response["trends"] = trends
        }
        if !profileInfo.isEmpty {
            response["profile"] = profileInfo
        }

        return .dataResponse(FunctionResult(
            name: "get_weight_history",
            response: response
        ))
    }

    /// Determines the date range for weight queries
    private func determineWeightDateRange(
        args: [String: Any],
        calendar: Calendar,
        today: Date
    ) -> (startDate: Date, endDate: Date, description: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Option 1: Specific date provided
        if let dateString = args["date"] as? String,
           let specificDate = dateFormatter.date(from: dateString) {
            let startOfDay = calendar.startOfDay(for: specificDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            if rangeDays == 1 {
                return (startOfDay, endOfRange, dateString)
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(dateString) to \(endDateString)")
            }
        }

        // Option 2: Days back from today
        if let daysBack = args["days_back"] as? Int {
            let targetDate = calendar.date(byAdding: .day, value: -daysBack, to: today)!
            let startOfDay = calendar.startOfDay(for: targetDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            let startDateString = dateFormatter.string(from: startOfDay)
            if rangeDays == 1 {
                let dayName = daysBack == 1 ? "yesterday" : "\(daysBack) days ago"
                return (startOfDay, endOfRange, "\(startDateString) (\(dayName))")
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(startDateString) to \(endDateString)")
            }
        }

        // Default with range_days only: start from today and go back
        let rangeDays = (args["range_days"] as? Int) ?? 30
        let startDate = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: calendar.startOfDay(for: today))!
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: calendar.startOfDay(for: today))
        return (startDate, endOfRange, "\(startDateString) to \(endDateString)")
    }
}
