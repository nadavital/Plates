//
//  TraiApp.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData
import WidgetKit
import BackgroundTasks
import UIKit

@main
struct TraiApp: App {
    /// Shared ModelContainer for App Intents and other extension access
    @MainActor static var sharedModelContainer: ModelContainer?
    @UIApplicationDelegateAdaptor(HomeScreenQuickActionApplicationDelegate.self)
    private var quickActionDelegate

    let isUITesting: Bool
    let isRunningTests: Bool
    let modelContainer: ModelContainer
    @State private var notificationService: NotificationService
    @State private var healthKitService: HealthKitService
    @State private var notificationDelegate: NotificationDelegate?
    @State private var showRemindersFromNotification = false
    @State private var deepLinkDestination: AppRoute?
    @State private var lastHealthKitWorkoutSyncDate: Date?
    @AppStorage("healthkitRecentWorkoutSyncTimestamp")
    private var persistedHealthKitWorkoutSyncTimestamp: Double = 0
    @AppStorage("reminderScheduleRefreshToken")
    private var reminderScheduleRefreshToken: String = ""
    @State private var startupCoordinator = AppStartupCoordinator()
    @State private var deferredHealthKitSyncTask: Task<Void, Never>?
    @State private var reminderScheduleRefreshTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    private let startupTaskDeferral: Duration = .seconds(2)
    private let startupMigrationDeferral: Duration = .seconds(90)
    private let foregroundHealthKitSyncDelay: Duration = .seconds(35)
    private let reminderBackgroundRefreshInterval: TimeInterval = 12 * 60 * 60
    private let minimumHealthKitSyncInterval: TimeInterval = 6 * 60 * 60
    private let initialHealthKitSyncLookbackDays = 30
    private let incrementalHealthKitSyncLookbackDays = 10
    private let brandAccent = Color("AccentColor")
    private static let swiftDataStoreFilename = "default.store"
    private static let reminderBackgroundRefreshTaskIdentifier = "Nadav.Trai.reminder-refresh"

    init() {
        let notificationService = NotificationService()
        let healthKitService = HealthKitService()
        _notificationService = State(initialValue: notificationService)
        _healthKitService = State(initialValue: healthKitService)

        let isUITesting = AppLaunchArguments.isUITesting
        let isRunningTests = AppLaunchArguments.isRunningTests
        let shouldUseInMemoryStore = AppLaunchArguments.shouldUseInMemoryStore
        self.isUITesting = isUITesting
        self.isRunningTests = isRunningTests

        do {
            Self.primeSharedStoreDirectoryIfNeeded(usesInMemoryStore: shouldUseInMemoryStore)
            Self.migrateLegacyStoreToSharedContainerIfNeeded(usesInMemoryStore: shouldUseInMemoryStore)

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
                SuggestionUsage.self,
                BehaviorEvent.self
            ])

