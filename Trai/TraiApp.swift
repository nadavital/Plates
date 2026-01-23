//
//  TraiApp.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

@main
struct TraiApp: App {
    /// Shared ModelContainer for App Intents and other extension access
    @MainActor static var sharedModelContainer: ModelContainer?

    let modelContainer: ModelContainer
    @State private var notificationService = NotificationService()
    @State private var healthKitService = HealthKitService()
    @State private var notificationDelegate: NotificationDelegate?
    @State private var showRemindersFromNotification = false
    @State private var deepLinkDestination: DeepLinkDestination?

    /// Deep link destinations for URL scheme handling
    enum DeepLinkDestination: Equatable {
        case logFood
        case logWeight
        case workout
        case chat
    }

    init() {
        do {
            let schema = Schema([
                UserProfile.self,
                FoodEntry.self,
                Exercise.self,
                WorkoutSession.self,
                WeightEntry.self,
                ChatMessage.self,
                LiveWorkout.self,
                LiveWorkoutEntry.self,
                ExerciseHistory.self,
                CoachMemory.self,
                NutritionPlanVersion.self,
                CustomReminder.self,
                ReminderCompletion.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            // Set shared container for App Intents access
            let container = modelContainer
            Task { @MainActor in
                TraiApp.sharedModelContainer = container
                migrateExistingWorkoutSets(modelContainer: container)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkDestination: $deepLinkDestination)
                .environment(notificationService)
                .environment(healthKitService)
                .environment(\.showRemindersFromNotification, $showRemindersFromNotification)
                .onAppear {
                    setupNotificationDelegate()
                    // Clean up any stale Live Activities from previous sessions
                    Task { @MainActor in
                        LiveActivityManager.shared.cancelAllActivities()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(modelContainer)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "trai" else { return }

        switch url.host {
        case "logfood":
            deepLinkDestination = .logFood
        case "logweight":
            deepLinkDestination = .logWeight
        case "workout":
            deepLinkDestination = .workout
        case "chat":
            deepLinkDestination = .chat
        default:
            break
        }
    }

    private func setupNotificationDelegate() {
        guard notificationDelegate == nil else { return }
        let delegate = NotificationDelegate(
            modelContainer: modelContainer,
            notificationService: notificationService
        )
        delegate.onShowReminders = {
            showRemindersFromNotification = true
        }
        notificationDelegate = delegate
    }
}

// MARK: - Data Migrations

/// Fix existing completed workouts that have sets with data but not marked as completed
@MainActor
private func migrateExistingWorkoutSets(modelContainer: ModelContainer) {
    let context = modelContainer.mainContext
    let migrationKey = "workout_sets_completion_migration_v1"

    // Check if migration already ran
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }

    // Fetch all completed workouts
    let descriptor = FetchDescriptor<LiveWorkout>(
        predicate: #Predicate { $0.completedAt != nil }
    )

    guard let workouts = try? context.fetch(descriptor) else { return }

    var fixedCount = 0

    for workout in workouts {
        guard let entries = workout.entries else { continue }

        for entry in entries {
            var needsUpdate = false
            var updatedSets: [LiveWorkoutEntry.SetData] = []

            for set in entry.sets {
                if set.reps > 0 && !set.completed {
                    var fixedSet = set
                    fixedSet.completed = true
                    updatedSets.append(fixedSet)
                    needsUpdate = true
                } else {
                    updatedSets.append(set)
                }
            }

            if needsUpdate {
                entry.sets = updatedSets
                fixedCount += 1
            }
        }

        // Also ensure ExerciseHistory exists for this workout
        createMissingExerciseHistory(for: workout, context: context)
    }

    if fixedCount > 0 {
        try? context.save()
        print("Migration: Fixed \(fixedCount) exercise entries with unmarked sets")
    }

    // Mark migration as complete
    UserDefaults.standard.set(true, forKey: migrationKey)
}

/// Create ExerciseHistory entries for completed workouts that are missing them
@MainActor
private func createMissingExerciseHistory(for workout: LiveWorkout, context: ModelContext) {
    guard let entries = workout.entries,
          let completedAt = workout.completedAt else { return }

    // Fetch all existing history and filter in memory
    // (SwiftData predicates don't support captured variables)
    let historyDescriptor = FetchDescriptor<ExerciseHistory>()
    let allHistories = (try? context.fetch(historyDescriptor)) ?? []

    // Find histories around this workout's completion time
    let startTime = completedAt.addingTimeInterval(-60)
    let endTime = completedAt.addingTimeInterval(60)
    let existingExerciseNames = Set(
        allHistories
            .filter { $0.performedAt >= startTime && $0.performedAt <= endTime }
            .map { $0.exerciseName }
    )

    for entry in entries {
        // Check if entry has completed sets
        let completedSets = entry.sets.filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
        guard !completedSets.isEmpty else { continue }

        // Skip if history already exists for this exercise
        guard !existingExerciseNames.contains(entry.exerciseName) else { continue }

        // Create new history entry
        let history = ExerciseHistory(from: entry, performedAt: completedAt)
        context.insert(history)
    }
}
