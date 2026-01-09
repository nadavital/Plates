//
//  WorkoutPlanDefaults.swift
//  Plates
//
//  Default workout plan templates when AI generation is unavailable
//

import Foundation

// MARK: - Default Plan Generator

extension WorkoutPlan {
    /// Creates a default plan when AI is unavailable
    static func createDefault(from request: WorkoutPlanGenerationRequest) -> WorkoutPlan {
        let splitType = request.recommendedSplit
        let equipment = request.equipmentAccess ?? .fullGym
        let experience = request.experienceLevel ?? .intermediate

        let templates = generateDefaultTemplates(
            for: splitType,
            equipment: equipment,
            experience: experience,
            duration: request.timePerWorkout
        )

        let rationale = buildDefaultRationale(request: request, splitType: splitType)
        let guidelines = defaultGuidelines(for: experience)

        return WorkoutPlan(
            splitType: splitType,
            daysPerWeek: request.availableDays ?? 3,
            templates: templates,
            rationale: rationale,
            guidelines: guidelines,
            progressionStrategy: progressionStrategy(for: experience),
            warnings: generateWarnings(for: request)
        )
    }

    private static func generateDefaultTemplates(
        for split: SplitType,
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        duration: Int
    ) -> [WorkoutTemplate] {
        switch split {
        case .pushPullLegs:
            return generatePPLTemplates(equipment: equipment, experience: experience, duration: duration)
        case .upperLower:
            return generateUpperLowerTemplates(equipment: equipment, experience: experience, duration: duration)
        case .fullBody:
            return generateFullBodyTemplates(equipment: equipment, experience: experience, duration: duration)
        case .bodyPartSplit:
            return generateBodyPartTemplates(equipment: equipment, experience: experience, duration: duration)
        case .custom:
            return generateFullBodyTemplates(equipment: equipment, experience: experience, duration: duration)
        }
    }

    // MARK: - Push/Pull/Legs Templates

