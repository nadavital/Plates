//
//  LiveWorkout.swift
//  Plates
//

import Foundation
import SwiftData

/// Represents an in-progress or completed workout session with detailed exercise tracking
@Model
final class LiveWorkout {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var completedAt: Date?

    /// Workout type: "strength", "cardio", "mixed"
    var workoutType: String = "strength"

    /// Target muscle groups (comma-separated for AI context)
    /// e.g., "chest,triceps,shoulders"
    var targetMuscleGroups: String = ""

    /// Notes added by user during workout
    var notes: String = ""

    /// HealthKit workout ID if merged with Apple Watch data
    var mergedHealthKitWorkoutID: String?

    /// Calories from HealthKit (if available)
    var healthKitCalories: Double?

    /// Average heart rate from HealthKit (if available)
    var healthKitAvgHeartRate: Double?

    /// Relationship to workout entries (exercises performed)
    @Relationship(deleteRule: .cascade, inverse: \LiveWorkoutEntry.workout)
    var entries: [LiveWorkoutEntry]?

    init() {}

    init(name: String, workoutType: WorkoutType, targetMuscleGroups: [MuscleGroup] = []) {
        self.name = name
        self.workoutType = workoutType.rawValue
        self.targetMuscleGroups = targetMuscleGroups.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Workout Type

extension LiveWorkout {
    enum WorkoutType: String, CaseIterable, Identifiable {
        case strength = "strength"
        case cardio = "cardio"
        case mixed = "mixed"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: "Strength"
            case .cardio: "Cardio"
            case .mixed: "Mixed"
            }
        }

        var iconName: String {
            switch self {
            case .strength: "dumbbell.fill"
            case .cardio: "heart.fill"
            case .mixed: "figure.mixed.cardio"
            }
        }
    }

    var type: WorkoutType {
        get { WorkoutType(rawValue: workoutType) ?? .strength }
        set { workoutType = newValue.rawValue }
    }
}

// MARK: - Muscle Groups

extension LiveWorkout {
    enum MuscleGroup: String, CaseIterable, Identifiable {
        case chest = "chest"
        case back = "back"
        case shoulders = "shoulders"
        case biceps = "biceps"
        case triceps = "triceps"
        case forearms = "forearms"
        case core = "core"
        case quads = "quads"
        case hamstrings = "hamstrings"
        case glutes = "glutes"
        case calves = "calves"
        case fullBody = "fullBody"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .chest: "Chest"
            case .back: "Back"
            case .shoulders: "Shoulders"
            case .biceps: "Biceps"
            case .triceps: "Triceps"
            case .forearms: "Forearms"
            case .core: "Core"
            case .quads: "Quads"
            case .hamstrings: "Hamstrings"
            case .glutes: "Glutes"
            case .calves: "Calves"
            case .fullBody: "Full Body"
            }
        }

        var iconName: String {
            switch self {
            case .chest: "figure.arms.open"
            case .back: "figure.yoga"
            case .shoulders: "figure.arms.open"
            case .biceps, .triceps, .forearms: "figure.strengthtraining.traditional"
            case .core: "figure.core.training"
            case .quads, .hamstrings, .glutes, .calves: "figure.walk"
            case .fullBody: "figure.stand"
            }
        }

        /// Common workout split categories
        static var pushMuscles: [MuscleGroup] { [.chest, .shoulders, .triceps] }
        static var pullMuscles: [MuscleGroup] { [.back, .biceps, .forearms] }
        static var legMuscles: [MuscleGroup] { [.quads, .hamstrings, .glutes, .calves] }

        /// Convert to Exercise.MuscleGroup for exercise list filtering
        var toExerciseMuscleGroup: Exercise.MuscleGroup {
            switch self {
            case .chest: .chest
            case .back: .back
            case .shoulders: .shoulders
            case .biceps: .biceps
            case .triceps: .triceps
            case .core: .core
            case .fullBody: .fullBody
            // Map leg sub-groups to "legs"
            case .quads, .hamstrings, .glutes, .calves: .legs
            // Forearms maps to biceps (arm work)
            case .forearms: .biceps
            }
        }
    }

    var muscleGroups: [MuscleGroup] {
        get {
            guard !targetMuscleGroups.isEmpty else { return [] }
            return targetMuscleGroups.split(separator: ",")
                .compactMap { MuscleGroup(rawValue: String($0)) }
        }
        set {
            targetMuscleGroups = newValue.map(\.rawValue).joined(separator: ",")
        }
    }
}

// MARK: - Computed Properties

extension LiveWorkout {
    /// Whether the workout is still in progress
    var isInProgress: Bool {
        completedAt == nil
    }

    /// Duration of the workout
    var duration: TimeInterval {
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    /// Total number of sets completed
    var totalSets: Int {
        entries?.reduce(0) { total, entry in
            total + (entry.completedSets?.count ?? 0)
        } ?? 0
    }

    /// Total volume (weight × reps) for strength exercises
    var totalVolume: Double {
        entries?.reduce(0) { total, entry in
            total + entry.totalVolume
        } ?? 0
    }
}