            let modelConfiguration: ModelConfiguration
            if shouldUseInMemoryStore {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            } else {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    groupContainer: .identifier(SharedStorageKeys.AppGroup.suiteName),
                    cloudKitDatabase: .automatic
                )
            }

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            notificationService.ensureNotificationSetup()
            let delegate = NotificationDelegate(
                modelContainer: modelContainer,
                notificationService: notificationService
            )
            _notificationDelegate = State(initialValue: delegate)

            // Set shared container for App Intents access
            let container = modelContainer
            Task { @MainActor in
                TraiApp.sharedModelContainer = container
                if isUITesting {
                    seedUITestProfileIfNeeded(modelContainer: container)
                }
                if AppLaunchArguments.shouldSeedLiveWorkoutPerfData {
                    seedLiveWorkoutPerformanceDataIfNeeded(modelContainer: container)
                } else {
                    purgeLiveWorkoutPerformanceSeedDataIfPresent(modelContainer: container)
                }
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                ContentView(deepLinkDestination: $deepLinkDestination)
                    .tint(brandAccent)
                    .accentColor(brandAccent)
                    .environment(notificationService)
                    .environment(\.showRemindersFromNotification, $showRemindersFromNotification)
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            } else {
                ContentView(deepLinkDestination: $deepLinkDestination)
                    .tint(brandAccent)
                    .accentColor(brandAccent)
                    .environment(notificationService)
                    .environment(healthKitService)
                    .environment(\.showRemindersFromNotification, $showRemindersFromNotification)
                    .onAppear {
                        PerformanceTrace.event("app_window_appear", category: .launch)
                        setupNotificationDelegate()
                        scheduleDeferredStartupTasksIfNeeded()
                        scheduleStartupMigrationIfNeeded()
                        scheduleReminderScheduleRefreshIfNeeded()
                        scheduleReminderBackgroundRefresh()
                    }
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard !isRunningTests else { return }

            if newPhase == .background {
                deferredHealthKitSyncTask?.cancel()
                reminderScheduleRefreshTask?.cancel()
                NotificationCenter.default.post(name: .liveWorkoutForceFlush, object: nil)
                // Update widget data when app goes to background
                Task { @MainActor in
                    guard !hasActiveLiveWorkoutInProgress() else { return }
                    WidgetDataProvider.shared.updateWidgetData(modelContext: modelContainer.mainContext)
                }
            } else if newPhase == .active {
                scheduleForegroundHealthKitSyncIfEligible()
                scheduleReminderScheduleRefreshIfNeeded()
                scheduleReminderBackgroundRefresh()
            }
        }
        .backgroundTask(.appRefresh(Self.reminderBackgroundRefreshTaskIdentifier)) {
            await handleReminderBackgroundRefresh()
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        deepLinkDestination = route
    }

    private func setupNotificationDelegate() {
        notificationService.ensureNotificationSetup()

        if notificationDelegate == nil {
            notificationDelegate = NotificationDelegate(
                modelContainer: modelContainer,
                notificationService: notificationService
            )
        }

        notificationDelegate?.onShowReminders = {
            showRemindersFromNotification = true
        }
    }

    @MainActor
    private func scheduleReminderScheduleRefreshIfNeeded(force: Bool = false) {
        reminderScheduleRefreshTask?.cancel()
        reminderScheduleRefreshTask = Task(priority: .utility) { @MainActor in
            await refreshReminderSchedulesIfNeeded(force: force)
        }
    }

    private func scheduleReminderBackgroundRefresh() {
        guard !isRunningTests else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.reminderBackgroundRefreshTaskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.reminderBackgroundRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: reminderBackgroundRefreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule reminder background refresh: \(error)")
        }
    }

    @MainActor
    private func handleReminderBackgroundRefresh() async {
        await refreshReminderSchedulesIfNeeded(force: true)
        scheduleReminderBackgroundRefresh()
    }

    @MainActor
    private func refreshReminderSchedulesIfNeeded(force: Bool) async {
        let todayToken = NotificationService.occurrenceDateToken(for: Date())
        if !force, reminderScheduleRefreshToken == todayToken {
            return
        }

        await notificationService.updateAuthorizationStatus()
        guard notificationService.isAuthorized else { return }

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        guard let profile = try? modelContainer.mainContext.fetch(profileDescriptor).first else { return }

        let customReminderDescriptor = FetchDescriptor<CustomReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let customReminders = (try? modelContainer.mainContext.fetch(customReminderDescriptor)) ?? []

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let completionDescriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { completion in
                completion.completedAt >= startOfDay
            }
        )
        let completions = (try? modelContainer.mainContext.fetch(completionDescriptor)) ?? []
        let completedTodayReminderIDs = Set(completions.map(\.reminderId))

        if profile.mealRemindersEnabled {
            let enabledMeals = Set(profile.enabledMealReminders.split(separator: ",").map(String.init))
            let mealTimes = MealReminderTime.allMeals.filter { enabledMeals.contains($0.id) }
            await notificationService.scheduleMealReminders(
                times: mealTimes,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await notificationService.cancelNotifications(category: .mealReminder)
        }

        if profile.workoutRemindersEnabled {
            let workoutDays = Set(profile.workoutReminderDays.split(separator: ",").compactMap { Int($0) })
            await notificationService.scheduleWorkoutReminders(
                days: workoutDays.sorted(),
                hour: profile.workoutReminderHour,
                minute: profile.workoutReminderMinute,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await notificationService.cancelNotifications(category: .workoutReminder)
        }

        if profile.weightReminderEnabled {
            await notificationService.scheduleWeightReminder(
                weekday: profile.weightReminderWeekday,
                hour: profile.weightReminderHour,
                minute: 0,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await notificationService.cancelNotifications(category: .weightReminder)
        }

        await notificationService.scheduleAllCustomReminders(
            customReminders,
            skippingTodayReminderIDs: completedTodayReminderIDs
        )
        reminderScheduleRefreshToken = todayToken
        scheduleReminderBackgroundRefresh()
    }

    @MainActor
    private func scheduleDeferredStartupTasksIfNeeded() {
        guard startupCoordinator.claimDeferredStartupWork() else { return }

        Task(priority: .utility) {
            try? await Task.sleep(for: startupTaskDeferral)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let interval = PerformanceTrace.begin("startup_deferral", category: .launch)
                // Keep non-critical cleanup and widget persistence off the first-frame path.
                LiveActivityManager.shared.cancelAllActivities()
                processPendingWidgetFoodLogs()
                startupCoordinator.markDeferredStartupWorkCompleted()
                PerformanceTrace.event("startup_deferral_completed", category: .launch)
                PerformanceTrace.end("startup_deferral", interval, category: .launch)
            }
        }
    }

    @MainActor
    private func scheduleStartupMigrationIfNeeded() {
        guard startupCoordinator.claimStartupMigration() else { return }

        Task(priority: .utility) {
            // Keep migration work well off the critical startup + early interaction window.
            try? await Task.sleep(for: startupMigrationDeferral)
            guard !Task.isCancelled else { return }
            await runStartupMigrationWhenIdle()
        }
    }

    @MainActor
    private func runStartupMigrationWhenIdle(maxAttempts: Int = 8) async {
        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return }
            if !hasActiveLiveWorkoutInProgress() {
                let interval = PerformanceTrace.begin("startup_migration", category: .dataLoad)
                await migrateExistingWorkoutSets(modelContainer: modelContainer)
                await migrateLegacyCloudImagesAndBackfillFoodEmoji(modelContainer: modelContainer)
                PerformanceTrace.end("startup_migration", interval, category: .dataLoad)
                return
            }

            let retryDelay: Duration = attempt < 3 ? .seconds(45) : .seconds(90)
            try? await Task.sleep(for: retryDelay)
        }
    }

    @MainActor
    private func scheduleForegroundHealthKitSyncIfEligible() {
        deferredHealthKitSyncTask?.cancel()
        deferredHealthKitSyncTask = Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: foregroundHealthKitSyncDelay)
            guard !Task.isCancelled else { return }
            guard scenePhase == .active else { return }
            let hasActiveWorkout = hasActiveLiveWorkoutInProgress()
            guard startupCoordinator.shouldScheduleForegroundHealthKitSync(
                hasActiveWorkoutInProgress: hasActiveWorkout
            ) else { return }
            await syncRecentWorkoutsFromHealthKit()
        }
    }

    @MainActor
    private func hasActiveLiveWorkoutInProgress() -> Bool {
        var descriptor = FetchDescriptor<LiveWorkout>(predicate: #Predicate { $0.completedAt == nil })
        descriptor.fetchLimit = 1
        let active = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return !active.isEmpty
    }

    @MainActor
    private func syncRecentWorkoutsFromHealthKit() async {
        let interval = PerformanceTrace.begin("healthkit_recent_sync", category: .dataLoad)
        defer { PerformanceTrace.end("healthkit_recent_sync", interval, category: .dataLoad) }

        let now = Date()
        let persistedLastSync: Date? = {
            guard persistedHealthKitWorkoutSyncTimestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: persistedHealthKitWorkoutSyncTimestamp)
        }()
        let effectiveLastSync = lastHealthKitWorkoutSyncDate ?? persistedLastSync

        // Persisted debounce keeps launch-time sync from re-running every app open.
        if let lastSync = effectiveLastSync, now.timeIntervalSince(lastSync) < minimumHealthKitSyncInterval {
            return
        }

        do {
            let context = modelContainer.mainContext
            let lookbackDays = effectiveLastSync == nil
                ? initialHealthKitSyncLookbackDays
                : incrementalHealthKitSyncLookbackDays
            let syncStart = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
            let healthKitWorkouts = try await healthKitService.fetchWorkoutsAuthorized(from: syncStart, to: now)
            guard !hasActiveLiveWorkoutInProgress() else { return }
            guard !healthKitWorkouts.isEmpty else {
                // Avoid long import backoff when the sample window is empty.
                return
            }

            let workoutDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate<WorkoutSession> { workout in
                    workout.loggedAt >= syncStart && workout.healthKitWorkoutID != nil
                }
            )
            let existingWorkouts = (try? context.fetch(workoutDescriptor)) ?? []
            let existingIDs = Set(existingWorkouts.compactMap { $0.healthKitWorkoutID })
            let newWorkouts = healthKitWorkouts.filter { !existingIDs.contains($0.healthKitWorkoutID ?? "") }

            for workout in newWorkouts {
                context.insert(workout)
            }
            if !newWorkouts.isEmpty {
                try? context.save()
            }

            let mergeSearchStart = Calendar.current.date(
                byAdding: .day,
                value: -(lookbackDays + 14),
                to: now
            ) ?? syncStart
            let liveDescriptor = FetchDescriptor<LiveWorkout>(
                predicate: #Predicate<LiveWorkout> { workout in
                    workout.completedAt != nil &&
                    workout.mergedHealthKitWorkoutID == nil &&
                    workout.startedAt >= mergeSearchStart
                }
            )
            let completedLiveWorkouts = (try? context.fetch(liveDescriptor)) ?? []

            var didMerge = false
            for workout in completedLiveWorkouts {
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
            persistedHealthKitWorkoutSyncTimestamp = now.timeIntervalSince1970
            PerformanceTrace.event("healthkit_recent_sync_completed", category: .dataLoad)
        } catch {
            // Handle silently to avoid blocking app startup.
        }
    }

    private static func primeSharedStoreDirectoryIfNeeded(usesInMemoryStore: Bool) {
        guard !usesInMemoryStore else { return }
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStorageKeys.AppGroup.suiteName
        ) else {
            return
        }

        let appSupportURL = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }

    private static func migrateLegacyStoreToSharedContainerIfNeeded(usesInMemoryStore: Bool) {
        guard !usesInMemoryStore else { return }

        let fileManager = FileManager.default
        guard let sharedContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStorageKeys.AppGroup.suiteName
        ) else {
            return
        }
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let sharedAppSupportURL = sharedContainerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: sharedAppSupportURL,
            withIntermediateDirectories: true
        )

        guard let legacyFiles = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let legacyStoreFiles = legacyFiles.filter {
            $0.lastPathComponent.hasPrefix(swiftDataStoreFilename)
        }
        guard !legacyStoreFiles.isEmpty else { return }

        let sharedStoreURL = sharedAppSupportURL.appendingPathComponent(swiftDataStoreFilename)
        guard !fileManager.fileExists(atPath: sharedStoreURL.path) else {
            return
        }

        for sourceURL in legacyStoreFiles {
            let destinationURL = sharedAppSupportURL.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
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
            entry.emoji = FoodEmojiResolver.resolve(preferred: nil, foodName: log.name)
            entry.ensureDisplayMetadata()
            context.insert(entry)
            BehaviorTracker(modelContext: context).record(
                actionKey: BehaviorActionKey.logFood,
                domain: .nutrition,
                surface: .widget,
                outcome: .completed,
                relatedEntityId: entry.id,
                metadata: [
                    "source": "widget_pending",
                    "name": log.name
                ],
                saveImmediately: false
            )
        }

        try? context.save()

        // Clear pending logs
        defaults.removeObject(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs)

        // Refresh widgets with new data
        WidgetDataProvider.shared.updateWidgetData(modelContext: context)
    }
}

