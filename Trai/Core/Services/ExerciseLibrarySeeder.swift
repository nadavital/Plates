//
//  ExerciseLibrarySeeder.swift
//  Trai
//

import Foundation
import SwiftData

@MainActor
enum ExerciseLibrarySeeder {
    @discardableResult
    static func ensureDefaults(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Exercise>()
        let existingExercises = (try? modelContext.fetch(descriptor)) ?? []
        var existingByName: [String: Exercise] = [:]
        for exercise in existingExercises {
            let key = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, existingByName[key] == nil else { continue }
            existingByName[key] = exercise
        }
        var insertedCount = 0
        var didMutate = false

        for (name, category, muscleGroup, equipment) in Exercise.defaultExercises {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }

            if let existing = existingByName[key] {
                if existing.equipmentName?.isEmpty ?? true, let equipment {
                    existing.equipmentName = equipment
                    didMutate = true
                }
                if existing.muscleGroup?.isEmpty ?? true, let muscleGroup {
                    existing.muscleGroup = muscleGroup
                    didMutate = true
                }
                if existing.trackingFieldsRaw.isEmpty {
                    existing.trackingFields = Exercise.defaultTrackingFields(for: existing.exerciseCategory)
                    didMutate = true
                }
                if existing.targetTagsRaw.isEmpty {
                    existing.targetTags = defaultTargetTags(category: existing.exerciseCategory, muscleGroup: existing.targetMuscleGroup)
                    didMutate = true
                }
                continue
            }

            let exercise = Exercise(name: name, category: category, muscleGroup: muscleGroup)
            exercise.equipmentName = equipment
            exercise.isCustom = false
            exercise.trackingFields = Exercise.defaultTrackingFields(for: exercise.exerciseCategory)
            exercise.targetTags = defaultTargetTags(category: exercise.exerciseCategory, muscleGroup: exercise.targetMuscleGroup)
            modelContext.insert(exercise)
            existingByName[key] = exercise
            insertedCount += 1
            didMutate = true
        }

        if didMutate {
            try? modelContext.save()
        }

        return insertedCount
    }

    private static func defaultTargetTags(
        category: Exercise.Category,
        muscleGroup: Exercise.MuscleGroup?
    ) -> [String] {
        if category == .strength, let muscleGroup {
            return [muscleGroup.displayName]
        }
        return Exercise.defaultTargetTags(for: category)
    }
}
