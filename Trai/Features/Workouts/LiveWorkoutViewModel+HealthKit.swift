//
//  LiveWorkoutViewModel+HealthKit.swift
//  Trai
//
//  HealthKit merge functionality for live workouts
//

import Foundation

extension LiveWorkoutViewModel {
    // MARK: - Apple Watch Workout Merge

    /// Check for overlapping Apple Watch workout and merge data
    func mergeWithAppleWatchWorkout() async {
        guard let healthKitService else { return }

        do {
            // Search in a wider window to catch workouts that started before/after ours
            let searchStart = workout.startedAt.addingTimeInterval(-15 * 60) // 15 min before
            let searchEnd = (workout.completedAt ?? Date()).addingTimeInterval(15 * 60) // 15 min after

            let healthKitWorkouts = try await healthKitService.fetchWorkoutsAuthorized(
                from: searchStart,
                to: searchEnd
            )

            guard let match = healthKitService.bestOverlappingWorkout(for: workout, from: healthKitWorkouts) else { return }

            // Merge data from Apple Watch
            workout.mergedHealthKitWorkoutID = match.healthKitWorkoutID
            if let calories = match.caloriesBurned {
                workout.healthKitCalories = Double(calories)
            }
            if let avgHR = match.averageHeartRate {
                workout.healthKitAvgHeartRate = Double(avgHR)
            }

            save()
        } catch {
            // Silently fail - HealthKit merge is optional
            print("HealthKit merge failed: \(error)")
        }
    }
}