private enum HomeScreenQuickAction: String, CaseIterable {
    case logFood = "Nadav.Trai.quickaction.logFood"
    case logWeight = "Nadav.Trai.quickaction.logWeight"
    case workout = "Nadav.Trai.quickaction.workout"
    case chat = "Nadav.Trai.quickaction.chat"

    var title: String {
        switch self {
        case .logFood:
            return "Log Food"
        case .logWeight:
            return "Log Weight"
        case .workout:
            return "Start Workout"
        case .chat:
            return "Trai"
        }
    }

    var systemImageName: String {
        switch self {
        case .logFood:
            return "fork.knife"
        case .logWeight:
            return "scalemass.fill"
        case .workout:
            return "figure.run"
        case .chat:
            return "circle.hexagongrid.circle"
        }
    }

    var route: AppRoute {
        switch self {
        case .logFood:
            return .logFood
        case .logWeight:
            return .logWeight
        case .workout:
            return .workout(templateName: nil)
        case .chat:
            return .chat
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: nil
        )
    }

    @MainActor
    static func registerAll() {
        UIApplication.shared.shortcutItems = allCases.map(\.shortcutItem)
    }

    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = Self(rawValue: shortcutItem.type) else { return false }
        PendingAppRouteStore.setPendingRoute(action.route)
        return true
    }
}

