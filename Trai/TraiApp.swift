//
//  TraiApp.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData
import WidgetKit

@main
struct TraiApp: App {
    /// Shared ModelContainer for App Intents and other extension access
    @MainActor static var sharedModelContainer: ModelContainer?

    let modelContainer: ModelContainer
    @State private var notificationService = NotificationService()
    @State private var healthKitService = HealthKitService()
    @State private var notificationDelegate: NotificationDelegate?
    @State private var showRemindersFromNotification = false
    @State private var deepLinkDestination: AppRoute?
    @State private var lastHealthKitWorkoutSyncDate: Date?
    @Environment(\.scenePhase) private var scenePhase

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
                CoachSignal.self,
                NutritionPlanVersion.self,
                WorkoutPlanVersion.self,
                CustomReminder.self,
                ReminderCompletion.self,
                SuggestionUsage.self
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
                    // Process any pending widget food logs
                    processPendingWidgetFoodLogs()
                    // Update widget data on launch
                    Task { @MainActor in
                        WidgetDataProvider.shared.updateWidgetData(modelContext: modelContainer.mainContext)
                    }
                    Task { @MainActor in
                        await syncRecentWorkoutsFromHealthKit()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Update widget data when app goes to background
                Task { @MainActor in
                    WidgetDataProvider.shared.updateWidgetData(modelContext: modelContainer.mainContext)
                }
            } else if newPhase == .active {
                Task { @MainActor in
                    await syncRecentWorkoutsFromHealthKit()
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        deepLinkDestination = route
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

    @MainActor
    private func syncRecentWorkoutsFromHealthKit() async {
        let now = Date()

        // Debounce repeated syncs while app is already open and active.
        if let lastSync = lastHealthKitWorkoutSyncDate, now.timeIntervalSince(lastSync) < 60 {
            return
        }

        do {
            let context = modelContainer.mainContext
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            let healthKitWorkouts = try await healthKitService.fetchWorkoutsAuthorized(from: oneMonthAgo, to: now)

            let workoutDescriptor = FetchDescriptor<WorkoutSession>()
            let existingWorkouts = (try? context.fetch(workoutDescriptor)) ?? []
            let existingIDs = Set(existingWorkouts.compactMap { $0.healthKitWorkoutID })
            let newWorkouts = healthKitWorkouts.filter { !existingIDs.contains($0.healthKitWorkoutID ?? "") }

            for workout in newWorkouts {
                context.insert(workout)
            }
            if !newWorkouts.isEmpty {
                try? context.save()
            }

            let liveDescriptor = FetchDescriptor<LiveWorkout>(predicate: #Predicate { $0.completedAt != nil })
            let completedLiveWorkouts = (try? context.fetch(liveDescriptor)) ?? []

            var didMerge = false
            for workout in completedLiveWorkouts where workout.mergedHealthKitWorkoutID == nil {
                if let match = healthKitService.bestOverlappingWorkout(for: workout, from: healthKitWorkouts, searchBufferMinutes: 15) {
                    workout.mergedHealthKitWorkoutID = match.healthKitWorkoutID
                    if let calories = match.caloriesBurned {
                        workout.healthKitCalories = Double(calories)
                    }
                    if let avgHR = match.averageHeartRate {
                        workout.healthKitAvgHeartRate = Double(avgHR)
                    }
                    didMerge = true
                }
            }

            if didMerge {
                try? context.save()
            }

            lastHealthKitWorkoutSyncDate = now
        } catch {
            // Handle silently to avoid blocking app startup.
        }
    }
}

// MARK: - Widget Food Log Processing

extension TraiApp {
    /// Process any pending food logs from widget quick actions
    @MainActor
    func processPendingWidgetFoodLogs() {
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName),
              let pendingData = defaults.data(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs),
              let pendingLogs = try? JSONDecoder().decode([PendingFoodLog].self, from: pendingData),
              !pendingLogs.isEmpty else {
            return
        }

        let context = modelContainer.mainContext

        for log in pendingLogs {
            let entry = FoodEntry()
            entry.name = log.name
            entry.calories = log.calories
            entry.proteinGrams = Double(log.protein)
            entry.loggedAt = log.loggedAt
            entry.mealType = log.mealType
            context.insert(entry)
        }

        try? context.save()

        // Clear pending logs
        defaults.removeObject(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs)

        // Refresh widgets with new data
        WidgetDataProvider.shared.updateWidgetData(modelContext: context)
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
