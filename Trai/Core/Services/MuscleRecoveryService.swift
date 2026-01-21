//
//  MuscleRecoveryService.swift
//  Trai
//

import Foundation
import SwiftData

/// Service to calculate muscle group recovery status based on workout history
@MainActor @Observable
final class MuscleRecoveryService {

    // MARK: - Recovery Status

    enum RecoveryStatus: String, CaseIterable {
        case ready = "ready"           // 48+ hours - fully recovered
        case recovering = "recovering" // 24-48 hours - moderate recovery
        case tired = "tired"           // <24 hours - needs rest

        var displayName: String {
            switch self {
            case .ready: "Ready"
            case .recovering: "Recovering"
            case .tired: "Needs Rest"
            }
        }

        var description: String {
            switch self {
            case .ready: "Fully recovered and ready to train"
            case .recovering: "Still recovering, light training okay"
            case .tired: "Recently trained, rest recommended"
            }
        }

        var iconName: String {
            switch self {
            case .ready: "checkmark.circle.fill"
            case .recovering: "clock.fill"
            case .tired: "moon.zzz.fill"
            }
        }
    }

    // MARK: - Muscle Recovery Info

    struct MuscleRecoveryInfo: Identifiable {
        let muscleGroup: LiveWorkout.MuscleGroup
        let status: RecoveryStatus
        let lastTrainedAt: Date?
        let hoursSinceTraining: Double?

        var id: String { muscleGroup.rawValue }

        var formattedLastTrained: String {
            guard let lastTrainedAt else { return "Never trained" }

            let hours = Date().timeIntervalSince(lastTrainedAt) / 3600
            if hours < 1 {
                return "Just now"
            } else if hours < 24 {
                return "\(Int(hours))h ago"
            } else {
                let days = Int(hours / 24)
                return days == 1 ? "Yesterday" : "\(days) days ago"
            }
        }
    }

    // MARK: - Recovery Thresholds (in hours)

    private let readyThreshold: Double = 48    // 2 days
    private let recoveringThreshold: Double = 24  // 1 day

    // MARK: - Public Methods