private final class HomeScreenQuickActionApplicationDelegate: NSObject, UIApplicationDelegate {
    @MainActor
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HomeScreenQuickAction.registerAll()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = HomeScreenQuickActionSceneDelegate.self
        return configuration
    }
}

private final class HomeScreenQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = HomeScreenQuickAction.handle(shortcutItem)
        }
    }

    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        HomeScreenQuickAction.registerAll()
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(HomeScreenQuickAction.handle(shortcutItem))
    }
}

// MARK: - Data Migrations

@MainActor
private func seedUITestProfileIfNeeded(modelContainer: ModelContainer) {
    let context = modelContainer.mainContext
    var completedProfileDescriptor = FetchDescriptor<UserProfile>(
        predicate: #Predicate<UserProfile> { $0.hasCompletedOnboarding == true }
    )
    completedProfileDescriptor.fetchLimit = 1
    let hasCompletedProfile = ((try? context.fetch(completedProfileDescriptor)) ?? []).isEmpty == false
    guard !hasCompletedProfile else { return }

    var anyProfileDescriptor = FetchDescriptor<UserProfile>()
    anyProfileDescriptor.fetchLimit = 1
    if let existingProfile = ((try? context.fetch(anyProfileDescriptor)) ?? []).first {
        existingProfile.hasCompletedOnboarding = true
        if existingProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            existingProfile.name = "UI Test User"
        }
        try? context.save()
        return
    }

    let profile = UserProfile()
    profile.name = "UI Test User"
    profile.hasCompletedOnboarding = true
    context.insert(profile)
    try? context.save()
}

