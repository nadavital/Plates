//
//  LiveWorkoutViewModel+HealthKit.swift
//  Plates
//
//  HealthKit merge functionality for live workouts
//

import Foundation

extension LiveWorkoutViewModel {
    // MARK: - Apple Watch Workout Merge

    /// Check for overlapping Apple Watch workout and merge data
    func mergeWithAppleWatchWorkout() async {
        let healthKitService = HealthKitService()

        do {
            try await healthKitService.requestAuthorization()

            // Search in a wider window to catch workouts that started before/after ours
            let searchStart = workout.startedAt.addingTimeInterval(-15 * 60) // 15 min before
            let searchEnd = (workout.completedAt ?? Date()).addingTimeInterval(15 * 60) // 15 min after

            let healthKitWorkouts = try await healthKitService.fetchWorkouts(
                from: searchStart,
                to: searchEnd
            )

            // Find best overlapping workout (prefer strength training types)
            let overlapping = findBestOverlappingWorkout(from: healthKitWorkouts)

            guard let match = overlapping else { return }

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

    /// Find the best overlapping workout from HealthKit results
    func findBestOverlappingWorkout(from healthKitWorkouts: [WorkoutSession]) -> WorkoutSession? {
        let ourStart = workout.startedAt
        let ourEnd = workout.completedAt ?? Date()

        // Filter to only overlapping workouts
        let overlapping = healthKitWorkouts.filter { hkWorkout in
            let hkStart = hkWorkout.loggedAt
            let hkEnd = calculateHealthKitEndDate(for: hkWorkout) ?? hkStart

            // Check for any overlap
            return hkStart <= ourEnd && hkEnd >= ourStart
        }

        // Prefer strength training workouts ("Traditional Strength Training", "Functional Strength Training")
        let strengthWorkouts = overlapping.filter {
            $0.healthKitWorkoutType?.lowercased().contains("strength") == true ||
            $0.healthKitWorkoutType?.lowercased().contains("weight") == true
        }

        // Return best match: strength workout if available, otherwise first overlapping
        return strengthWorkouts.first ?? overlapping.first
    }

    func calculateHealthKitEndDate(for workout: WorkoutSession) -> Date? {
        guard let duration = workout.durationMinutes, duration > 0 else {
            // If no duration, assume a reasonable default (e.g., 1 hour)
            return workout.loggedAt.addingTimeInterval(60 * 60)
        }
        return workout.loggedAt.addingTimeInterval(duration * 60)
    }
}
