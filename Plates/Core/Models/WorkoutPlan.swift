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
