//
//  WorkoutPlanDefaults.swift
//  Trai
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
            request: request,
            equipment: equipment,
            experience: experience,
            duration: request.timePerWorkout
        )

        let rationale = buildDefaultRationale(request: request, splitType: splitType)
        let guidelines = defaultGuidelines(for: experience, workoutType: request.workoutType)

        return WorkoutPlan(
            splitType: splitType,
            daysPerWeek: request.availableDays ?? 3,
            templates: templates,
            rationale: rationale,
            guidelines: guidelines,
            progressionStrategy: progressionStrategy(for: experience, workoutType: request.workoutType),
            warnings: generateWarnings(for: request)
        )
    }

    private static func generateDefaultTemplates(
        for split: SplitType,
        request: WorkoutPlanGenerationRequest,
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
            switch request.workoutType {
            case .cardio:
                return generateCardioTemplates(request: request, duration: duration)
            case .hiit:
                return generateHIITTemplates(duration: duration)
            case .flexibility:
                return generateFlexibilityTemplates(duration: duration)
            case .mixed:
                return generateMixedTemplates(
                    equipment: equipment,
                    experience: experience,
                    request: request,
                    duration: duration
                )
            case .strength:
                return generateFullBodyTemplates(equipment: equipment, experience: experience, duration: duration)
            }
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
        if splitType == .custom && request.workoutType != .strength {
            parts.append("I've designed a custom \(request.workoutType.displayName.lowercased()) plan.")
        } else {
            parts.append("I've designed a \(splitType.displayName) program.")
        }

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

    private static func defaultGuidelines(
        for experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        workoutType: WorkoutPlanGenerationRequest.WorkoutType
    ) -> [String] {
        switch workoutType {
        case .cardio:
            return [
                "Start each session with 5-10 minutes of easy movement to warm up",
                "Keep most sessions conversational and easy enough to recover from",
                "Increase weekly volume gradually instead of making big jumps",
                "Use one harder interval day at most until recovery feels consistent"
            ]
        case .hiit:
            return [
                "Warm up thoroughly before each interval session",
                "Keep work intervals sharp and stop before your form breaks down",
                "Take full recovery between hard rounds so intensity stays high",
                "Balance HIIT with at least 1-2 easier recovery days each week"
            ]
        case .flexibility:
            return [
                "Move slowly and stay in pain-free ranges of motion",
                "Focus on steady breathing during mobility and stretch work",
                "Aim for consistency across the week instead of chasing intensity",
                "Treat recovery and technique as the main progression drivers"
            ]
        case .mixed, .strength:
            break
        }

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
        for experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        workoutType: WorkoutPlanGenerationRequest.WorkoutType
    ) -> ProgressionStrategy {
        switch workoutType {
        case .cardio:
            return ProgressionStrategy(
                type: .periodized,
                weightIncrementKg: 0,
                repsTrigger: nil,
                description: "Progress by gradually adding time, distance, or pace while keeping easy days easy"
            )
        case .hiit:
            return ProgressionStrategy(
                type: .periodized,
                weightIncrementKg: 0,
                repsTrigger: nil,
                description: "Progress by adding rounds, sharpening work intervals, or reducing rest only when recovery stays solid"
            )
        case .flexibility:
            return ProgressionStrategy(
                type: .periodized,
                weightIncrementKg: 0,
                repsTrigger: nil,
                description: "Progress by improving control, range of motion, and total hold time before increasing difficulty"
            )
        case .mixed, .strength:
            break
        }

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

    private static func generateCardioTemplates(
        request: WorkoutPlanGenerationRequest,
        duration: Int
    ) -> [WorkoutTemplate] {
        let preferred = request.cardioTypes?.filter { $0 != .anyCardio } ?? []
        let primary = preferred.first ?? .running
        let secondary = preferred.dropFirst().first ?? .cycling
        let days = max(request.availableDays ?? 3, 2)

        var templates: [WorkoutTemplate] = [
            WorkoutTemplate(
                name: "\(primary.displayName) Endurance",
                sessionType: primary == .climbing ? .climbing : .cardio,
                focusAreas: [primary.displayName, "Endurance"],
                targetMuscleGroups: [primary.displayName.lowercased(), "cardio"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Easy Warm-Up", muscleGroup: "cardio", defaultSets: 1, defaultReps: 10, notes: "10 minutes easy", order: 0),
                    ExerciseTemplate(exerciseName: "\(primary.displayName) Base Work", muscleGroup: primary.displayName.lowercased(), defaultSets: 1, defaultReps: max(duration - 15, 20), notes: "Steady conversational pace", order: 1),
                    ExerciseTemplate(exerciseName: "Cool Down", muscleGroup: "cardio", defaultSets: 1, defaultReps: 5, notes: "5 minutes easy", order: 2)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Intervals",
                sessionType: .hiit,
                focusAreas: [secondary.displayName, "Intervals"],
                targetMuscleGroups: ["conditioning", "cardio"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Warm-Up", muscleGroup: "cardio", defaultSets: 1, defaultReps: 10, notes: "Build to moderate effort", order: 0),
                    ExerciseTemplate(exerciseName: "\(secondary.displayName) Intervals", muscleGroup: secondary.displayName.lowercased(), defaultSets: 6, defaultReps: 2, notes: "2 hard minutes, 2 easy minutes", order: 1),
                    ExerciseTemplate(exerciseName: "Cool Down", muscleGroup: "cardio", defaultSets: 1, defaultReps: 5, notes: "Return to easy pace", order: 2)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            )
        ]

        if days >= 3 {
            let recoveryFocus = preferred.contains(.climbing) ? "Climbing Technique" : "Recovery Cardio"
            let recoveryTarget = preferred.contains(.climbing) ? "climbing" : "cardio"
            templates.append(
                WorkoutTemplate(
                    name: recoveryFocus,
                    sessionType: preferred.contains(.climbing) ? .climbing : .recovery,
                    focusAreas: [recoveryFocus],
                    targetMuscleGroups: [recoveryTarget, "recovery"],
                    exercises: [
                        ExerciseTemplate(exerciseName: "Skill Warm-Up", muscleGroup: recoveryTarget, defaultSets: 1, defaultReps: 10, notes: "Easy ramp-up", order: 0),
                        ExerciseTemplate(exerciseName: recoveryFocus, muscleGroup: recoveryTarget, defaultSets: 1, defaultReps: max(duration - 20, 15), notes: "Keep effort smooth and repeatable", order: 1),
                        ExerciseTemplate(exerciseName: "Mobility Finish", muscleGroup: "mobility", defaultSets: 1, defaultReps: 10, notes: "Reset hips, ankles, and upper back", order: 2)
                    ],
                    estimatedDurationMinutes: duration,
                    order: 2
                )
            )
        }

        return templates
    }

    private static func generateHIITTemplates(duration: Int) -> [WorkoutTemplate] {
        [
            WorkoutTemplate(
                name: "Power Intervals",
                sessionType: .hiit,
                focusAreas: ["Power", "Intervals"],
                targetMuscleGroups: ["hiit", "conditioning"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Dynamic Warm-Up", muscleGroup: "mobility", defaultSets: 1, defaultReps: 8, notes: "8 minutes", order: 0),
                    ExerciseTemplate(exerciseName: "Sprint Intervals", muscleGroup: "hiit", defaultSets: 8, defaultReps: 30, notes: "30 sec hard, 90 sec easy", order: 1),
                    ExerciseTemplate(exerciseName: "Cool Down Walk", muscleGroup: "cardio", defaultSets: 1, defaultReps: 8, notes: "8 minutes easy", order: 2)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Conditioning Circuit",
                sessionType: .hiit,
                focusAreas: ["Conditioning", "Circuit"],
                targetMuscleGroups: ["conditioning", "fullBody"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Jump Rope", muscleGroup: "conditioning", defaultSets: 5, defaultReps: 60, notes: "60 sec on", order: 0),
                    ExerciseTemplate(exerciseName: "Burpees", muscleGroup: "conditioning", defaultSets: 5, defaultReps: 10, order: 1),
                    ExerciseTemplate(exerciseName: "Mountain Climbers", muscleGroup: "conditioning", defaultSets: 5, defaultReps: 30, order: 2),
                    ExerciseTemplate(exerciseName: "Bodyweight Squats", muscleGroup: "legs", defaultSets: 5, defaultReps: 15, order: 3)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            )
        ]
    }

    private static func generateFlexibilityTemplates(duration: Int) -> [WorkoutTemplate] {
        [
            WorkoutTemplate(
                name: "Full-Body Mobility",
                sessionType: .mobility,
                focusAreas: ["Mobility", "Full Body"],
                targetMuscleGroups: ["mobility", "fullBody"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Cat-Cow", muscleGroup: "mobility", defaultSets: 2, defaultReps: 8, order: 0),
                    ExerciseTemplate(exerciseName: "World's Greatest Stretch", muscleGroup: "mobility", defaultSets: 2, defaultReps: 6, order: 1),
                    ExerciseTemplate(exerciseName: "90/90 Hip Flow", muscleGroup: "mobility", defaultSets: 2, defaultReps: 8, order: 2),
                    ExerciseTemplate(exerciseName: "Thoracic Rotations", muscleGroup: "mobility", defaultSets: 2, defaultReps: 8, order: 3)
                ],
                estimatedDurationMinutes: duration,
                order: 0
            ),
            WorkoutTemplate(
                name: "Recovery Flow",
                sessionType: .flexibility,
                focusAreas: ["Recovery", "Flow"],
                targetMuscleGroups: ["flexibility", "recovery"],
                exercises: [
                    ExerciseTemplate(exerciseName: "Breath-Led Warm-Up", muscleGroup: "flexibility", defaultSets: 1, defaultReps: 5, notes: "5 minutes", order: 0),
                    ExerciseTemplate(exerciseName: "Hamstring Stretch", muscleGroup: "flexibility", defaultSets: 2, defaultReps: 45, notes: "45 sec each side", order: 1),
                    ExerciseTemplate(exerciseName: "Hip Flexor Stretch", muscleGroup: "flexibility", defaultSets: 2, defaultReps: 45, notes: "45 sec each side", order: 2),
                    ExerciseTemplate(exerciseName: "Child's Pose", muscleGroup: "recovery", defaultSets: 2, defaultReps: 60, notes: "60 sec hold", order: 3)
                ],
                estimatedDurationMinutes: duration,
                order: 1
            )
        ]
    }

    private static func generateMixedTemplates(
        equipment: WorkoutPlanGenerationRequest.EquipmentAccess,
        experience: WorkoutPlanGenerationRequest.ExperienceLevel,
        request: WorkoutPlanGenerationRequest,
        duration: Int
    ) -> [WorkoutTemplate] {
        let strengthTemplates = generateFullBodyTemplates(equipment: equipment, experience: experience, duration: duration)
        let cardioTemplates = generateCardioTemplates(request: request, duration: duration)

        return [
            strengthTemplates.first.map { template in
                WorkoutTemplate(
                    id: template.id,
                    name: "Strength A",
                    sessionType: .strength,
                    focusAreas: template.targetMuscleGroups,
                    targetMuscleGroups: template.targetMuscleGroups,
                    exercises: template.exercises,
                    estimatedDurationMinutes: template.estimatedDurationMinutes,
                    order: 0,
                    notes: template.notes
                )
            },
            cardioTemplates.first.map { template in
                WorkoutTemplate(
                    id: template.id,
                    name: template.name,
                    sessionType: template.sessionType,
                    focusAreas: template.focusAreas,
                    targetMuscleGroups: template.targetMuscleGroups,
                    exercises: template.exercises,
                    estimatedDurationMinutes: template.estimatedDurationMinutes,
                    order: 1,
                    notes: template.notes
                )
            },
            strengthTemplates.dropFirst().first.map { template in
                WorkoutTemplate(
                    id: template.id,
                    name: "Strength B",
                    sessionType: .strength,
                    focusAreas: template.targetMuscleGroups,
                    targetMuscleGroups: template.targetMuscleGroups,
                    exercises: template.exercises,
                    estimatedDurationMinutes: template.estimatedDurationMinutes,
                    order: 2,
                    notes: template.notes
                )
            }
        ]
        .compactMap { $0 }
    }
}
