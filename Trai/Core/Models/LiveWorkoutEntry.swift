//
//  LiveWorkoutEntry.swift
//  Trai
//

import Foundation
import SwiftData

/// Represents a single exercise within a live workout, with detailed set tracking
@Model
final class LiveWorkoutEntry {
    var id: UUID = UUID()

    /// Order of this exercise in the workout (0-based)
    var orderIndex: Int = 0

    /// Reference to the exercise by ID (not a relationship for CloudKit compatibility)
    var exerciseId: UUID?

    /// Exercise name (stored for display, in case exercise is deleted)
    var exerciseName: String = ""

    /// Equipment/machine name (e.g., "Life Fitness Lat Pulldown", "Rack 3")
    var equipmentName: String?

    /// Type of exercise: "strength", "cardio", or "flexibility"
    var exerciseType: String = "strength"

    /// JSON-encoded sets data for strength exercises
    /// Format: [{"reps": 10, "weightKg": 50.0, "completed": true, "isWarmup": false}]
    var setsData: String = "[]"

    /// Duration in seconds (for cardio/timed exercises)
    var durationSeconds: Int?

    /// Distance in meters (for cardio exercises)
    var distanceMeters: Double?

    /// Calories burned (from HealthKit or manual entry)
    var caloriesBurned: Double?

    /// Notes for this specific exercise
    var notes: String = ""

    /// When this exercise was completed (nil if still in progress)
    var completedAt: Date?

    /// Parent workout
    var workout: LiveWorkout?

    init() {}

    /// Whether this is a cardio exercise
    var isCardio: Bool {
        exerciseType == "cardio"
    }

    /// Whether this is a strength exercise
    var isStrength: Bool {
        exerciseType == "strength"
    }

    init(exercise: Exercise, orderIndex: Int) {
        self.exerciseId = exercise.id
        self.exerciseName = exercise.name
        self.exerciseType = exercise.category
        self.equipmentName = exercise.displayEquipment  // Use inferred equipment if not stored
        self.orderIndex = orderIndex
    }

    init(exerciseName: String, orderIndex: Int, exerciseId: UUID? = nil, exerciseType: String = "strength", equipmentName: String? = nil) {
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.exerciseId = exerciseId
        self.exerciseType = exerciseType
        self.equipmentName = equipmentName
    }
}

// MARK: - Set Data Model

extension LiveWorkoutEntry {
    struct SetData: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var reps: Int
        var weightKg: Double
        var completed: Bool
        var isWarmup: Bool
        var notes: String

        init(reps: Int = 0, weightKg: Double = 0, completed: Bool = false, isWarmup: Bool = false, notes: String = "") {
            self.reps = reps
            self.weightKg = weightKg
            self.completed = completed
            self.isWarmup = isWarmup
            self.notes = notes
        }

        // Custom decoder to handle missing notes field in existing data
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            reps = try container.decode(Int.self, forKey: .reps)
            weightKg = try container.decode(Double.self, forKey: .weightKg)
            completed = try container.decode(Bool.self, forKey: .completed)
            isWarmup = try container.decode(Bool.self, forKey: .isWarmup)
            notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        }

        /// Volume for this set (weight × reps)
        var volume: Double {
            Double(reps) * weightKg
        }
    }
}

// MARK: - Sets Management

extension LiveWorkoutEntry {
    /// Parsed sets from JSON
    var sets: [SetData] {
        get {
            guard let data = setsData.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([SetData].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            setsData = json
        }
    }

    /// Add a new set
    func addSet(_ set: SetData = SetData()) {
        var currentSets = sets
        currentSets.append(set)
        sets = currentSets
    }

    /// Update a set at index
    func updateSet(at index: Int, with set: SetData) {
        var currentSets = sets
        guard index < currentSets.count else { return }
        currentSets[index] = set
        sets = currentSets
    }

    /// Remove a set at index
    func removeSet(at index: Int) {
        var currentSets = sets
        guard index < currentSets.count else { return }
        currentSets.remove(at: index)
        sets = currentSets
    }

    /// Toggle set completion
    func toggleSetCompletion(at index: Int) {
        var currentSets = sets
        guard index < currentSets.count else { return }
        currentSets[index].completed.toggle()
        sets = currentSets
    }
}

// MARK: - Computed Properties

extension LiveWorkoutEntry {
    /// Only completed (non-warmup) sets
    var completedSets: [SetData]? {
        sets.filter { $0.completed && !$0.isWarmup }
    }

    /// Total volume for this exercise
    var totalVolume: Double {
        completedSets?.reduce(0) { $0 + $1.volume } ?? 0
    }

    /// Best set (highest volume)
    var bestSet: SetData? {
        completedSets?.max(by: { $0.volume < $1.volume })
    }

    /// Total reps completed
    var totalReps: Int {
        completedSets?.reduce(0) { $0 + $1.reps } ?? 0
    }

    /// Average weight used
    var averageWeight: Double {
        guard let completed = completedSets, !completed.isEmpty else { return 0 }
        return completed.reduce(0) { $0 + $1.weightKg } / Double(completed.count)
    }

    /// Whether this entry is complete
    var isComplete: Bool {
        completedAt != nil
    }

    /// Estimated one rep max using Brzycki formula
    var estimatedOneRepMax: Double? {
        guard let best = bestSet, best.reps > 0, best.reps <= 12 else { return nil }
        // Brzycki formula: 1RM = weight × (36 / (37 - reps))
        return best.weightKg * (36.0 / (37.0 - Double(best.reps)))
    }
}

// MARK: - Cardio Helpers

extension LiveWorkoutEntry {
    /// Formatted duration
    var formattedDuration: String? {
        guard let seconds = durationSeconds else { return nil }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    /// Formatted distance
    var formattedDistance: String? {
        guard let meters = distanceMeters else { return nil }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    /// Pace (min/km) for cardio
    var pacePerKm: Double? {
        guard let meters = distanceMeters, meters > 0,
              let seconds = durationSeconds, seconds > 0 else { return nil }
        let km = meters / 1000
        let minutes = Double(seconds) / 60
        return minutes / km
    }

    /// Formatted pace string
    var formattedPace: String? {
        guard let pace = pacePerKm else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}
