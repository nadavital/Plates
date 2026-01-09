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
}

// MARK: - Default Exercises

extension Exercise {
    static let defaultExercises: [(name: String, category: String, muscleGroup: String?)] = [
        // Chest
        ("Bench Press", "strength", "chest"),
        ("Incline Bench Press", "strength", "chest"),
        ("Dumbbell Flyes", "strength", "chest"),
        ("Push-Ups", "strength", "chest"),

        // Back
        ("Deadlift", "strength", "back"),
        ("Bent Over Row", "strength", "back"),
        ("Lat Pulldown", "strength", "back"),
        ("Pull-Ups", "strength", "back"),

        // Shoulders
        ("Overhead Press", "strength", "shoulders"),
        ("Lateral Raises", "strength", "shoulders"),
        ("Front Raises", "strength", "shoulders"),

        // Arms
        ("Bicep Curls", "strength", "biceps"),
        ("Hammer Curls", "strength", "biceps"),
        ("Tricep Pushdown", "strength", "triceps"),
        ("Skull Crushers", "strength", "triceps"),

        // Legs
        ("Squat", "strength", "legs"),
        ("Leg Press", "strength", "legs"),
        ("Lunges", "strength", "legs"),
        ("Leg Curl", "strength", "legs"),
        ("Calf Raises", "strength", "legs"),

        // Core
        ("Plank", "strength", "core"),
        ("Crunches", "strength", "core"),
        ("Russian Twists", "strength", "core"),

        // Cardio
        ("Running", "cardio", nil),
        ("Cycling", "cardio", nil),
        ("Swimming", "cardio", nil),
        ("Rowing", "cardio", nil),
        ("Jump Rope", "cardio", nil),
        ("HIIT", "cardio", nil),

        // Flexibility
        ("Yoga", "flexibility", nil),
        ("Stretching", "flexibility", nil),
        ("Foam Rolling", "flexibility", nil),
    ]
}