    private static func generatePPLTemplates(
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        duration: Int
    ) -> [WorkoutTemplate] {
        let sets = experience == .beginner ? 3 : 4

        return [
            WorkoutTemplate(
                name: "Push Day",
                targetMuscleGroups: ["chest", "shoulders", "triceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Overhead Press", muscleGroup: "shoulders", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 1),
                    ExerciseTemplate(exerciseName: "Incline Dumbbell Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Lateral Raises", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 3),
                    ExerciseTemplate(exerciseName: "Tricep Pushdown", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Pull Day",
                targetMuscleGroups: ["back", "biceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Deadlift", muscleGroup: "back", defaultSets: sets, defaultReps: 5, repRange: "3-6", order: 0),
                    ExerciseTemplate(exerciseName: "Lat Pulldown", muscleGroup: "back", defaultSets: sets, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Bent Over Row", muscleGroup: "back", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Face Pulls", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 15, repRange: "12-15", order: 3),
                    ExerciseTemplate(exerciseName: "Bicep Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 12, repRange: "10-12", order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            ),
            WorkoutTemplate(
                name: "Leg Day",
                targetMuscleGroups: ["quads", "hamstrings", "glutes", "calves"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Squat", muscleGroup: "quads", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Romanian Deadlift", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Leg Press", muscleGroup: "quads", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 2),
                    ExerciseTemplate(exerciseName: "Leg Curl", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 3),
                    ExerciseTemplate(exerciseName: "Calf Raises", muscleGroup: "calves", defaultSets: 4, defaultReps: 15, repRange: "12-20", order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 2
            )
        ]
    }

    // MARK: - Upper/Lower Templates

    private static func generateUpperLowerTemplates(
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        duration: Int
    ) -> [WorkoutTemplate] {
        let sets = experience == .beginner ? 3 : 4

        return [
            WorkoutTemplate(
                name: "Upper Body A",
                targetMuscleGroups: ["chest", "back", "shoulders", "biceps", "triceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Bent Over Row", muscleGroup: "back", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 1),
                    ExerciseTemplate(exerciseName: "Overhead Press", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Lat Pulldown", muscleGroup: "back", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 3),
                    ExerciseTemplate(exerciseName: "Bicep Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 12, order: 4),
                    ExerciseTemplate(exerciseName: "Tricep Pushdown", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, order: 5)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Lower Body A",
                targetMuscleGroups: ["quads", "hamstrings", "glutes", "calves", "core"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Squat", muscleGroup: "quads", defaultSets: sets, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Romanian Deadlift", muscleGroup: "hamstrings", defaultSets: sets, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Leg Press", muscleGroup: "quads", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 2),
                    ExerciseTemplate(exerciseName: "Leg Curl", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 12, order: 3),
                    ExerciseTemplate(exerciseName: "Calf Raises", muscleGroup: "calves", defaultSets: 4, defaultReps: 15, order: 4),
                    ExerciseTemplate(exerciseName: "Plank", muscleGroup: "core", defaultSets: 3, defaultReps: 60, notes: "Hold for 60 seconds", order: 5)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            )
        ]
    }

    // MARK: - Full Body Templates

    private static func generateFullBodyTemplates(
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        duration: Int
    ) -> [WorkoutTemplate] {
        return [
            WorkoutTemplate(
                name: "Full Body A",
                targetMuscleGroups: ["chest", "back", "quads", "shoulders", "core"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Squat", muscleGroup: "quads", defaultSets: 3, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 8, repRange: "6-10", order: 1),
                    ExerciseTemplate(exerciseName: "Bent Over Row", muscleGroup: "back", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Overhead Press", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 3),
                    ExerciseTemplate(exerciseName: "Plank", muscleGroup: "core", defaultSets: 3, defaultReps: 45, notes: "Hold for 45 seconds", order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Full Body B",
                targetMuscleGroups: ["hamstrings", "back", "chest", "biceps", "triceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Deadlift", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 5, repRange: "3-6", order: 0),
                    ExerciseTemplate(exerciseName: "Incline Dumbbell Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Lat Pulldown", muscleGroup: "back", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Bicep Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 12, order: 3),
                    ExerciseTemplate(exerciseName: "Tricep Pushdown", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            )
        ]
    }

    // MARK: - Body Part Split Templates

    private static func generateBodyPartTemplates(
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        duration: Int
    ) -> [WorkoutTemplate] {
        return [
            WorkoutTemplate(
                name: "Chest & Triceps",
                targetMuscleGroups: ["chest", "triceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: 4, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Incline Dumbbell Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Cable Flyes", muscleGroup: "chest", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 2),
                    ExerciseTemplate(exerciseName: "Tricep Pushdown", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, order: 3),
                    ExerciseTemplate(exerciseName: "Skull Crushers", muscleGroup: "triceps", defaultSets: 3, defaultReps: 10, order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Back & Biceps",
                targetMuscleGroups: ["back", "biceps"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Deadlift", muscleGroup: "back", defaultSets: 4, defaultReps: 5, repRange: "3-6", order: 0),
                    ExerciseTemplate(exerciseName: "Lat Pulldown", muscleGroup: "back", defaultSets: 4, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Bent Over Row", muscleGroup: "back", defaultSets: 3, defaultReps: 10, repRange: "8-12", order: 2),
                    ExerciseTemplate(exerciseName: "Bicep Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 12, order: 3),
                    ExerciseTemplate(exerciseName: "Hammer Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 10, order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            ),
            WorkoutTemplate(
                name: "Shoulders & Abs",
                targetMuscleGroups: ["shoulders", "core"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Overhead Press", muscleGroup: "shoulders", defaultSets: 4, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Lateral Raises", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 1),
                    ExerciseTemplate(exerciseName: "Face Pulls", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 15, order: 2),
                    ExerciseTemplate(exerciseName: "Plank", muscleGroup: "core", defaultSets: 3, defaultReps: 60, notes: "Hold for 60 seconds", order: 3),
                    ExerciseTemplate(exerciseName: "Russian Twists", muscleGroup: "core", defaultSets: 3, defaultReps: 20, order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 2
            ),
            WorkoutTemplate(
                name: "Legs",
                targetMuscleGroups: ["quads", "hamstrings", "glutes", "calves"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Squat", muscleGroup: "quads", defaultSets: 4, defaultReps: 8, repRange: "6-10", order: 0),
                    ExerciseTemplate(exerciseName: "Romanian Deadlift", muscleGroup: "hamstrings", defaultSets: 4, defaultReps: 10, repRange: "8-12", order: 1),
                    ExerciseTemplate(exerciseName: "Leg Press", muscleGroup: "quads", defaultSets: 3, defaultReps: 12, repRange: "10-15", order: 2),
                    ExerciseTemplate(exerciseName: "Leg Curl", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 12, order: 3),
                    ExerciseTemplate(exerciseName: "Calf Raises", muscleGroup: "calves", defaultSets: 4, defaultReps: 15, order: 4)
                ],
                estimatedDurationMinutes: duration,
                order: 3
            )
        ]
    }

    // MARK: - Helper Methods

    private static func buildDefaultRationale(
        request: WorkoutPlanGenerationRequest,
        splitType: SplitType
    ) -> String {
        var parts: [String] = []

        let daysText = request.availableDays.map { "\($0) days per week" } ?? "flexible"
        let experienceText = request.experienceLevel?.displayName.lowercased() ?? "your"
        parts.append("Based on your \(daysText) availability and \(experienceText) experience level,")
        parts.append("I've designed a \(splitType.displayName) program.")

        switch request.goal {
        case .buildMuscle:
            parts.append("This split is optimized for muscle growth with progressive overload.")
        case .loseWeight, .loseFat:
            parts.append("Combined with your nutrition plan, this will help preserve muscle while losing fat.")
        case .performance:
            parts.append("This structure supports athletic performance with adequate recovery.")
        default:
            parts.append("This balanced approach will help you build strength and improve fitness.")
        }

        return parts.joined(separator: " ")
    }

    private static func defaultGuidelines(for experience: WorkoutPlanGenerationRequest.ExperienceLevel) -> [String] {
        var guidelines = [
            "Warm up for 5-10 minutes before each workout",
            "Rest 2-3 minutes between heavy compound sets",
            "Rest 60-90 seconds between isolation exercises"
        ]

        switch experience {
        case .beginner:
            guidelines.append("Focus on learning proper form before adding weight")
            guidelines.append("Start with lighter weights to build technique")
        case .intermediate:
            guidelines.append("Track your weights and aim for progressive overload each week")
            guidelines.append("Consider deload weeks every 4-6 weeks")
        case .advanced:
            guidelines.append("Periodize your training with varying intensity phases")
            guidelines.append("Listen to your body and adjust volume as needed")
        }

        return guidelines
    }

    private static func progressionStrategy(
        for experience: WorkoutPlanGenerationRequest.ExperienceLevel
    ) -> ProgressionStrategy {
        switch experience {
        case .beginner:
            return ProgressionStrategy(
                type: .linearProgression,
                weightIncrementKg: 2.5,
                repsTrigger: nil,
                description: "Add weight each session while maintaining good form"
            )
        case .intermediate:
            return ProgressionStrategy(
                type: .doubleProgression,
                weightIncrementKg: 2.5,
                repsTrigger: 12,
                description: "Increase reps until you hit the top of the range, then add weight"
            )
        case .advanced:
            return ProgressionStrategy(
                type: .periodized,
                weightIncrementKg: 2.5,
                repsTrigger: nil,
                description: "Cycle through strength and hypertrophy phases for continued progress"
            )
        }
    }

    private static func generateWarnings(for request: WorkoutPlanGenerationRequest) -> [String]? {
        var warnings: [String] = []

        if let injuries = request.injuries, !injuries.isEmpty {
            warnings.append("Please consult a healthcare provider about exercises that may affect your injury.")
        }

        if let days = request.availableDays, days >= 6, request.experienceLevel == .beginner {
            warnings.append("Training 6+ days as a beginner may lead to overtraining. Consider starting with fewer days.")
        }

        return warnings.isEmpty ? nil : warnings
    }
}