    /// Get recovery status for all muscle groups
    func getRecoveryStatus(modelContext: ModelContext) -> [MuscleRecoveryInfo] {
        let lastTrainedDates = getLastTrainedDates(modelContext: modelContext)

        // Exclude fullBody - it's not a real muscle group for recovery tracking
        return LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }.map { muscleGroup in
            let lastTrained = lastTrainedDates[muscleGroup]
            let hoursSince = lastTrained.map { Date().timeIntervalSince($0) / 3600 }
            let status = calculateStatus(hoursSinceTraining: hoursSince)

            return MuscleRecoveryInfo(
                muscleGroup: muscleGroup,
                status: status,
                lastTrainedAt: lastTrained,
                hoursSinceTraining: hoursSince
            )
        }
    }

    /// Get only muscle groups that are ready to train
    func getReadyMuscleGroups(modelContext: ModelContext) -> [LiveWorkout.MuscleGroup] {
        getRecoveryStatus(modelContext: modelContext)
            .filter { $0.status == .ready }
            .map(\.muscleGroup)
    }

    /// Get recommended muscle groups to train today
    func getRecommendedMuscleGroups(modelContext: ModelContext) -> [LiveWorkout.MuscleGroup] {
        let recoveryInfo = getRecoveryStatus(modelContext: modelContext)

        // Filter to ready muscles
        let readyMuscles = recoveryInfo.filter { $0.status == .ready }

        // Sort by longest time since training (prioritize least recently trained)
        let sorted = readyMuscles.sorted { info1, info2 in
            let hours1 = info1.hoursSinceTraining ?? Double.infinity
            let hours2 = info2.hoursSinceTraining ?? Double.infinity
            return hours1 > hours2
        }

        // Return top muscle groups, preferring complete workout splits
        return suggestWorkoutSplit(from: sorted.map(\.muscleGroup))
    }

    /// Get recovery summary for AI context
    func getRecoverySummary(modelContext: ModelContext) -> [String: Any] {
        let recoveryInfo = getRecoveryStatus(modelContext: modelContext)

        let readyMuscles = recoveryInfo.filter { $0.status == .ready }
        let recoveringMuscles = recoveryInfo.filter { $0.status == .recovering }
        let tiredMuscles = recoveryInfo.filter { $0.status == .tired }

        return [
            "ready_muscles": readyMuscles.map { [
                "muscle": $0.muscleGroup.displayName,
                "last_trained": $0.formattedLastTrained,
                "hours_since": $0.hoursSinceTraining.map { Int($0) } as Any
            ]},
            "recovering_muscles": recoveringMuscles.map { [
                "muscle": $0.muscleGroup.displayName,
                "last_trained": $0.formattedLastTrained,
                "hours_since": $0.hoursSinceTraining.map { Int($0) } as Any
            ]},
            "tired_muscles": tiredMuscles.map { [
                "muscle": $0.muscleGroup.displayName,
                "last_trained": $0.formattedLastTrained,
                "hours_since": $0.hoursSinceTraining.map { Int($0) } as Any
            ]},
            "recommended_workout": getRecommendedWorkoutType(from: recoveryInfo),
            "recommended_muscles": getRecommendedMuscleGroups(modelContext: modelContext)
                .map(\.displayName)
        ]
    }

    // MARK: - Private Methods

    /// Get the last trained date for each muscle group
    /// Note: Derives muscle groups from actual exercises performed, not user-selected targets
    private func getLastTrainedDates(modelContext: ModelContext) -> [LiveWorkout.MuscleGroup: Date] {
        var lastTrained: [LiveWorkout.MuscleGroup: Date] = [:]

        // Get all exercises for muscle group lookup
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let exercises = (try? modelContext.fetch(exerciseDescriptor)) ?? []
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name.lowercased(), $0) })

        // Query completed LiveWorkouts and derive muscles from actual exercises
        let workoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { $0.completedAt != nil },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )

        if let workouts = try? modelContext.fetch(workoutDescriptor) {
            for workout in workouts {
                guard let entries = workout.entries, !entries.isEmpty else { continue }
                let completionDate = workout.completedAt ?? workout.startedAt

                // Derive muscle groups from actual exercises performed
                for entry in entries {
                    // Skip entries with no sets completed
                    guard entry.sets.contains(where: { $0.completed }) else { continue }

                    // Try to find the exercise by ID first, then by name
                    var muscleGroupString: String?
                    if let exerciseId = entry.exerciseId,
                       let exercise = exerciseById[exerciseId] {
                        muscleGroupString = exercise.muscleGroup
                    } else if let exercise = exerciseByName[entry.exerciseName.lowercased()] {
                        muscleGroupString = exercise.muscleGroup
                    }

                    guard let muscleGroup = muscleGroupString else { continue }

                    let mappedGroups = mapExerciseMuscleGroup(muscleGroup)
                    for group in mappedGroups {
                        if lastTrained[group] == nil {
                            lastTrained[group] = completionDate
                        }
                    }
                }
            }
        }

        // Also check ExerciseHistory for additional exercise data
        let historyDescriptor = FetchDescriptor<ExerciseHistory>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )

        if let histories = try? modelContext.fetch(historyDescriptor) {
            for history in histories {
                guard let exerciseId = history.exerciseId,
                      let exercise = exerciseById[exerciseId],
                      let muscleGroupString = exercise.muscleGroup else { continue }

                // Map Exercise.MuscleGroup to LiveWorkout.MuscleGroup
                let mappedGroups = mapExerciseMuscleGroup(muscleGroupString)

                for muscleGroup in mappedGroups {
                    if lastTrained[muscleGroup] == nil {
                        lastTrained[muscleGroup] = history.performedAt
                    }
                }
            }
        }

        return lastTrained
    }

    /// Map Exercise muscle group string to LiveWorkout MuscleGroups
    private func mapExerciseMuscleGroup(_ muscleGroup: String) -> [LiveWorkout.MuscleGroup] {
        switch muscleGroup {
        case "chest": return [.chest]
        case "back": return [.back]
        case "shoulders": return [.shoulders]
        case "biceps": return [.biceps]
        case "triceps": return [.triceps]
        case "legs": return [.quads, .hamstrings, .glutes, .calves]
        case "core": return [.core]
        case "fullBody": return LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }
        default: return []
        }
    }

    /// Calculate recovery status from hours since training
    private func calculateStatus(hoursSinceTraining: Double?) -> RecoveryStatus {
        guard let hours = hoursSinceTraining else {
            return .ready  // Never trained = ready to train
        }

        if hours >= readyThreshold {
            return .ready
        } else if hours >= recoveringThreshold {
            return .recovering
        } else {
            return .tired
        }
    }

    /// Suggest a coherent workout split from available muscles
    private func suggestWorkoutSplit(from availableMuscles: [LiveWorkout.MuscleGroup]) -> [LiveWorkout.MuscleGroup] {
        let available = Set(availableMuscles)

        // Check for push day (chest, shoulders, triceps)
        let pushMuscles = Set(LiveWorkout.MuscleGroup.pushMuscles)
        if pushMuscles.isSubset(of: available) {
            return LiveWorkout.MuscleGroup.pushMuscles
        }

        // Check for pull day (back, biceps)
        let pullMuscles = Set(LiveWorkout.MuscleGroup.pullMuscles)
        if pullMuscles.isSubset(of: available) {
            return LiveWorkout.MuscleGroup.pullMuscles
        }

        // Check for leg day
        let legMuscles = Set(LiveWorkout.MuscleGroup.legMuscles)
        if legMuscles.isSubset(of: available) {
            return LiveWorkout.MuscleGroup.legMuscles
        }

        // Fall back to top 3-4 available muscles
        return Array(availableMuscles.prefix(4))
    }

    /// Get recommended workout type based on recovery status
    private func getRecommendedWorkoutType(from recoveryInfo: [MuscleRecoveryInfo]) -> String {
        let readyMuscles = Set(recoveryInfo.filter { $0.status == .ready }.map(\.muscleGroup))

        // Check for full push/pull/legs splits
        if Set(LiveWorkout.MuscleGroup.pushMuscles).isSubset(of: readyMuscles) {
            return "Push Day (Chest, Shoulders, Triceps)"
        }
        if Set(LiveWorkout.MuscleGroup.pullMuscles).isSubset(of: readyMuscles) {
            return "Pull Day (Back, Biceps)"
        }
        if Set(LiveWorkout.MuscleGroup.legMuscles).isSubset(of: readyMuscles) {
            return "Leg Day"
        }

        // Suggest based on what's available
        if readyMuscles.isEmpty {
            return "Rest Day or Light Cardio"
        } else if readyMuscles.count >= 4 {
            return "Full Body Workout"
        } else {
            return "Targeted Workout"
        }
    }

    // MARK: - Template Scoring

    /// Score all templates and return recovery info for each
    func scoreTemplates(
        _ templates: [WorkoutPlan.WorkoutTemplate],
        modelContext: ModelContext
    ) -> [UUID: (score: Double, reason: String)] {
        let recoveryInfo = getRecoveryStatus(modelContext: modelContext)

        var scores: [UUID: (score: Double, reason: String)] = [:]

        for template in templates {
            let (score, reason) = scoreTemplate(template, recoveryInfo: recoveryInfo)
            scores[template.id] = (score, reason)
        }

        return scores
    }

    /// Get the best matching workout template based on current recovery status
    func getBestTemplateForToday(
        plan: WorkoutPlan,
        modelContext: ModelContext
    ) -> (template: WorkoutPlan.WorkoutTemplate, score: Double, reason: String)? {
        guard !plan.templates.isEmpty else { return nil }

        let scores = scoreTemplates(plan.templates, modelContext: modelContext)

        // Find template with highest score
        var bestTemplate: WorkoutPlan.WorkoutTemplate?
        var bestScore: Double = -1
        var bestReason: String = ""

        for template in plan.templates {
            if let (score, reason) = scores[template.id], score > bestScore {
                bestScore = score
                bestReason = reason
                bestTemplate = template
            }
        }

        guard let template = bestTemplate else { return nil }

        return (template, bestScore, bestReason)
    }

    /// Score a single template based on muscle recovery
    func scoreTemplate(
        _ template: WorkoutPlan.WorkoutTemplate,
        recoveryInfo: [MuscleRecoveryInfo]
    ) -> (score: Double, reason: String) {
        // Map template muscle groups to LiveWorkout.MuscleGroup
        let templateMuscles = template.targetMuscleGroups.compactMap { name in
            LiveWorkout.MuscleGroup(rawValue: name)
        }

        guard !templateMuscles.isEmpty else {
            return (0.5, "Unknown muscle groups")
        }

        // Get recovery status for each target muscle
        var readyCount = 0
        var recoveringCount = 0
        var tiredCount = 0
        var tiredMuscles: [String] = []
        var recoveringMuscles: [String] = []

        for muscle in templateMuscles {
            if let info = recoveryInfo.first(where: { $0.muscleGroup == muscle }) {
                switch info.status {
                case .ready:
                    readyCount += 1
                case .recovering:
                    recoveringCount += 1
                    recoveringMuscles.append(muscle.displayName)
                case .tired:
                    tiredCount += 1
                    tiredMuscles.append(muscle.displayName)
                }
            } else {
                // No data = assume ready (never trained)
                readyCount += 1
            }
        }

        let total = templateMuscles.count

        // Calculate score
        let score: Double
        let reason: String

        if tiredCount > 0 {
            // Any tired muscles = low score
            score = 0.2
            reason = "\(tiredMuscles.joined(separator: ", ")) need\(tiredMuscles.count == 1 ? "s" : "") rest"
        } else if recoveringCount > 0 {
            // Some recovering = medium score
            score = 0.5 + (Double(readyCount) / Double(total)) * 0.3
            reason = "\(recoveringMuscles.joined(separator: ", ")) still recovering"
        } else {
            // All ready = high score
            score = 1.0
            reason = "All muscles recovered"
        }

        return (score, reason)
    }

    /// Get the recommended template ID from a plan
    func getRecommendedTemplateId(
        plan: WorkoutPlan,
        modelContext: ModelContext
    ) -> UUID? {
        getBestTemplateForToday(plan: plan, modelContext: modelContext)?.template.id
    }
}
