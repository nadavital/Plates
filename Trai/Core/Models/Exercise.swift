import Foundation
import SwiftData

/// Represents an exercise type in the user's exercise library
@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""

    /// Category: "strength", "cardio", or "flexibility"
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
        case flexibility = "flexibility"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: "Strength"
            case .cardio: "Cardio"
            case .flexibility: "Flexibility"
            }
        }

        var iconName: String {
            switch self {
            case .strength: "dumbbell.fill"
            case .cardio: "heart.fill"
            case .flexibility: "figure.flexibility"
            }
        }
    }

    var exerciseCategory: Category {
        get { Category(rawValue: category) ?? .strength }
        set { category = newValue.rawValue }
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
        ("Swimming", "cardio", nil, "Pool"),
        ("Rowing", "cardio", nil, "Rowing Machine"),
        ("Jump Rope", "cardio", nil, "Jump Rope"),
        ("HIIT", "cardio", nil, "Various"),

        // Flexibility
        ("Yoga", "flexibility", nil, "Yoga Mat"),
        ("Stretching", "flexibility", nil, "Mat / Bodyweight"),
        ("Foam Rolling", "flexibility", nil, "Foam Roller"),
    ]

    /// Infers equipment name from exercise name keywords
    static func inferEquipment(from exerciseName: String) -> String? {
        let lowercased = exerciseName.lowercased()

        // Check for explicit machine keywords
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

        // Bodyweight exercises
        if lowercased.contains("push-up") || lowercased.contains("pushup") { return "Bodyweight" }
        if lowercased.contains("pull-up") || lowercased.contains("pullup") { return "Pull-Up Bar" }
        if lowercased.contains("chin-up") || lowercased.contains("chinup") { return "Pull-Up Bar" }
        if lowercased.contains("dip") { return "Dip Station / Parallel Bars" }
        if lowercased.contains("plank") || lowercased.contains("crunch") { return "Bodyweight" }
        if lowercased.contains("lunge") { return "Bodyweight / Dumbbells" }
        if lowercased.contains("squat") && !lowercased.contains("machine") && !lowercased.contains("hack") {
            return "Barbell / Squat Rack"
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
