//
//  WorkoutTemplateService.swift
//  Plates
//
//  Creates LiveWorkouts from templates with history-based pre-filling
//

import Foundation
import SwiftData

@MainActor @Observable
final class WorkoutTemplateService {

    // MARK: - Progression Suggestion

    struct ProgressionSuggestion {
        let suggestedWeight: Double
        let previousWeight: Double
        let previousReps: Int
        let reason: String
        let isNewRecord: Bool
    }

    // MARK: - Create Workout from Template

    /// Create a LiveWorkout from a template, pre-filling with last used weights
    func createWorkoutFromTemplate(
        _ template: WorkoutPlan.WorkoutTemplate,
        progressionStrategy: WorkoutPlan.ProgressionStrategy,
        modelContext: ModelContext
    ) -> LiveWorkout {
        // Map template muscle groups to LiveWorkout.MuscleGroup
        let muscleGroups = template.targetMuscleGroups.compactMap { name in
            LiveWorkout.MuscleGroup(rawValue: name)
        }

        let workout = LiveWorkout(
            name: template.name,
            workoutType: .strength,
            targetMuscleGroups: muscleGroups
        )

        // Create entries from exercise templates
        var entries: [LiveWorkoutEntry] = []

        for exerciseTemplate in template.exercises.sorted(by: { $0.order < $1.order }) {
            let entry = LiveWorkoutEntry(
                exerciseName: exerciseTemplate.exerciseName,
                orderIndex: exerciseTemplate.order
            )

            // Get last performance for this exercise
            let lastPerformance = getLastPerformance(
                exerciseName: exerciseTemplate.exerciseName,
                modelContext: modelContext
            )

            // Calculate suggested weight with progression
            let (weight, reps) = calculateSuggestedWeightAndReps(
                lastPerformance: lastPerformance,
                template: exerciseTemplate,
                strategy: progressionStrategy
            )

            // Add sets based on template
            for _ in 0..<exerciseTemplate.defaultSets {
                entry.addSet(LiveWorkoutEntry.SetData(
                    reps: reps,
                    weightKg: weight,
                    completed: false,
                    isWarmup: false
                ))
            }

            entries.append(entry)
        }

        workout.entries = entries
        return workout
    }

    // MARK: - Get Last Performance

    /// Get the most recent performance for an exercise
    func getLastPerformance(
        exerciseName: String,
        modelContext: ModelContext
    ) -> ExerciseHistory? {
        let descriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Get multiple past performances for trend analysis
    func getPerformanceHistory(
        exerciseName: String,
        limit: Int = 5,
        modelContext: ModelContext
    ) -> [ExerciseHistory] {
        var descriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Progressive Overload

    /// Suggest weight progression based on history and strategy
    func suggestProgression(
        exerciseName: String,
        lastPerformance: ExerciseHistory,
        progressionStrategy: WorkoutPlan.ProgressionStrategy,
        targetReps: Int
    ) -> ProgressionSuggestion? {
        let lastWeight = lastPerformance.bestSetWeightKg
        let lastReps = lastPerformance.bestSetReps

        // No progression if no weight data
        guard lastWeight > 0 else { return nil }

        switch progressionStrategy.type {
        case .linearProgression:
            // Always try to add weight
            let newWeight = lastWeight + progressionStrategy.weightIncrementKg
            return ProgressionSuggestion(
                suggestedWeight: newWeight,
                previousWeight: lastWeight,
                previousReps: lastReps,
                reason: "Linear progression: +\(progressionStrategy.weightIncrementKg)kg from last session",
                isNewRecord: true
            )

        case .doubleProgression:
            // Increase reps first, then weight
            if let repsTrigger = progressionStrategy.repsTrigger, lastReps >= repsTrigger {
                let newWeight = lastWeight + progressionStrategy.weightIncrementKg
                return ProgressionSuggestion(
                    suggestedWeight: newWeight,
                    previousWeight: lastWeight,
                    previousReps: lastReps,
                    reason: "Hit \(lastReps) reps - time to add weight!",
                    isNewRecord: true
                )
            } else {
                // Maintain weight, try for more reps
                return ProgressionSuggestion(
                    suggestedWeight: lastWeight,
                    previousWeight: lastWeight,
                    previousReps: lastReps,
                    reason: "Last: \(lastReps) reps @ \(Int(lastWeight))kg",
                    isNewRecord: false
                )
            }

        case .periodized:
            // Maintain weight but provide context
            return ProgressionSuggestion(
                suggestedWeight: lastWeight,
                previousWeight: lastWeight,
                previousReps: lastReps,
                reason: "Last session: \(lastReps) reps @ \(Int(lastWeight))kg",
                isNewRecord: false
            )
        }
    }

    /// Check if user has been at the same weight for multiple sessions
    func shouldSuggestWeightIncrease(
        exerciseName: String,
        currentWeight: Double,
        sessionsAtWeight: Int = 3,
        modelContext: ModelContext
    ) -> Bool {
        let history = getPerformanceHistory(
            exerciseName: exerciseName,
            limit: sessionsAtWeight,
            modelContext: modelContext
        )

        guard history.count >= sessionsAtWeight else { return false }

        // Check if all recent sessions used the same weight
        let allSameWeight = history.allSatisfy { entry in
            abs(entry.bestSetWeightKg - currentWeight) < 1.0
        }

        // Check if user hit target reps in all sessions
        let allHitTargetReps = history.allSatisfy { entry in
            entry.bestSetReps >= 10 // Assume 10 is good performance
        }

        return allSameWeight && allHitTargetReps
    }

    // MARK: - Private Helpers

    private func calculateSuggestedWeightAndReps(
        lastPerformance: ExerciseHistory?,
        template: WorkoutPlan.ExerciseTemplate,
        strategy: WorkoutPlan.ProgressionStrategy
    ) -> (weight: Double, reps: Int) {
        guard let last = lastPerformance else {
            // No history - use template defaults with 0 weight (user fills in)
            return (0, template.defaultReps)
        }

        // Apply progression strategy
        switch strategy.type {
        case .linearProgression:
            // Add increment to last weight
            let newWeight = last.bestSetWeightKg + strategy.weightIncrementKg
            return (newWeight, template.defaultReps)

        case .doubleProgression:
            // Check if we should increase weight
            if let trigger = strategy.repsTrigger, last.bestSetReps >= trigger {
                let newWeight = last.bestSetWeightKg + strategy.weightIncrementKg
                // Reset to lower end of rep range
                let lowerReps = parseLowerRepRange(template.repRange) ?? template.defaultReps
                return (newWeight, lowerReps)
            } else {
                // Keep weight, try for more reps
                return (last.bestSetWeightKg, template.defaultReps)
            }

        case .periodized:
            // Use last weight and default reps
            return (last.bestSetWeightKg, template.defaultReps)
        }
    }

    private func parseLowerRepRange(_ repRange: String?) -> Int? {
        guard let range = repRange else { return nil }

        // Parse "8-12" format
        let components = range.split(separator: "-")
        if let first = components.first, let lower = Int(first) {
            return lower
        }
        return nil
    }
}
