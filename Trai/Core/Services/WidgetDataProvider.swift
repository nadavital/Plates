//
//  WidgetDataProvider.swift
//  Trai
//
//  Provides fitness data to widgets via App Groups UserDefaults
//

import Foundation
import SwiftData
import WidgetKit

/// Service to sync fitness data to widgets via App Groups UserDefaults.
/// Heavy widget snapshot building runs on a dedicated actor with a fresh ModelContext
/// so food logging and navigation stay responsive.
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let refreshActor = WidgetDataRefreshActor()

    private init() {}

    func scheduleRefresh(
        delay: Duration = .milliseconds(250)
    ) {
        Task { @MainActor in
            guard let modelContainer = TraiApp.sharedModelContainer else { return }
            await refreshActor.scheduleRefresh(modelContainer: modelContainer, delay: delay)
        }
    }

    func scheduleRefresh(
        modelContainer: ModelContainer,
        delay: Duration = .milliseconds(250)
    ) {
        Task {
            await refreshActor.scheduleRefresh(modelContainer: modelContainer, delay: delay)
        }
    }

    nonisolated func readWidgetData() -> WidgetData? {
        Self.readPersistedWidgetData()
    }

    nonisolated fileprivate static func persistWidgetData(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName),
              let jsonData = try? JSONEncoder().encode(data) else {
            return
        }
        defaults.set(jsonData, forKey: SharedStorageKeys.AppGroup.widgetData)
    }

    nonisolated fileprivate static func readPersistedWidgetData() -> WidgetData? {
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName),
              let jsonData = defaults.data(forKey: SharedStorageKeys.AppGroup.widgetData),
              let data = try? JSONDecoder().decode(WidgetData.self, from: jsonData) else {
            return nil
        }
        return data
    }
}

