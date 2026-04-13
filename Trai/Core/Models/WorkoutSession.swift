import Foundation
import SwiftData

/// Represents a single workout session or exercise set
@Model
final class WorkoutSession {
    var id: UUID = UUID()

    /// The exercise performed (optional for HealthKit-imported workouts)
    var exercise: Exercise?

    /// Name of exercise (used when exercise relationship is nil)
    var exerciseName: String?

    // Strength training metrics
    var sets: Int = 0
    var reps: Int = 0
    var weightKg: Double?

    // Cardio metrics
    var durationMinutes: Double?
    var caloriesBurned: Int?
    var distanceMeters: Double?
    var averageHeartRate: Int?

    /// Whether this was imported from HealthKit
    var sourceIsHealthKit: Bool = false

    /// HealthKit workout UUID for deduplication
    var healthKitWorkoutID: String?

    /// Type of workout from HealthKit (e.g., "running", "cycling")
    var healthKitWorkoutType: String?

    var loggedAt: Date = Date()
    var notes: String?

    init() {}

    /// Initialize for strength training
    init(exercise: Exercise, sets: Int, reps: Int, weightKg: Double?) {
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
    }

    /// Initialize for cardio from HealthKit
    init(
        healthKitWorkoutID: String,
        workoutType: String,
        durationMinutes: Double,
        caloriesBurned: Int?,
        distanceMeters: Double?,
        loggedAt: Date
    ) {
        self.healthKitWorkoutID = healthKitWorkoutID
        self.healthKitWorkoutType = workoutType
        self.exerciseName = workoutType.capitalized
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
        self.loggedAt = loggedAt
        self.sourceIsHealthKit = true
    }
}

// MARK: - Computed Properties

extension WorkoutSession {
    /// Display name for the workout
    var displayName: String {
        exercise?.name ?? exerciseName ?? healthKitWorkoutType?.capitalized ?? "Workout"
    }

    /// Total volume (sets * reps * weight) for strength exercises
    var totalVolume: Double? {
        guard let weightKg, sets > 0, reps > 0 else { return nil }
        return Double(sets * reps) * weightKg
    }

    /// Normalized session volume to compare across different set counts.
    var volumePerSet: Double? {
        guard let totalVolume, sets > 0 else { return nil }
        return totalVolume / Double(sets)
    }

    /// Returns the volume metric value using the selected PR mode.
    func volumeValue(for mode: UserProfile.VolumePRMode) -> Double? {
        switch mode {
        case .perSet:
            return volumePerSet
        case .totalVolume:
            return totalVolume
        }
    }

    /// Formatted duration string
    var formattedDuration: String? {
        guard let durationMinutes else { return nil }
        let hours = Int(durationMinutes) / 60
        let minutes = Int(durationMinutes) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Formatted distance string
    var formattedDistance: String? {
        guard let distanceMeters else { return nil }
        let kilometers = distanceMeters / 1000

        if kilometers >= 1 {
            return String(format: "%.2f km", kilometers)
        } else {
            return "\(Int(distanceMeters)) m"
        }
    }

    /// Check if this is a strength training session
    var isStrengthTraining: Bool {
        exercise?.category == "strength" || (sets > 0 && reps > 0)
    }

    /// Check if this is a cardio session
    var isCardio: Bool {
        exercise?.category == "cardio" || durationMinutes != nil || healthKitWorkoutType != nil
    }

    var displayTypeName: String {
        if isStrengthTraining {
            return "Strength Training"
        }

        let rawType = healthKitWorkoutType ?? exercise?.category
        let cleaned = rawType?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleaned.isEmpty else {
            return isCardio ? "Cardio" : "Workout"
        }

        return cleaned
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var inferredWorkoutMode: WorkoutMode {
        if isStrengthTraining {
            return .strength
        }

        return WorkoutMode.infer(
            from: displayName,
            focusAreas: [healthKitWorkoutType ?? exercise?.category ?? displayTypeName],
            targetMuscleGroups: []
        )
    }

    var trimmedNotes: String {
        (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSignalNote: Bool {
        !trimmedNotes.isEmpty
    }

    var traiReviewPrompt: String {
        var prompt = "Can you review my \(displayName) session from \(loggedAt.formatted(date: .abbreviated, time: .shortened))?"

        var details: [String] = []
        details.append(displayTypeName.lowercased())

        if let formattedDuration {
            details.append("duration \(formattedDuration)")
        }
        if let formattedDistance {
            details.append("distance \(formattedDistance)")
        }
        if sets > 0 {
            details.append("\(sets) sets")
        }
        if reps > 0 {
            details.append("\(reps) reps")
        }
        if let caloriesBurned {
            details.append("\(caloriesBurned) kcal")
        }

        if !details.isEmpty {
            prompt += " It was a \(details.joined(separator: ", "))."
        }

        if hasSignalNote {
            prompt += " I added these notes: \(trimmedNotes)."
        } else if sourceIsHealthKit {
            prompt += " This one was tracked on my Apple Watch, so please use the workout data that was imported."
        }

        prompt += " Tell me what this says about my progress and what I should focus on next."
        return prompt
    }

    var goalMatchingTokens: Set<String> {
        var tokens: Set<String> = []
        [displayName, exerciseName, healthKitWorkoutType, exercise?.category, displayTypeName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .forEach { tokens.insert($0.goalNormalizedKey) }
        return tokens
    }

    var iconName: String {
        let token = (healthKitWorkoutType ?? exercise?.category ?? "")
            .lowercased()

        if isStrengthTraining || token.contains("strength") || token.contains("weight") {
            return "dumbbell.fill"
        }
        if token.contains("run") {
            return "figure.run"
        }
        if token.contains("cycle") || token.contains("bike") {
            return "figure.outdoor.cycle"
        }
        if token.contains("swim") {
            return "figure.pool.swim"
        }
        if token.contains("walk") || token.contains("hike") {
            return "figure.walk"
        }
        if token.contains("row") {
            return "figure.rower"
        }
        if token.contains("yoga") {
            return "figure.yoga"
        }
        if token.contains("pilates") || token.contains("stretch") || token.contains("flexibility") {
            return "figure.flexibility"
        }
        if token.contains("climb") || token.contains("boulder") {
            return "figure.climbing"
        }
        if token.contains("hiit") || token.contains("interval") || token.contains("conditioning") {
            return "bolt.heart.fill"
        }
        return isCardio ? "figure.mixed.cardio" : "figure.run"
    }
}
