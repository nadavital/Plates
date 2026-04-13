//
//  LiveWorkout.swift
//  Trai
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

    /// Flexible focus labels for non-strength sessions, e.g. "Yoga Flow, Recovery"
    var sessionFocus: String = ""

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

    init(
        name: String,
        workoutType: WorkoutType,
        targetMuscleGroups: [MuscleGroup] = [],
        focusAreas: [String] = []
    ) {
        self.name = name
        self.workoutType = workoutType.rawValue
        self.targetMuscleGroups = targetMuscleGroups.map(\.rawValue).joined(separator: ",")
        self.focusAreas = focusAreas
    }
}

// MARK: - Workout Type

extension LiveWorkout {
    typealias WorkoutType = WorkoutMode

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
        static var upperBodyMuscles: [MuscleGroup] { [.chest, .back, .shoulders, .biceps, .triceps, .forearms] }

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

        /// Normalize persisted/API muscle strings into app muscle groups.
        static func fromTargetString(_ raw: String) -> [MuscleGroup] {
            let token = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")

            switch token {
            case "chest": return [.chest]
            case "back": return [.back]
            case "shoulders", "shoulder": return [.shoulders]
            case "biceps", "bicep": return [.biceps]
            case "triceps", "tricep": return [.triceps]
            case "forearms", "forearm": return [.forearms]
            case "core", "abs", "abdominals": return [.core]
            case "quads", "quad": return [.quads]
            case "hamstrings", "hamstring": return [.hamstrings]
            case "glutes", "glute": return [.glutes]
            case "calves", "calf": return [.calves]
            case "legs", "lowerbody", "lower": return legMuscles
            case "upperbody", "upper": return upperBodyMuscles
            case "arms", "arm": return [.biceps, .triceps, .forearms]
            case "cardio", "conditioning", "hiit", "intervals", "running", "cycling", "swimming", "rowing", "climbing", "walking", "mobility", "flexibility", "recovery", "zone2", "zone 2":
                return [.fullBody]
            case "fullbody": return [.fullBody]
            default:
                return []
            }
        }

        static func fromTargetStrings(_ rawGroups: [String]) -> [MuscleGroup] {
            var groups: [MuscleGroup] = []
            var seen: Set<MuscleGroup> = []

            for raw in rawGroups {
                for group in fromTargetString(raw) where !seen.contains(group) {
                    groups.append(group)
                    seen.insert(group)
                }
            }

            if groups.isEmpty {
                return [.fullBody]
            }

            if groups.count > 1 {
                return groups.filter { $0 != .fullBody }
            }

            return groups
        }
    }

    var muscleGroups: [MuscleGroup] {
        get {
            guard !targetMuscleGroups.isEmpty else { return [] }
            return MuscleGroup.fromTargetStrings(
                targetMuscleGroups
                    .split(separator: ",")
                    .map(String.init)
            )
        }
        set {
            targetMuscleGroups = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    var focusAreas: [String] {
        get {
            sessionFocus
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            sessionFocus = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }

    var displayFocusSummary: String {
        if !focusAreas.isEmpty {
            return focusAreas.joined(separator: " • ")
        }
        let muscles = muscleGroups.map(\.displayName)
        return muscles.isEmpty ? type.displayName : muscles.joined(separator: " • ")
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var traiReviewPrompt: String {
        var prompt = "Can you review my \(name) workout from \(startedAt.formatted(date: .abbreviated, time: .shortened))?"

        var details: [String] = [type.displayName.lowercased()]

        if !displayFocusSummary.isEmpty {
            details.append("focus \(displayFocusSummary)")
        }

        let durationMinutes = Int(duration / 60)
        if durationMinutes > 0 {
            details.append("duration \(formattedDuration)")
        }

        let entryCount = entries?.count ?? 0
        if entryCount > 0 {
            details.append("\(entryCount) \(entryCount == 1 ? "item" : "items")")
        }

        if let healthKitCalories, healthKitCalories > 0 {
            details.append("\(Int(healthKitCalories)) kcal")
        }

        if !details.isEmpty {
            prompt += " It was a \(details.joined(separator: ", "))."
        }

        if !trimmedNotes.isEmpty {
            prompt += " I added these notes: \(trimmedNotes)."
        }

        prompt += " Tell me what this says about my progress and what I should focus on next."
        return prompt
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
