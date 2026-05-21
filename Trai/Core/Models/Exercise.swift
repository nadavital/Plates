import Foundation
import SwiftData

/// Represents an exercise type in the user's exercise library
@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""

    /// Category: "strength", "cardio", "conditioning", "mobility", "skill", "sportPractice", "recovery", "flexibility", or "custom"
    var category: String = "strength"

    /// Target muscle group (for strength exercises)
    var muscleGroup: String?

    /// Secondary muscle groups worked (comma-separated for CloudKit compatibility)
    var secondaryMuscles: String?

    /// Equipment/machine name (for exercises added via photo identification)
    var equipmentName: String?

    /// User notes about the exercise
    var notes: String?

    /// Whether this is a custom exercise created by the user
    var isCustom: Bool = false

    /// Comma-separated targeting tags. Strength tags usually mirror muscle groups;
    /// other categories use intent tags like endurance, zone2, skill, or recovery.
    var targetTagsRaw: String = ""

    /// Comma-separated tracking fields that decide which live-workout inputs this exercise shows.
    var trackingFieldsRaw: String = ""

    var createdAt: Date = Date()

    /// Related workout sessions
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.exercise)
    var sessions: [WorkoutSession]?

    init() {}

    init(name: String, category: String, muscleGroup: String? = nil) {
        self.name = name
        self.category = category
        self.muscleGroup = muscleGroup
    }

    /// Convenience initializer with enum types
    convenience init(name: String, category: Category, muscleGroup: MuscleGroup? = nil) {
        self.init(name: name, category: category.rawValue, muscleGroup: muscleGroup?.rawValue)
    }
}

// MARK: - Category Helper