private actor WidgetDataRefreshActor {
    private var pendingRefreshTask: Task<Void, Never>?

    func scheduleRefresh(
        modelContainer: ModelContainer,
        delay: Duration
    ) {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let modelContext = ModelContext(modelContainer)
            let data = WidgetDataSnapshotBuilder().build(modelContext: modelContext)
            WidgetDataProvider.persistWidgetData(data)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private struct WidgetDataSnapshotBuilder {
    private let readyThreshold: Double = 48
    private let recoveringThreshold: Double = 24

    nonisolated func build(modelContext: ModelContext) -> WidgetData {
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profile = (try? modelContext.fetch(profileDescriptor))?.first

        let calorieGoal = profile?.effectiveCalorieGoal ?? 2000
        let proteinGoal = profile?.dailyProteinGoal ?? 150
        let carbsGoal = profile?.dailyCarbsGoal ?? 200
        let fatGoal = profile?.dailyFatGoal ?? 65

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.loggedAt >= startOfDay && entry.loggedAt < endOfDay
            }
        )
        let todayFoods = (try? modelContext.fetch(foodDescriptor)) ?? []

        let caloriesConsumed = todayFoods.reduce(0) { $0 + $1.calories }
        let proteinConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.proteinGrams) }
        let carbsConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.carbsGrams) }
        let fatConsumed = todayFoods.reduce(into: 0) { $0 += Int($1.fatGrams) }

        let recoveryInfo = recoveryStatus(modelContext: modelContext)
        let readyMuscleCount = recoveryInfo.filter { $0.status == .ready }.count

        var recommendedWorkout: String?
        if let workoutPlan = profile?.workoutPlan {
            recommendedWorkout = bestTemplateForToday(
                plan: workoutPlan,
                recoveryInfo: recoveryInfo
            )?.template.name
        }

        let workoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { workout in
                workout.completedAt != nil && workout.completedAt! >= startOfDay
            }
        )
        let todayWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        let todayWorkoutCompleted = !todayWorkouts.isEmpty

        return WidgetData(
            caloriesConsumed: caloriesConsumed,
            calorieGoal: calorieGoal,
            proteinConsumed: proteinConsumed,
            proteinGoal: proteinGoal,
            carbsConsumed: carbsConsumed,
            carbsGoal: carbsGoal,
            fatConsumed: fatConsumed,
            fatGoal: fatGoal,
            readyMuscleCount: readyMuscleCount,
            recommendedWorkout: recommendedWorkout,
            workoutStreak: workoutStreak(modelContext: modelContext),
            todayWorkoutCompleted: todayWorkoutCompleted,
            lastUpdated: Date()
        )
    }

    nonisolated private func recoveryStatus(modelContext: ModelContext) -> [WidgetMuscleRecoveryInfo] {
        let lastTrainedDates = lastTrainedDates(modelContext: modelContext)

        return LiveWorkout.MuscleGroup.allCases
            .filter { $0 != .fullBody }
            .map { muscleGroup in
                let lastTrained = lastTrainedDates[muscleGroup]
                let hoursSince = lastTrained.map { Date().timeIntervalSince($0) / 3600 }
                return WidgetMuscleRecoveryInfo(
                    muscleGroup: muscleGroup,
                    status: recoveryStatus(hoursSinceTraining: hoursSince)
                )
            }
    }

    nonisolated private func lastTrainedDates(modelContext: ModelContext) -> [LiveWorkout.MuscleGroup: Date] {
        var lastTrained: [LiveWorkout.MuscleGroup: Date] = [:]
        let trackedMuscleGroups = Set(LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody })
        let trackedCount = trackedMuscleGroups.count
        let historyWindowStart = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast

        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let exercises = (try? modelContext.fetch(exerciseDescriptor)) ?? []
        let exerciseById: [UUID: String] = Dictionary(uniqueKeysWithValues: exercises.compactMap { exercise in
            guard let muscleGroup = exercise.muscleGroup else { return nil }
            return (exercise.id, muscleGroup)
        })
        let exerciseByName: [String: String] = Dictionary(uniqueKeysWithValues: exercises.compactMap { exercise in
            guard let muscleGroup = exercise.muscleGroup else { return nil }
            return (exercise.name.lowercased(), muscleGroup)
        })

        var workoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { workout in
                workout.completedAt != nil && workout.startedAt >= historyWindowStart
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 320

        if let workouts = try? modelContext.fetch(workoutDescriptor) {
            for workout in workouts {
                guard let entries = workout.entries, !entries.isEmpty else { continue }
                let completionDate = workout.completedAt ?? workout.startedAt

                for entry in entries where entry.sets.contains(where: { $0.completed }) {
                    var muscleGroupString: String?
                    if let exerciseId = entry.exerciseId,
                       let cachedMuscleGroup = exerciseById[exerciseId] {
                        muscleGroupString = cachedMuscleGroup
                    } else if let cachedMuscleGroup = exerciseByName[entry.exerciseName.lowercased()] {
                        muscleGroupString = cachedMuscleGroup
                    }

                    guard let muscleGroupString else { continue }

                    for group in mapExerciseMuscleGroup(muscleGroupString) where lastTrained[group] == nil {
                        lastTrained[group] = completionDate
                    }
                    if lastTrained.count >= trackedCount {
                        return lastTrained
                    }
                }
            }
        }

        var historyDescriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate<ExerciseHistory> { history in
                history.performedAt >= historyWindowStart
            },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        historyDescriptor.fetchLimit = 420

        if let histories = try? modelContext.fetch(historyDescriptor) {
            for history in histories {
                let muscleGroupString: String?
                if let exerciseId = history.exerciseId {
                    muscleGroupString = exerciseById[exerciseId]
                } else {
                    muscleGroupString = exerciseByName[history.exerciseName.lowercased()]
                }

                guard let muscleGroupString else { continue }

                for muscleGroup in mapExerciseMuscleGroup(muscleGroupString) where lastTrained[muscleGroup] == nil {
                    lastTrained[muscleGroup] = history.performedAt
                }
                if lastTrained.count >= trackedCount {
                    break
                }
            }
        }

        return lastTrained
    }

    nonisolated private func mapExerciseMuscleGroup(_ muscleGroup: String) -> [LiveWorkout.MuscleGroup] {
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

    nonisolated private func recoveryStatus(hoursSinceTraining: Double?) -> WidgetRecoveryStatus {
        guard let hours = hoursSinceTraining else { return .ready }

        if hours >= readyThreshold {
            return .ready
        } else if hours >= recoveringThreshold {
            return .recovering
        } else {
            return .tired
        }
    }

    nonisolated private func bestTemplateForToday(
        plan: WorkoutPlan,
        recoveryInfo: [WidgetMuscleRecoveryInfo]
    ) -> (template: WorkoutPlan.WorkoutTemplate, score: Double, reason: String)? {
        guard !plan.templates.isEmpty else { return nil }

        var bestTemplate: WorkoutPlan.WorkoutTemplate?
        var bestScore = -1.0
        var bestReason = ""

        for template in plan.templates {
            let result = scoreTemplate(template, recoveryInfo: recoveryInfo)
            if result.score > bestScore {
                bestTemplate = template
                bestScore = result.score
                bestReason = result.reason
            }
        }

        guard let bestTemplate else { return nil }
        return (bestTemplate, bestScore, bestReason)
    }

    nonisolated private func scoreTemplate(
        _ template: WorkoutPlan.WorkoutTemplate,
        recoveryInfo: [WidgetMuscleRecoveryInfo]
    ) -> (score: Double, reason: String) {
        let templateMuscles = LiveWorkout.MuscleGroup.fromTargetStrings(template.targetMuscleGroups)

        guard !templateMuscles.isEmpty else {
            return (0.5, "Unknown muscle groups")
        }

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
                readyCount += 1
            }
        }

        let total = templateMuscles.count

        if tiredCount > 0 {
            return (
                0.2,
                "\(tiredMuscles.joined(separator: ", ")) need\(tiredMuscles.count == 1 ? "s" : "") rest"
            )
        }

        if recoveringCount > 0 {
            return (
                0.5 + (Double(readyCount) / Double(total)) * 0.3,
                "\(recoveringMuscles.joined(separator: ", ")) still recovering"
            )
        }

        return (1.0, "All muscles recovered")
    }

    nonisolated private func workoutStreak(modelContext: ModelContext) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliestDate = calendar.date(byAdding: .day, value: -365, to: today) ?? today
        var descriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { workout in
                workout.completedAt != nil && workout.completedAt! >= earliestDate
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 2000

        let workouts = (try? modelContext.fetch(descriptor)) ?? []
        let workoutDays = Set(workouts.compactMap { workout -> Date? in
            guard let completedAt = workout.completedAt else { return nil }
            return calendar.startOfDay(for: completedAt)
        })

        var streak = 0
        var consecutiveRestDays = 0
        var currentDate = today

        for dayOffset in 0..<365 {
            if dayOffset > 0 {
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
                currentDate = previousDay
            }

            if workoutDays.contains(currentDate) {
                streak += 1
                consecutiveRestDays = 0
                continue
            }

            consecutiveRestDays += 1
            if streak == 0 {
                if currentDate != today {
                    break
                }
                continue
            }

            if consecutiveRestDays >= 2 {
                break
            }
        }

        return streak
    }
}

private enum WidgetRecoveryStatus {
    case ready
    case recovering
    case tired
}

private struct WidgetMuscleRecoveryInfo {
    let muscleGroup: LiveWorkout.MuscleGroup
    let status: WidgetRecoveryStatus
}
