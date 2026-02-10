//
//  ExerciseHistory.swift
//  Trai
//

import Foundation
import SwiftData

/// Tracks per-exercise progress over time for analytics and PR tracking
@Model
final class ExerciseHistory {
    var id: UUID = UUID()

    /// Reference to the exercise by ID (not a relationship for CloudKit compatibility)
    var exerciseId: UUID?

    /// Exercise name (stored for display, in case exercise is deleted)
    var exerciseName: String = ""

    /// When this entry was recorded
    var performedAt: Date = Date()

    /// Best set weight in kg
    var bestSetWeightKg: Double = 0

    /// Best set weight in lbs (pre-computed for clean display)
    var bestSetWeightLbs: Double = 0

    /// Best set reps
    var bestSetReps: Int = 0

    /// Total volume (weight × reps across all sets)
    var totalVolume: Double = 0

    /// Total sets completed
    var totalSets: Int = 0

    /// Total reps across all sets
    var totalReps: Int = 0

    /// Estimated one rep max (calculated at time of workout)
    var estimatedOneRepMax: Double?

    /// Reference to the source workout entry
    var sourceWorkoutEntryId: UUID?

    /// Rep pattern as comma-separated values (e.g., "12,10,8")
    var repPattern: String?

    /// Weight pattern as comma-separated values (e.g., "60,70,80")
    var weightPattern: String?

    init() {}

    init(from entry: LiveWorkoutEntry, performedAt: Date = Date()) {
        self.exerciseId = entry.exerciseId
        self.exerciseName = entry.exerciseName
        self.performedAt = performedAt

        if let best = entry.bestSet {
            // Use pre-computed clean values from SetData
            self.bestSetWeightKg = WeightUtility.round(best.weightKg, unit: .kg)
            self.bestSetWeightLbs = WeightUtility.round(best.weightLbs, unit: .lbs)
            self.bestSetReps = best.reps
        }

        self.totalVolume = entry.totalVolume
        self.totalSets = entry.completedSets?.count ?? 0
        self.totalReps = entry.totalReps
        self.estimatedOneRepMax = entry.estimatedOneRepMax
        self.sourceWorkoutEntryId = entry.id

        // Store rep and weight patterns from completed sets
        if let completedSets = entry.completedSets, !completedSets.isEmpty {
            self.repPattern = completedSets.map { "\($0.reps)" }.joined(separator: ",")
            self.weightPattern = completedSets.map { set -> String in
                let rounded = WeightUtility.round(set.weightKg, unit: .kg)
                return String(format: "%.1f", rounded)
            }.joined(separator: ",")
        }
    }

