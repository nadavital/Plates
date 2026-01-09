//
//  WorkoutPlan.swift
//  Plates
//
//  Represents an AI-generated workout plan with splits and templates
//  This is a Codable struct (not SwiftData) since it's generated dynamically
//

import Foundation

/// Represents a user's workout plan with split structure and exercise templates
struct WorkoutPlan: Codable, Equatable {
    let splitType: SplitType
    let daysPerWeek: Int
    let templates: [WorkoutTemplate]
    let rationale: String
    let guidelines: [String]
    let progressionStrategy: ProgressionStrategy
    let warnings: [String]?

    // MARK: - Split Type

    enum SplitType: String, Codable, CaseIterable, Identifiable {
        case pushPullLegs = "pushPullLegs"
        case upperLower = "upperLower"
        case fullBody = "fullBody"
        case bodyPartSplit = "bodyPartSplit"
        case custom = "custom"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pushPullLegs: "Push/Pull/Legs"
            case .upperLower: "Upper/Lower"
            case .fullBody: "Full Body"
            case .bodyPartSplit: "Body Part Split"
            case .custom: "Custom Split"
            }
        }

        var description: String {
            switch self {
            case .pushPullLegs: "Train push muscles, pull muscles, and legs on separate days"
            case .upperLower: "Alternate between upper and lower body workouts"
            case .fullBody: "Train your entire body each session"
            case .bodyPartSplit: "Dedicate each day to specific muscle groups"
            case .custom: "A personalized split based on your preferences"
            }
        }

        var recommendedDaysPerWeek: ClosedRange<Int> {
            switch self {
            case .pushPullLegs: 3...6
            case .upperLower: 3...4
            case .fullBody: 2...4
            case .bodyPartSplit: 4...6
            case .custom: 2...6
            }
        }

        var iconName: String {
            switch self {
            case .pushPullLegs: "arrow.left.arrow.right"
            case .upperLower: "arrow.up.arrow.down"
            case .fullBody: "figure.walk"
            case .bodyPartSplit: "rectangle.split.3x1"
            case .custom: "slider.horizontal.3"
            }
        }
    }

    // MARK: - Workout Template

    struct WorkoutTemplate: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let targetMuscleGroups: [String]
        let exercises: [ExerciseTemplate]
        let estimatedDurationMinutes: Int
        let order: Int
        let notes: String?

        init(
            id: UUID = UUID(),
            name: String,
            targetMuscleGroups: [String],
            exercises: [ExerciseTemplate],
            estimatedDurationMinutes: Int,
            order: Int,
            notes: String? = nil
        ) {
            self.id = id
            self.name = name
            self.targetMuscleGroups = targetMuscleGroups
            self.exercises = exercises
            self.estimatedDurationMinutes = estimatedDurationMinutes
            self.order = order
            self.notes = notes
        }

        var exerciseCount: Int { exercises.count }

        var muscleGroupsDisplay: String {
            targetMuscleGroups
                .map { $0.capitalized }
                .joined(separator: " • ")
        }
    }

    // MARK: - Exercise Template

    struct ExerciseTemplate: Codable, Equatable, Identifiable {
        let id: UUID
        let exerciseName: String
        let muscleGroup: String
        let defaultSets: Int
        let defaultReps: Int
        let repRange: String?
        let restSeconds: Int?
        let notes: String?
        let order: Int

        init(
            id: UUID = UUID(),
            exerciseName: String,
            muscleGroup: String,
            defaultSets: Int,
            defaultReps: Int,
            repRange: String? = nil,
            restSeconds: Int? = nil,
            notes: String? = nil,
            order: Int
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.muscleGroup = muscleGroup
            self.defaultSets = defaultSets
            self.defaultReps = defaultReps
            self.repRange = repRange
            self.restSeconds = restSeconds
            self.notes = notes
            self.order = order
        }

        var setsRepsDisplay: String {
            if let range = repRange {
                return "\(defaultSets)×\(range)"
            }
            return "\(defaultSets)×\(defaultReps)"
        }
    }

    // MARK: - Progression Strategy

    struct ProgressionStrategy: Codable, Equatable {
        let type: ProgressionType
        let weightIncrementKg: Double
        let repsTrigger: Int?
        let description: String

        enum ProgressionType: String, Codable {
            case linearProgression = "linearProgression"
            case doubleProgression = "doubleProgression"
            case periodized = "periodized"

            var displayName: String {
                switch self {
                case .linearProgression: "Linear Progression"
                case .doubleProgression: "Double Progression"
                case .periodized: "Periodized"
                }
            }
        }

        static let defaultStrategy = ProgressionStrategy(
            type: .doubleProgression,
            weightIncrementKg: 2.5,
            repsTrigger: 12,
            description: "Increase reps until you hit the target, then add weight and reset reps"
        )
    }

    // MARK: - JSON Serialization

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func fromJSON(_ json: String) -> WorkoutPlan? {
        guard let data = json.data(using: .utf8),
              let plan = try? JSONDecoder().decode(WorkoutPlan.self, from: data) else {
            return nil
        }
        return plan
    }

    // MARK: - Placeholder

    static let placeholder = WorkoutPlan(
        splitType: .pushPullLegs,
        daysPerWeek: 3,
        templates: [],
        rationale: "",
        guidelines: [],
        progressionStrategy: .defaultStrategy,
        warnings: nil
    )
}