@MainActor
private func seedLiveWorkoutPerformanceDataIfNeeded(modelContainer: ModelContainer) {
    let seeder = LiveWorkoutPerformanceDataSeeder()
    let context = modelContainer.mainContext
    do {
        let summary = try seeder.seed(
            modelContext: context,
            configuration: .defaultHeavyDeviceProfile
        )
        print(
            "Perf seed complete (\(summary.runIdentifier)): " +
            "\(summary.totalWorkoutsInserted) workouts, " +
            "\(summary.totalEntriesInserted) entries, " +
            "\(summary.totalSetsInserted) sets"
        )
    } catch {
        print("Perf seed failed: \(error.localizedDescription)")
    }
}

@MainActor
private func purgeLiveWorkoutPerformanceSeedDataIfPresent(modelContainer: ModelContainer) {
    let seedMarkerPrefix = "[PerfSeed:"
    let context = modelContainer.mainContext

    do {
        let workoutDescriptor = FetchDescriptor<LiveWorkout>()
        let allWorkouts = try context.fetch(workoutDescriptor)
        let seededWorkouts = allWorkouts.filter { $0.notes.contains(seedMarkerPrefix) }
        guard !seededWorkouts.isEmpty else { return }

        var seededEntryIDs: Set<UUID> = []
        seededEntryIDs.reserveCapacity(seededWorkouts.count * 6)

        for workout in seededWorkouts {
            for entry in workout.entries ?? [] {
                seededEntryIDs.insert(entry.id)
            }
            context.delete(workout)
        }

        var deletedHistoryCount = 0
        if !seededEntryIDs.isEmpty {
            let historyDescriptor = FetchDescriptor<ExerciseHistory>()
            let allHistory = try context.fetch(historyDescriptor)
            for history in allHistory {
                guard let sourceWorkoutEntryId = history.sourceWorkoutEntryId else { continue }
                if seededEntryIDs.contains(sourceWorkoutEntryId) {
                    context.delete(history)
                    deletedHistoryCount += 1
                }
            }
        }

        try context.save()
        print(
            "Purged perf seed data: \(seededWorkouts.count) workouts, " +
            "\(deletedHistoryCount) history entries"
        )
    } catch {
        print("Perf seed cleanup failed: \(error.localizedDescription)")
    }
}