    /// Get rep pattern as array of integers
    var repPatternArray: [Int] {
        guard let pattern = repPattern else { return [] }
        return pattern.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Get weight pattern as array of doubles
    var weightPatternArray: [Double] {
        guard let pattern = weightPattern else { return [] }
        return pattern.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Computed Properties

extension ExerciseHistory {
    /// Best set volume (weight × reps)
    var bestSetVolume: Double {
        bestSetWeightKg * Double(bestSetReps)
    }

    /// Formatted date
    var formattedDate: String {
        performedAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// Get clean weight in user's preferred unit
    func displayWeight(usesMetric: Bool) -> Double {
        if usesMetric {
            return bestSetWeightKg
        } else {
            // Use stored lbs if available, otherwise compute
            return bestSetWeightLbs > 0 ? bestSetWeightLbs : WeightUtility.round(bestSetWeightKg * WeightUtility.kgToLbs, unit: .lbs)
        }
    }

    /// Get formatted weight string in user's preferred unit
    func formattedWeight(usesMetric: Bool, showUnit: Bool = true) -> String {
        let value = displayWeight(usesMetric: usesMetric)
        let unit = usesMetric ? "kg" : "lbs"
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return showUnit ? "\(Int(value)) \(unit)" : "\(Int(value))"
        }
        return showUnit ? String(format: "%.1f %@", value, unit) : String(format: "%.1f", value)
    }
}

// MARK: - Analytics Helpers

extension ExerciseHistory {
    /// Calculate progress between two history entries
    static func progress(from previous: ExerciseHistory, to current: ExerciseHistory) -> ProgressDelta {
        ProgressDelta(
            weightChange: current.bestSetWeightKg - previous.bestSetWeightKg,
            repsChange: current.bestSetReps - previous.bestSetReps,
            volumeChange: current.totalVolume - previous.totalVolume,
            oneRepMaxChange: (current.estimatedOneRepMax ?? 0) - (previous.estimatedOneRepMax ?? 0)
        )
    }

    struct ProgressDelta {
        let weightChange: Double
        let repsChange: Int
        let volumeChange: Double
        let oneRepMaxChange: Double

        var isImprovement: Bool {
            weightChange > 0 || repsChange > 0 || volumeChange > 0
        }

        var formattedWeightChange: String {
            if weightChange > 0 {
                return String(format: "+%.1f kg", weightChange)
            } else if weightChange < 0 {
                return String(format: "%.1f kg", weightChange)
            }
            return "No change"
        }
    }
}

// MARK: - Personal Records

extension ExerciseHistory {
    /// Record types for PR tracking
    enum RecordType: String, CaseIterable {
        case weight = "weight"
        case reps = "reps"
        case volume = "volume"
        case oneRepMax = "oneRepMax"

        var displayName: String {
            switch self {
            case .weight: "Heaviest Weight"
            case .reps: "Most Reps"
            case .volume: "Highest Volume"
            case .oneRepMax: "Best Estimated 1RM"
            }
        }

        var iconName: String {
            switch self {
            case .weight: "scalemass.fill"
            case .reps: "number.circle.fill"
            case .volume: "chart.bar.fill"
            case .oneRepMax: "trophy.fill"
            }
        }
    }

    /// Check if this entry sets a new record compared to previous best
    func isNewRecord(_ type: RecordType, comparedTo previous: ExerciseHistory?) -> Bool {
        guard let previous else { return true }

        switch type {
        case .weight:
            return bestSetWeightKg > previous.bestSetWeightKg
        case .reps:
            return bestSetReps > previous.bestSetReps
        case .volume:
            return totalVolume > previous.totalVolume
        case .oneRepMax:
            guard let current1RM = estimatedOneRepMax,
                  let previous1RM = previous.estimatedOneRepMax else { return false }
            return current1RM > previous1RM
        }
    }
}

// MARK: - Performance Snapshot

struct ExercisePerformanceSnapshot {
    let exerciseName: String
    let lastSession: ExerciseHistory?
    let weightPR: ExerciseHistory?
    let repsPR: ExerciseHistory?
    let volumePR: ExerciseHistory?
    let estimatedOneRepMax: Double?
    let totalSessions: Int
}

final class ExercisePerformanceService {
    /// Fetch exercise history sorted by most-recent session first.
    func history(
        for exerciseName: String,
        limit: Int? = nil,
        modelContext: ModelContext
    ) -> [ExerciseHistory] {
        var descriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func snapshot(
        for exerciseName: String,
        modelContext: ModelContext
    ) -> ExercisePerformanceSnapshot? {
        let history = history(for: exerciseName, modelContext: modelContext)
        return Self.snapshot(exerciseName: exerciseName, history: history)
    }

    static func snapshots(from history: [ExerciseHistory]) -> [String: ExercisePerformanceSnapshot] {
        let grouped = Dictionary(grouping: history, by: { $0.exerciseName })
        return grouped.reduce(into: [:]) { result, item in
            let (exerciseName, exerciseHistory) = item
            if let snapshot = snapshot(exerciseName: exerciseName, history: exerciseHistory) {
                result[exerciseName] = snapshot
            }
        }
    }

    static func snapshot(
        exerciseName: String,
        history: [ExerciseHistory]
    ) -> ExercisePerformanceSnapshot? {
        guard !history.isEmpty else { return nil }

        return ExercisePerformanceSnapshot(
            exerciseName: exerciseName,
            lastSession: mostRecentRecord(in: history),
            weightPR: bestWeightRecord(in: history),
            repsPR: bestRepsRecord(in: history),
            volumePR: bestVolumeRecord(in: history),
            estimatedOneRepMax: history.compactMap(\.estimatedOneRepMax).max(),
            totalSessions: history.count
        )
    }

    static func bestWeightRecord(in history: [ExerciseHistory]) -> ExerciseHistory? {
        history
            .filter { $0.bestSetWeightKg > 0 }
            .max(by: isWeightRecordWorse(_:_:))
    }

    static func bestRepsRecord(in history: [ExerciseHistory]) -> ExerciseHistory? {
        history
            .filter { $0.bestSetReps > 0 }
            .max(by: isRepsRecordWorse(_:_:))
    }

    static func bestVolumeRecord(in history: [ExerciseHistory]) -> ExerciseHistory? {
        history
            .filter { $0.totalVolume > 0 }
            .max(by: isVolumeRecordWorse(_:_:))
    }

    private static func mostRecentRecord(in history: [ExerciseHistory]) -> ExerciseHistory? {
        history.max(by: isRecentRecordWorse(_:_:))
    }

    private static func isWeightRecordWorse(_ lhs: ExerciseHistory, _ rhs: ExerciseHistory) -> Bool {
        if lhs.bestSetWeightKg != rhs.bestSetWeightKg {
            return lhs.bestSetWeightKg < rhs.bestSetWeightKg
        }
        if lhs.bestSetReps != rhs.bestSetReps {
            return lhs.bestSetReps < rhs.bestSetReps
        }
        if lhs.totalVolume != rhs.totalVolume {
            return lhs.totalVolume < rhs.totalVolume
        }
        if lhs.performedAt != rhs.performedAt {
            return lhs.performedAt < rhs.performedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isRepsRecordWorse(_ lhs: ExerciseHistory, _ rhs: ExerciseHistory) -> Bool {
        if lhs.bestSetReps != rhs.bestSetReps {
            return lhs.bestSetReps < rhs.bestSetReps
        }
        if lhs.bestSetWeightKg != rhs.bestSetWeightKg {
            return lhs.bestSetWeightKg < rhs.bestSetWeightKg
        }
        if lhs.totalVolume != rhs.totalVolume {
            return lhs.totalVolume < rhs.totalVolume
        }
        if lhs.performedAt != rhs.performedAt {
            return lhs.performedAt < rhs.performedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isVolumeRecordWorse(_ lhs: ExerciseHistory, _ rhs: ExerciseHistory) -> Bool {
        if lhs.totalVolume != rhs.totalVolume {
            return lhs.totalVolume < rhs.totalVolume
        }
        if lhs.bestSetWeightKg != rhs.bestSetWeightKg {
            return lhs.bestSetWeightKg < rhs.bestSetWeightKg
        }
        if lhs.bestSetReps != rhs.bestSetReps {
            return lhs.bestSetReps < rhs.bestSetReps
        }
        if lhs.performedAt != rhs.performedAt {
            return lhs.performedAt < rhs.performedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isRecentRecordWorse(_ lhs: ExerciseHistory, _ rhs: ExerciseHistory) -> Bool {
        if lhs.performedAt != rhs.performedAt {
            return lhs.performedAt < rhs.performedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
