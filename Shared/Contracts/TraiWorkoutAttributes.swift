//
//  TraiWorkoutAttributes.swift
//  Shared
//
//  Live Activity attributes shared by app and widget extension.
//

import ActivityKit
import Foundation

struct TraiWorkoutAttributes: ActivityAttributes {
    let workoutName: String
    let targetMuscles: [String]
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        let elapsedSeconds: Int
        let currentExercise: String?
        let currentEquipment: String?
        let completedSets: Int
        let totalSets: Int
        let heartRate: Int?
        let isPaused: Bool
        let currentWeightKg: Double?
        let currentWeightLbs: Double?
        let currentReps: Int?
        let totalVolumeKg: Double?
        let totalVolumeLbs: Double?
        let nextExercise: String?
        let usesMetricWeight: Bool

        init(
            elapsedSeconds: Int,
            currentExercise: String? = nil,
            currentEquipment: String? = nil,
            completedSets: Int,
            totalSets: Int,
            heartRate: Int? = nil,
            isPaused: Bool,
            currentWeightKg: Double? = nil,
            currentWeightLbs: Double? = nil,
            currentReps: Int? = nil,
            totalVolumeKg: Double? = nil,
            totalVolumeLbs: Double? = nil,
            nextExercise: String? = nil,
            usesMetricWeight: Bool = true
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.currentExercise = currentExercise
            self.currentEquipment = currentEquipment
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.heartRate = heartRate
            self.isPaused = isPaused
            self.currentWeightKg = currentWeightKg
            self.currentWeightLbs = currentWeightLbs
            self.currentReps = currentReps
            self.totalVolumeKg = totalVolumeKg
            self.totalVolumeLbs = totalVolumeLbs
            self.nextExercise = nextExercise
            self.usesMetricWeight = usesMetricWeight
        }

        var formattedTime: String {
            let hours = elapsedSeconds / 3600
            let minutes = (elapsedSeconds % 3600) / 60
            let seconds = elapsedSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        var progress: Double {
            guard totalSets > 0 else { return 0 }
            return Double(completedSets) / Double(totalSets)
        }

        var setsDisplay: String {
            "\(completedSets)/\(totalSets) sets"
        }

        var volumeDisplay: String? {
            let displayVolume: Double?
            let unit: String
            if usesMetricWeight {
                displayVolume = totalVolumeKg
                unit = "kg"
            } else {
                displayVolume = totalVolumeLbs ?? totalVolumeKg.map { $0 * 2.20462 }
                unit = "lbs"
            }
            guard let volume = displayVolume, volume > 0 else { return nil }
            if volume >= 1000 {
                return String(format: "%.1fk %@", volume / 1000, unit)
            }
            return "\(Int(volume.rounded())) \(unit)"
        }

        var currentSetDisplay: String? {
            guard let reps = currentReps else { return nil }
            let displayWeight: Double?
            let unit: String
            if usesMetricWeight {
                displayWeight = currentWeightKg
                unit = "kg"
            } else {
                displayWeight = currentWeightLbs ?? currentWeightKg.map { $0 * 2.20462 }
                unit = "lbs"
            }
            guard let weight = displayWeight, weight > 0 else { return nil }
            return "\(Int(weight.rounded()))\(unit) \u{00D7} \(reps)"
        }
    }
}