/// Fix existing completed workouts that have sets with data but not marked as completed
@MainActor
private func migrateExistingWorkoutSets(modelContainer: ModelContainer) async {
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
    var insertedHistoryCount = 0
    let historyDescriptor = FetchDescriptor<ExerciseHistory>()
    let existingHistories = (try? context.fetch(historyDescriptor)) ?? []
    var historyDatesByExercise: [String: [Date]] = Dictionary(
        grouping: existingHistories,
        by: \.exerciseName
    ).mapValues { histories in
        histories.map(\.performedAt).sorted()
    }

    for (index, workout) in workouts.enumerated() {
        guard let entries = workout.entries else { continue }
        let completedAt = workout.completedAt

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
            guard let completedAt else { continue }

            // Ensure ExerciseHistory exists for this entry around workout completion.
            let completedSets = entry.sets.filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
            guard !completedSets.isEmpty else { continue }

            let existingDates = historyDatesByExercise[entry.exerciseName] ?? []
            guard !hasDateInWindow(existingDates, around: completedAt) else { continue }

            let history = ExerciseHistory(from: entry, performedAt: completedAt)
            context.insert(history)
            insertedHistoryCount += 1
            historyDatesByExercise[entry.exerciseName] = insertingSortedDate(completedAt, into: existingDates)
        }

        if index.isMultiple(of: 20) {
            await Task.yield()
        }
    }

    if fixedCount > 0 || insertedHistoryCount > 0 {
        try? context.save()
    }

    if fixedCount > 0 {
        print("Migration: Fixed \(fixedCount) exercise entries with unmarked sets")
    }
    if insertedHistoryCount > 0 {
        print("Migration: Inserted \(insertedHistoryCount) missing exercise history entries")
    }

    // Mark migration as complete
    UserDefaults.standard.set(true, forKey: migrationKey)
}

/// Move legacy CloudKit-backed image blobs to local-only file storage and backfill food emojis.
@MainActor
private func migrateLegacyCloudImagesAndBackfillFoodEmoji(modelContainer: ModelContainer) async {
    let context = modelContainer.mainContext
    let migrationKey = "local_image_storage_migration_v1"

    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }

    var migratedFoodImages = 0
    var backfilledFoodEmoji = 0
    var migratedChatImages = 0

    let foodDescriptor = FetchDescriptor<FoodEntry>()
    if let foodEntries = try? context.fetch(foodDescriptor) {
        for (index, entry) in foodEntries.enumerated() {
            if entry.migrateLegacyImageToLocalStoreIfNeeded() {
                migratedFoodImages += 1
            }

            let previousEmoji = entry.emoji
            entry.ensureDisplayMetadata()
            if previousEmoji != entry.emoji {
                backfilledFoodEmoji += 1
            }

            if index.isMultiple(of: 40) {
                await Task.yield()
            }
        }
    }

    let chatDescriptor = FetchDescriptor<ChatMessage>()
    if let chatMessages = try? context.fetch(chatDescriptor) {
        for (index, message) in chatMessages.enumerated() {
            if message.migrateLegacyImageToLocalStoreIfNeeded() {
                migratedChatImages += 1
            }
            if index.isMultiple(of: 80) {
                await Task.yield()
            }
        }
    }

    if migratedFoodImages > 0 || backfilledFoodEmoji > 0 || migratedChatImages > 0 {
        try? context.save()
    }

    if migratedFoodImages > 0 {
        print("Migration: Moved \(migratedFoodImages) food images to local-only storage")
    }
    if backfilledFoodEmoji > 0 {
        print("Migration: Backfilled emoji for \(backfilledFoodEmoji) food entries")
    }
    if migratedChatImages > 0 {
        print("Migration: Moved \(migratedChatImages) chat images to local-only storage")
    }

    UserDefaults.standard.set(true, forKey: migrationKey)
}

private func hasDateInWindow(_ dates: [Date], around target: Date, tolerance: TimeInterval = 60) -> Bool {
    guard !dates.isEmpty else { return false }

    let lowerBound = target.addingTimeInterval(-tolerance)
    let upperBound = target.addingTimeInterval(tolerance)
    let startIndex = lowerBoundIndex(for: lowerBound, in: dates)
    guard startIndex < dates.count else { return false }
    return dates[startIndex] <= upperBound
}

private func lowerBoundIndex(for value: Date, in dates: [Date]) -> Int {
    var lower = 0
    var upper = dates.count

    while lower < upper {
        let mid = (lower + upper) / 2
        if dates[mid] < value {
            lower = mid + 1
        } else {
            upper = mid
        }
    }

    return lower
}

private func insertingSortedDate(_ value: Date, into dates: [Date]) -> [Date] {
    var updated = dates
    let insertIndex = lowerBoundIndex(for: value, in: updated)
    updated.insert(value, at: insertIndex)
    return updated
}