// MARK: - Plan Generation Request

struct WorkoutPlanGenerationRequest {
    let name: String
    let age: Int
    let gender: UserProfile.Gender
    let goal: UserProfile.GoalType
    let activityLevel: UserProfile.ActivityLevel

    // Core preferences
    let workoutType: WorkoutType              // Primary/derived type
    let selectedWorkoutTypes: [WorkoutType]?  // All types user explicitly selected
    let experienceLevel: ExperienceLevel?
    let equipmentAccess: EquipmentAccess?
    let availableDays: Int?  // nil = flexible/as available
    let timePerWorkout: Int

    // Conditional/optional preferences
    let preferredSplit: PreferredSplit?
    let cardioTypes: [CardioType]?

    // Custom/Other text inputs
    let customWorkoutType: String?
    let customExperience: String?
    let customEquipment: String?
    let customCardioType: String?

    // Open-ended from conversation
    let specificGoals: [String]?      // "I want to do a pull-up", "visible abs"
    let weakPoints: [String]?         // "shoulders are lagging", "weak core"
    let injuries: String?             // "bad knee", "lower back issues"
    let preferences: String?          // "I love deadlifts", "hate burpees"

    /// Whether cardio should be included in the plan
    var includesCardio: Bool {
        if let types = selectedWorkoutTypes {
            return types.contains(.cardio) || types.contains(.mixed) || types.contains(.hiit)
        }
        return workoutType == .cardio || workoutType == .mixed || workoutType == .hiit
    }

    // MARK: - Workout Type