extension Exercise {
    enum Category: String, CaseIterable, Identifiable {
        case strength = "strength"
        case cardio = "cardio"
        case conditioning = "conditioning"
        case mobility = "mobility"
        case skill = "skill"
        case sportPractice = "sportPractice"
        case recovery = "recovery"
        case flexibility = "flexibility"
        case custom = "custom"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: "Strength"
            case .cardio: "Cardio"
            case .conditioning: "Conditioning"
            case .mobility: "Mobility"
            case .skill: "Skill"
            case .sportPractice: "Practice"
            case .recovery: "Recovery"
            case .flexibility: "Flexibility"
            case .custom: "Custom"
            }
        }

        var iconName: String {
            switch self {
            case .strength: "dumbbell.fill"
            case .cardio: "figure.run"
            case .conditioning: "bolt.heart.fill"
            case .mobility: "figure.mind.and.body"
            case .skill: "figure.climbing"
            case .sportPractice: "sportscourt.fill"
            case .recovery: "heart.text.square.fill"
            case .flexibility: "figure.flexibility"
            case .custom: "slider.horizontal.3"
            }
        }

        var liveWorkoutActivityKind: WorkoutPlan.TrainingBlock.BlockKind? {
            switch self {
            case .strength:
                return .strength
            case .cardio:
                return .cardio
            case .conditioning:
                return .conditioning
            case .mobility, .flexibility:
                return .mobility
            case .skill:
                return .skill
            case .sportPractice:
                return .sportPractice
            case .recovery:
                return .recovery
            case .custom:
                return .custom
            }
        }
    }

    var exerciseCategory: Category {
        get { Category(rawValue: category) ?? .custom }
        set { category = newValue.rawValue }
    }

    enum TrackingField: String, CaseIterable, Identifiable {
        case sets
        case reps
        case weight
        case duration
        case distance
        case calories
        case notes

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sets: "Sets"
            case .reps: "Reps"
            case .weight: "Weight"
            case .duration: "Duration"
            case .distance: "Distance"
            case .calories: "Calories"
            case .notes: "Notes"
            }
        }

        var iconName: String {
            switch self {
            case .sets: "number"
            case .reps: "repeat"
            case .weight: "scalemass.fill"
            case .duration: "clock.fill"
            case .distance: "map.fill"
            case .calories: "flame.fill"
            case .notes: "note.text"
            }
        }
    }

    var trackingFields: [TrackingField] {
        get {
            let fields = trackingFieldsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap(TrackingField.init(rawValue:))
            return fields.isEmpty ? Self.defaultTrackingFields(for: exerciseCategory) : fields
        }
        set {
            trackingFieldsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    var targetTags: [String] {
        get {
            let stored = targetTagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !stored.isEmpty { return stored }
            if let targetMuscleGroup {
                return [targetMuscleGroup.displayName]
            }
            return Self.defaultTargetTags(for: exerciseCategory)
        }
        set {
            targetTagsRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }

    static func defaultTrackingFields(for category: Category) -> [TrackingField] {
        switch category {
        case .strength:
            return [.sets, .weight, .reps]
        case .cardio:
            return [.duration, .distance, .calories]
        case .conditioning:
            return [.duration, .reps, .calories, .notes]
        case .mobility, .flexibility, .recovery:
            return [.duration, .notes]
        case .skill, .sportPractice:
            return [.duration, .reps, .notes]
        case .custom:
            return [.duration, .notes]
        }
    }

    static func targetOptions(for category: Category) -> [String] {
        switch category {
        case .strength:
            return MuscleGroup.allCases.map(\.displayName)
        case .cardio:
            return ["Endurance", "Zone 2", "Speed", "Intervals", "Hills", "Recovery"]
        case .conditioning:
            return ["Work Capacity", "Power", "Intervals", "Core", "Full Body", "Explosiveness"]
        case .mobility:
            return ["Hips", "Shoulders", "Ankles", "Thoracic", "Warm-Up", "Cooldown"]
        case .skill:
            return ["Technique", "Coordination", "Grip", "Footwork", "Balance", "Practice"]
        case .sportPractice:
            return ["Technique", "Drills", "Agility", "Conditioning", "Game Pace", "Recovery"]
        case .recovery:
            return ["Easy Movement", "Breathing", "Cooldown", "Restoration", "Walking", "Mobility"]
        case .flexibility:
            return ["Hamstrings", "Hips", "Shoulders", "Back", "Cooldown", "Range of Motion"]
        case .custom:
            return ["Strength", "Endurance", "Skill", "Mobility", "Recovery", "Conditioning"]
        }
    }

    static func defaultTargetTags(for category: Category) -> [String] {
        Array(targetOptions(for: category).prefix(category == .strength ? 0 : 2))
    }
}

// MARK: - Muscle Group Helper

extension Exercise {
    enum MuscleGroup: String, CaseIterable, Identifiable {
        case chest = "chest"
        case back = "back"
        case shoulders = "shoulders"
        case biceps = "biceps"
        case triceps = "triceps"
        case legs = "legs"
        case core = "core"
        case fullBody = "fullBody"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .chest: "Chest"
            case .back: "Back"
            case .shoulders: "Shoulders"
            case .biceps: "Biceps"
            case .triceps: "Triceps"
            case .legs: "Legs"
            case .core: "Core"
            case .fullBody: "Full Body"
            }
        }

        var iconName: String {
            switch self {
            case .chest: "figure.arms.open"
            case .back: "figure.walk"
            case .shoulders: "figure.boxing"
            case .biceps: "figure.strengthtraining.functional"
            case .triceps: "figure.strengthtraining.traditional"
            case .legs: "figure.run"
            case .core: "figure.core.training"
            case .fullBody: "figure.mixed.cardio"
            }
        }
    }

    var targetMuscleGroup: MuscleGroup? {
        get {
            guard let muscleGroup else { return nil }
            return MuscleGroup(rawValue: muscleGroup)
        }
        set { muscleGroup = newValue?.rawValue }
    }

    /// Secondary muscle groups as array (parsed from comma-separated string)
    var secondaryMuscleGroups: [MuscleGroup] {
        get {
            guard let secondary = secondaryMuscles else { return [] }
            return secondary.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap { MuscleGroup(rawValue: $0) }
        }
        set {
            secondaryMuscles = newValue.isEmpty ? nil : newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Display string for secondary muscles (e.g., "Biceps, Core")
    var secondaryMusclesDisplay: String? {
        let groups = secondaryMuscleGroups
        guard !groups.isEmpty else { return nil }
        return groups.map(\.displayName).joined(separator: ", ")
    }
}

// MARK: - Default Exercises

extension Exercise {
    /// Default exercises with equipment info: (name, category, muscleGroup, equipmentName)
    static let defaultExercises: [(name: String, category: String, muscleGroup: String?, equipment: String?)] = [
        // Chest
        ("Bench Press", "strength", "chest", "Barbell / Flat Bench"),
        ("Incline Bench Press", "strength", "chest", "Barbell / Incline Bench"),
        ("Dumbbell Flyes", "strength", "chest", "Dumbbells / Flat Bench"),
        ("Push-Ups", "strength", "chest", "Bodyweight"),

        // Back
        ("Deadlift", "strength", "back", "Barbell"),
        ("Bent Over Row", "strength", "back", "Barbell"),
        ("Lat Pulldown", "strength", "back", "Lat Pulldown Machine"),
        ("Pull-Ups", "strength", "back", "Pull-Up Bar"),
        ("Rowing Machine", "strength", "back", "Cable Row Machine"),

        // Shoulders
        ("Overhead Press", "strength", "shoulders", "Barbell / Dumbbells"),
        ("Lateral Raises", "strength", "shoulders", "Dumbbells"),
        ("Front Raises", "strength", "shoulders", "Dumbbells"),

        // Arms
        ("Bicep Curls", "strength", "biceps", "Dumbbells / Barbell"),
        ("Hammer Curls", "strength", "biceps", "Dumbbells"),
        ("Tricep Pushdown", "strength", "triceps", "Cable Machine"),
        ("Skull Crushers", "strength", "triceps", "EZ Bar / Flat Bench"),

        // Legs
        ("Squat", "strength", "legs", "Barbell / Squat Rack"),
        ("Leg Press", "strength", "legs", "Leg Press Machine"),
        ("Lunges", "strength", "legs", "Dumbbells / Bodyweight"),
        ("Leg Curl", "strength", "legs", "Leg Curl Machine"),
        ("Calf Raises", "strength", "legs", "Smith Machine / Dumbbells"),

        // Core
        ("Plank", "strength", "core", "Bodyweight"),
        ("Crunches", "strength", "core", "Bodyweight"),
        ("Russian Twists", "strength", "core", "Bodyweight / Medicine Ball"),

        // Cardio
        ("Running", "cardio", nil, "Treadmill / Outdoor"),
        ("Cycling", "cardio", nil, "Stationary Bike / Outdoor"),
        ("Walking", "cardio", nil, "Treadmill / Outdoor"),
        ("Incline Walk", "cardio", nil, "Treadmill"),
        ("Swimming", "cardio", nil, "Pool"),
        ("Rowing", "cardio", nil, "Rowing Machine"),
        ("Elliptical", "cardio", nil, "Elliptical"),
        ("Stair Climber", "cardio", nil, "Stair Climber"),
        ("Jump Rope", "cardio", nil, "Jump Rope"),
        ("Zone 2 Cardio", "cardio", nil, "Treadmill / Bike / Outdoor"),

        // Conditioning
        ("Intervals", "conditioning", nil, "Treadmill / Bike / Rower"),
        ("Sled Push", "conditioning", nil, "Sled"),
        ("Battle Ropes", "conditioning", nil, "Battle Ropes"),
        ("Kettlebell Swings", "conditioning", nil, "Kettlebell"),
        ("Circuit Training", "conditioning", nil, "Various"),

        // Skill / sport practice
        ("Bouldering", "skill", nil, "Climbing Wall"),
        ("Top Rope Climbing", "skill", nil, "Climbing Wall"),
        ("Technique Practice", "skill", nil, "Sport-Specific"),

        // Mobility / recovery
        ("Hip Mobility Flow", "mobility", nil, "Mat / Bodyweight"),
        ("Shoulder Mobility Flow", "mobility", nil, "Band / Bodyweight"),
        ("Ankle Mobility", "mobility", nil, "Bodyweight"),
        ("Breathwork", "recovery", nil, "Mat"),
        ("Easy Recovery Walk", "recovery", nil, "Outdoor / Treadmill"),

        // Flexibility
        ("Yoga", "flexibility", nil, "Yoga Mat"),
        ("Stretching", "flexibility", nil, "Mat / Bodyweight"),
        ("Foam Rolling", "flexibility", nil, "Foam Roller"),
    ]

    /// Infers equipment name from exercise name keywords
    /// Only returns a match when the exercise name clearly indicates specific equipment
    static func inferEquipment(from exerciseName: String) -> String? {
        let lowercased = exerciseName.lowercased()

        // Check for machine keywords FIRST (before bodyweight checks)
        // This prevents "Machine Crunch" from being tagged as "Bodyweight"
        let isMachineExercise = lowercased.contains("machine") ||
                                lowercased.contains("cable") ||
                                lowercased.contains("smith") ||
                                lowercased.contains("seated") ||
                                lowercased.contains("assisted")

        // Explicit machine types
        if lowercased.contains("cable") { return "Cable Machine" }
        if lowercased.contains("machine") { return "Machine" }
        if lowercased.contains("smith") { return "Smith Machine" }
        if lowercased.contains("pulldown") || lowercased.contains("pull-down") { return "Lat Pulldown Machine" }
        if lowercased.contains("leg press") { return "Leg Press Machine" }
        if lowercased.contains("leg curl") { return "Leg Curl Machine" }
        if lowercased.contains("leg extension") { return "Leg Extension Machine" }
        if lowercased.contains("chest press") && !lowercased.contains("dumbbell") { return "Chest Press Machine" }
        if lowercased.contains("pec deck") || lowercased.contains("pec fly") { return "Pec Deck Machine" }
        if lowercased.contains("hack squat") { return "Hack Squat Machine" }
        if lowercased.contains("seated row") { return "Seated Row Machine" }

        // Equipment types
        if lowercased.contains("dumbbell") { return "Dumbbells" }
        if lowercased.contains("barbell") { return "Barbell" }
        if lowercased.contains("kettlebell") { return "Kettlebell" }
        if lowercased.contains("band") { return "Resistance Bands" }
        if lowercased.contains("ez bar") || lowercased.contains("ez-bar") { return "EZ Bar" }

        // Bodyweight exercises - only if NOT a machine exercise
        if !isMachineExercise {
            if lowercased.contains("push-up") || lowercased.contains("pushup") { return "Bodyweight" }
            if lowercased.contains("pull-up") || lowercased.contains("pullup") { return "Pull-Up Bar" }
            if lowercased.contains("chin-up") || lowercased.contains("chinup") { return "Pull-Up Bar" }
            if lowercased.contains("dip") { return "Dip Station / Parallel Bars" }
            if lowercased.contains("plank") || lowercased.contains("crunch") { return "Bodyweight" }
            if lowercased.contains("lunge") { return "Bodyweight / Dumbbells" }
            if lowercased.contains("squat") && !lowercased.contains("hack") {
                return "Barbell / Squat Rack"
            }
        }

        return nil
    }

    /// Gets the equipment name, either stored or inferred
    var displayEquipment: String? {
        if let equipment = equipmentName, !equipment.isEmpty {
            return equipment
        }
        return Exercise.inferEquipment(from: name)
    }
}