    enum WorkoutType: String, CaseIterable, Identifiable, Codable {
        case strength = "strength"
        case cardio = "cardio"
        case hiit = "hiit"
        case flexibility = "flexibility"
        case mixed = "mixed"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: "Strength Training"
            case .cardio: "Cardio & Endurance"
            case .hiit: "HIIT & Conditioning"
            case .flexibility: "Yoga & Flexibility"
            case .mixed: "Mixed / Varied"
            }
        }

        var description: String {
            switch self {
            case .strength: "Build muscle and get stronger with weights"
            case .cardio: "Improve endurance with running, cycling, etc."
            case .hiit: "High-intensity intervals for fat loss and conditioning"
            case .flexibility: "Improve mobility and reduce stress"
            case .mixed: "A balanced mix of different training styles"
            }
        }

        var iconName: String {
            switch self {
            case .strength: "dumbbell.fill"
            case .cardio: "figure.run"
            case .hiit: "bolt.fill"
            case .flexibility: "figure.yoga"
            case .mixed: "square.grid.2x2"
            }
        }

        var shouldAskAboutSplit: Bool {
            self == .strength || self == .mixed
        }

        var shouldAskAboutCardioType: Bool {
            self == .cardio || self == .mixed
        }
    }

    // MARK: - Preferred Split

    enum PreferredSplit: String, CaseIterable, Identifiable, Codable {
        case pushPullLegs = "pushPullLegs"
        case upperLower = "upperLower"
        case fullBody = "fullBody"
        case broSplit = "broSplit"
        case letTraiDecide = "letTraiDecide"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pushPullLegs: "Push/Pull/Legs"
            case .upperLower: "Upper/Lower"
            case .fullBody: "Full Body"
            case .broSplit: "Body Part Split"
            case .letTraiDecide: "Let Trai Decide"
            }
        }

        var description: String {
            switch self {
            case .pushPullLegs: "Push muscles one day, pull the next, then legs"
            case .upperLower: "Alternate between upper and lower body"
            case .fullBody: "Train your whole body each session"
            case .broSplit: "One muscle group per day (chest day, back day, etc.)"
            case .letTraiDecide: "Trai will pick the best split for you"
            }
        }

        var iconName: String {
            switch self {
            case .pushPullLegs: "arrow.left.arrow.right"
            case .upperLower: "arrow.up.arrow.down"
            case .fullBody: "figure.strengthtraining.traditional"
            case .broSplit: "rectangle.split.3x1"
            case .letTraiDecide: "sparkles"
            }
        }
    }

    // MARK: - Cardio Type

    enum CardioType: String, CaseIterable, Identifiable, Codable {
        case running = "running"
        case cycling = "cycling"
        case swimming = "swimming"
        case rowing = "rowing"
        case walking = "walking"
        case stairClimber = "stairClimber"
        case elliptical = "elliptical"
        case jumpRope = "jumpRope"
        case anyCardio = "anyCardio"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .running: "Running"
            case .cycling: "Cycling"
            case .swimming: "Swimming"
            case .rowing: "Rowing"
            case .walking: "Walking"
            case .stairClimber: "Stair Climber"
            case .elliptical: "Elliptical"
            case .jumpRope: "Jump Rope"
            case .anyCardio: "Any / No Preference"
            }
        }

        var iconName: String {
            switch self {
            case .running: "figure.run"
            case .cycling: "figure.outdoor.cycle"
            case .swimming: "figure.pool.swim"
            case .rowing: "figure.rower"
            case .walking: "figure.walk"
            case .stairClimber: "figure.stair.stepper"
            case .elliptical: "figure.elliptical"
            case .jumpRope: "figure.jumprope"
            case .anyCardio: "heart.fill"
            }
        }
    }

    enum EquipmentAccess: String, CaseIterable, Identifiable {
        case fullGym = "fullGym"
        case homeAdvanced = "homeAdvanced"
        case homeBasic = "homeBasic"
        case bodyweightOnly = "bodyweightOnly"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fullGym: "Full Gym"
            case .homeAdvanced: "Home Gym (Advanced)"
            case .homeBasic: "Home Gym (Basic)"
            case .bodyweightOnly: "Bodyweight Only"
            }
        }

        var description: String {
            switch self {
            case .fullGym: "Access to all machines, barbells, dumbbells, cables"
            case .homeAdvanced: "Barbell, dumbbells, bench, pull-up bar"
            case .homeBasic: "Dumbbells and resistance bands"
            case .bodyweightOnly: "No equipment needed"
            }
        }

        var iconName: String {
            switch self {
            case .fullGym: "building.2"
            case .homeAdvanced: "dumbbell.fill"
            case .homeBasic: "figure.strengthtraining.functional"
            case .bodyweightOnly: "figure.walk"
            }
        }
    }

    enum ExperienceLevel: String, CaseIterable, Identifiable {
        case beginner = "beginner"
        case intermediate = "intermediate"
        case advanced = "advanced"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .beginner: "Beginner"
            case .intermediate: "Intermediate"
            case .advanced: "Advanced"
            }
        }

        var description: String {
            switch self {
            case .beginner: "New to strength training or less than 6 months experience"
            case .intermediate: "6 months to 2 years of consistent training"
            case .advanced: "2+ years of serious training with good technique"
            }
        }

        var iconName: String {
            switch self {
            case .beginner: "1.circle.fill"
            case .intermediate: "2.circle.fill"
            case .advanced: "3.circle.fill"
            }
        }
    }

    /// Recommend a split type based on preferences, available days and experience
    var recommendedSplit: WorkoutPlan.SplitType {
        // If user chose a specific split, use it
        if let preferred = preferredSplit, preferred != .letTraiDecide {
            switch preferred {
            case .pushPullLegs: return .pushPullLegs
            case .upperLower: return .upperLower
            case .fullBody: return .fullBody
            case .broSplit: return .bodyPartSplit
            case .letTraiDecide: break
            }
        }

        // Otherwise recommend based on days and experience
        switch availableDays {
        case 2:
            return .fullBody
        case 3:
            return experienceLevel == .beginner ? .fullBody : .pushPullLegs
        case 4:
            return .upperLower
        case 5, 6:
            return experienceLevel == .advanced ? .bodyPartSplit : .pushPullLegs
        default:
            return .fullBody
        }
    }
}

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
