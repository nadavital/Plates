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
    @State private var appAccountService: AppAccountService
    @State private var accountSessionService: AccountSessionService
    @State private var monetizationService: MonetizationService
    @State private var billingService: BillingService
    @State private var proUpsellCoordinator: ProUpsellCoordinator
    @State private var notificationDelegate: NotificationDelegate?
    @State private var showRemindersFromNotification = false
    @State private var deepLinkDestination: AppRoute?
    @State private var lastHealthKitWorkoutSyncDate: Date?
    @AppStorage("healthkitRecentWorkoutSyncTimestamp")
    private var persistedHealthKitWorkoutSyncTimestamp: Double = 0
    @AppStorage("foodMemoryLaunchMaintenanceTimestamp")
    private var persistedFoodMemoryLaunchMaintenanceTimestamp: Double = 0
    @AppStorage("reminderScheduleRefreshToken")
    private var reminderScheduleRefreshToken: String = ""
    @State private var startupCoordinator = AppStartupCoordinator()
    @State private var deferredHealthKitSyncTask: Task<Void, Never>?
    @State private var reminderScheduleRefreshTask: Task<Void, Never>?
    #if DEBUG
    @State private var hasRunLaunchReplayEvaluation = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    private let startupTaskDeferral: Duration = .seconds(2)
    private let startupMigrationDeferral: Duration = .seconds(90)
    private let foodMemoryMaintenanceDeferral: Duration = .seconds(30)
    private let foregroundHealthKitSyncDelay: Duration = .seconds(35)
    private let reminderBackgroundRefreshInterval: TimeInterval = 12 * 60 * 60
    private let foodMemoryLaunchMaintenanceInterval: TimeInterval = 12 * 60 * 60
    private let minimumHealthKitSyncInterval: TimeInterval = 6 * 60 * 60
    private let initialHealthKitSyncLookbackDays = 30
    private let incrementalHealthKitSyncLookbackDays = 10
    private let brandAccent = Color("AccentColor")
    private static let swiftDataStoreFilename = "default.store"
    private static let reminderBackgroundRefreshTaskIdentifier = "Nadav.Trai.reminder-refresh"

    init() {
        let notificationService = NotificationService()
        let healthKitService = HealthKitService()
        let appAccountService = AppAccountService.shared
        let accountSessionService = AccountSessionService.shared
        let monetizationService = MonetizationService.shared
        let billingService = BillingService.shared
        let proUpsellCoordinator = ProUpsellCoordinator.shared
        _notificationService = State(initialValue: notificationService)
        _healthKitService = State(initialValue: healthKitService)
        _appAccountService = State(initialValue: appAccountService)
        _accountSessionService = State(initialValue: accountSessionService)
        _monetizationService = State(initialValue: monetizationService)
        _billingService = State(initialValue: billingService)
        _proUpsellCoordinator = State(initialValue: proUpsellCoordinator)

        let isUITesting = AppLaunchArguments.isUITesting
        let isRunningTests = AppLaunchArguments.isRunningTests
        let shouldUseInMemoryStore = AppLaunchArguments.shouldUseInMemoryStore
        let launchPendingRoute = AppLaunchArguments.launchPendingRoute
        self.isUITesting = isUITesting
        self.isRunningTests = isRunningTests
        _deepLinkDestination = State(initialValue: launchPendingRoute)

        #if DEBUG
        if isUITesting {
            if AppLaunchArguments.shouldRunOnboardingFlowUITest {
                UserDefaults.standard.set(false, forKey: AppLaunchArguments.onboardingCompletedCacheKey)
                UserDefaults.standard.removeObject(forKey: "onboardingDraft")
            }
            if AppLaunchArguments.shouldUseLiveAIBackendForUITest {
                appAccountService.setDebugBackendEnvironment(.localDevelopment)
            }
            if AppLaunchArguments.shouldUseFreePlanForUITest {
                monetizationService.setDebugPlan(.free)
                accountSessionService.signOut()
            } else {
                monetizationService.setDebugPlan(AppLaunchArguments.shouldUseProPlanForUITest ? .pro : .developer)
                if !AppLaunchArguments.shouldUseLiveAIBackendForUITest {
                    accountSessionService.setDebugAuthenticatedSession()
                }
            }
            monetizationService.resetQuotaForDebug()
        }

        if isUITesting && AppLaunchArguments.shouldUseLiveAIBackendForUITest {
            Task { @MainActor in
                await Self.prepareLiveAIBackendSessionForUITest(
                    appAccountService: appAccountService,
                    accountSessionService: accountSessionService
                )
            }
        }
        #endif

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
                WorkoutGoal.self,
                CustomReminder.self,
                ReminderCompletion.self,
                SuggestionUsage.self,
                BehaviorEvent.self,
                FoodMemory.self
            ])

            let modelConfiguration: ModelConfiguration
            if shouldUseInMemoryStore {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            } else if Self.hasAccessibleSharedGroupContainer {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    groupContainer: .identifier(SharedStorageKeys.AppGroup.suiteName),
                    cloudKitDatabase: .automatic
                )
            } else {
                // Keep simulator/test persistence working even when app-group
                // entitlements are unavailable in the current build environment.
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
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
                if isUITesting && !AppLaunchArguments.shouldRunOnboardingFlowUITest {
                    seedUITestProfileIfNeeded(modelContainer: container)
                    if AppLaunchArguments.shouldUseAppStoreScreenshotSeed {
                        seedAppStoreScreenshotDataIfNeeded(modelContainer: container)
                    }
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

    #if DEBUG
    @MainActor
    private static func prepareLiveAIBackendSessionForUITest(
        appAccountService: AppAccountService,
        accountSessionService: AccountSessionService
    ) async {
        appAccountService.setDebugBackendEnvironment(.localDevelopment)

        do {
            let bootstrap = try await TraiBackendClient.shared.exchangeAppleIdentity(
                AppleIdentityExchangeRequest(
                    installationID: appAccountService.installationID,
                    appAccountToken: appAccountService.appAccountToken,
                    identityToken: "ui-test-live-ai-token",
                    authorizationCode: "ui-test-live-ai-code",
                    rawNonce: nil,
                    appleUserID: "ui-test-live-ai-\(appAccountService.installationID)",
                    email: "ui-live-ai@trai.local",
                    displayName: "Live AI Tester"
                ),
                environment: .localDevelopment
            )
            accountSessionService.setDebugAuthenticatedBootstrap(bootstrap)

            try await applyLocalDeveloperSubscriptionOverrideForUITest(userID: bootstrap.session.userID)
            await accountSessionService.refreshAccountFromBackend()
        } catch {
            print("⚠️ Failed to prepare live AI backend UI-test session: \(error.localizedDescription)")
        }
    }

    private static func applyLocalDeveloperSubscriptionOverrideForUITest(userID: String) async throws {
        guard let baseURL = TraiBackendClient.shared.baseURL(for: .localDevelopment) else {
            throw BackendClientError.environmentNotConfigured
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/admin/subscription-override"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer local-dev-admin", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userID": userID,
            "plan": "developer",
            "status": "active",
            "source": "developer",
            "reason": "local simulator live AI testing",
            "createdBy": "trai-ios-ui-test"
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BackendClientError.invalidResponse
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                ContentView(deepLinkDestination: $deepLinkDestination)
                    .tint(brandAccent)
                    .accentColor(brandAccent)
                    .environment(notificationService)
                    .environment(appAccountService)
                    .environment(accountSessionService)
                    .environment(monetizationService)
                    .environment(billingService)
                    .environment(proUpsellCoordinator)
                    .environment(\.showRemindersFromNotification, $showRemindersFromNotification)
                    .proUpsellPresenter()
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            } else {
                ContentView(deepLinkDestination: $deepLinkDestination)
                    .tint(brandAccent)
                    .accentColor(brandAccent)
                    .environment(notificationService)
                    .environment(healthKitService)
                    .environment(appAccountService)
                    .environment(accountSessionService)
                    .environment(monetizationService)
                    .environment(billingService)
                    .environment(proUpsellCoordinator)
                    .environment(\.showRemindersFromNotification, $showRemindersFromNotification)
                    .proUpsellPresenter()
                    .onAppear {
                        PerformanceTrace.event("app_window_appear", category: .launch)
                        billingService.refreshLocalState()
                        monetizationService.refreshStateIfNeeded()
                        setupNotificationDelegate()
                        scheduleDeferredStartupTasksIfNeeded()
                        scheduleStartupMigrationIfNeeded()
                        scheduleReminderScheduleRefreshIfNeeded()
                        scheduleReminderBackgroundRefresh()
                        runLaunchReplayEvaluationIfRequested()
                        scheduleFoodMemoryMaintenanceIfNeeded()
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
                // Keep background transition work minimal. Food-memory resolution is
                // non-critical and already runs on launch/foreground maintenance.
                Task { @MainActor in
                    guard !hasActiveLiveWorkoutInProgress() else { return }
                    WidgetDataProvider.shared.scheduleRefresh(
                        modelContainer: modelContainer,
                        delay: .zero
                    )
                }
            } else if newPhase == .active {
                billingService.refreshLocalState()
                monetizationService.refreshStateIfNeeded()
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

    #if DEBUG
    @MainActor
    private func runLaunchReplayEvaluationIfRequested() {
        guard AppLaunchArguments.shouldRunFoodRecommendationReplayEvaluation else { return }
        guard !hasRunLaunchReplayEvaluation else { return }
        hasRunLaunchReplayEvaluation = true
        NSLog("Food recommendation replay evaluation launch run started")
        writeLaunchReplayEvaluationReport(
            "Food recommendation replay evaluation\nrunning=\(Date().formatted(date: .abbreviated, time: .standard))"
        )
        let maximumCases = AppLaunchArguments.foodRecommendationReplayMaximumCases ?? 20
        Task { @MainActor in
            do {
                try? await Task.sleep(for: .seconds(1))
                let report = try await FoodRecommendationReplayService().run(
                    maximumCases: maximumCases,
                    modelContext: modelContainer.mainContext
                )
                writeLaunchReplayEvaluationReport(report.summaryText)
                NSLog("Food recommendation replay evaluation launch run completed cases=%d", report.metrics.evaluatedCases)
            } catch {
                let message = "Food recommendation replay evaluation launch run failed: \(error)"
                writeLaunchReplayEvaluationReport(message)
                NSLog("%@", message)
            }
        }
    }

    private func writeLaunchReplayEvaluationReport(_ text: String) {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let reportURL = cachesDirectory.appendingPathComponent("FoodRecommendationReplayEvaluation.txt")
        try? text.write(to: reportURL, atomically: true, encoding: .utf8)
    }
    #else
    private func runLaunchReplayEvaluationIfRequested() {}
    #endif

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
                if !hasActiveLiveWorkoutInProgress() {
                    LiveActivityManager.shared.cancelAllActivities()
                }
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
    private func scheduleFoodMemoryMaintenanceIfNeeded() {
        guard !AppLaunchArguments.shouldRunFoodRecommendationReplayEvaluation else { return }
        guard startupCoordinator.claimFoodMemoryMaintenance() else { return }

        let now = Date()
        if persistedFoodMemoryLaunchMaintenanceTimestamp > 0 {
            let lastRun = Date(timeIntervalSince1970: persistedFoodMemoryLaunchMaintenanceTimestamp)
            guard now.timeIntervalSince(lastRun) >= foodMemoryLaunchMaintenanceInterval else { return }
        }

        guard scenePhase == .active else { return }
        guard !hasActiveLiveWorkoutInProgress() else { return }

        persistedFoodMemoryLaunchMaintenanceTimestamp = now.timeIntervalSince1970
        FoodMemoryBackgroundService.shared.scheduleMaintenance(
            modelContainer: modelContainer,
            backfillLimit: 8,
            resolveLimit: 4,
            delay: foodMemoryMaintenanceDeferral
        )
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
        guard hasCompletedOnboardingProfile() else { return }
        guard healthKitService.isAuthorized else { return }

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
    private func hasCompletedOnboardingProfile() -> Bool {
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate<UserProfile> { $0.hasCompletedOnboarding == true }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContainer.mainContext.fetch(descriptor)) ?? []).isEmpty == false
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

    private static var hasAccessibleSharedGroupContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStorageKeys.AppGroup.suiteName
        ) != nil
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
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName) else {
            return
        }

        let pendingLogs = PendingFoodLogQueue.load(from: defaults)
        guard !pendingLogs.isEmpty else { return }

        let context = modelContainer.mainContext
        var alreadyPersistedIDs = Set<UUID>()
        var stagedIDs = Set<UUID>()
        var seenIDs = Set<UUID>()

        for log in pendingLogs {
            guard seenIDs.insert(log.id).inserted else { continue }

            do {
                if try hasPersistedWidgetFoodEntry(id: log.id, context: context) {
                    alreadyPersistedIDs.insert(log.id)
                    continue
                }
            } catch {
                continue
            }

            let entry = FoodEntry()
            entry.id = log.id
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
            stagedIDs.insert(log.id)
        }

        var processedIDs = alreadyPersistedIDs

        if !stagedIDs.isEmpty {
            do {
                try context.save()
                processedIDs.formUnion(stagedIDs)
            } catch {
                context.rollback()
            }
        }

        try? PendingFoodLogQueue.remove(ids: processedIDs, from: defaults)

        // Refresh widgets with new data
        if !processedIDs.isEmpty {
            WidgetDataProvider.shared.scheduleRefresh(
                modelContainer: modelContainer,
                delay: .milliseconds(150)
            )
        }
    }

    @MainActor
    private func hasPersistedWidgetFoodEntry(id: UUID, context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
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
private func seedAppStoreScreenshotDataIfNeeded(modelContainer: ModelContainer) {
    let context = modelContainer.mainContext
    var markerDescriptor = FetchDescriptor<CoachMemory>(
        predicate: #Predicate<CoachMemory> { $0.content == "App Store Screenshot Seed" }
    )
    markerDescriptor.fetchLimit = 1
    guard ((try? context.fetch(markerDescriptor)) ?? []).isEmpty else { return }

    let calendar = Calendar.current
    let now = Date()
    let today = calendar.startOfDay(for: now)

    let profile = fetchOrCreateScreenshotProfile(context: context)
    profile.name = "Nadav"
    profile.hasCompletedOnboarding = true
    profile.goal = .recomposition
    profile.currentWeightKg = 78.4
    profile.targetWeightKg = 75.0
    profile.dailyCalorieGoal = 2450
    profile.dailyProteinGoal = 175
    profile.dailyCarbsGoal = 260
    profile.dailyFatGoal = 72
    profile.dailyFiberGoal = 34
    profile.dailySugarGoal = 55
    profile.enabledMacros = MacroType.defaultEnabled
    profile.usesMetricWeight = false
    profile.usesMetricExerciseWeight = false
    profile.preferredWorkoutDays = 4
    profile.workoutExperienceLevel = "intermediate"
    profile.workoutTimePerSession = 55
    profile.defaultWorkoutAction = "recommendedWorkout"
    profile.workoutPlan = screenshotWorkoutPlan()

    let chatSessionId = UUID(uuidString: "48D643F0-4B92-4C90-9754-8546F511C6EF") ?? UUID()
    UserDefaults.standard.set(chatSessionId.uuidString, forKey: "currentChatSessionId")
    UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastChatActivityDate")

    seedScreenshotFoodEntries(context: context, calendar: calendar, today: today)
    seedScreenshotWeightEntries(context: context, calendar: calendar, today: today)
    seedScreenshotWorkouts(context: context, calendar: calendar, today: today)
    seedScreenshotChat(context: context, sessionId: chatSessionId, now: now)
    seedScreenshotGoalsAndMemory(context: context, now: now)

    try? context.save()
}

@MainActor
private func fetchOrCreateScreenshotProfile(context: ModelContext) -> UserProfile {
    var descriptor = FetchDescriptor<UserProfile>()
    descriptor.fetchLimit = 1
    if let profile = (try? context.fetch(descriptor))?.first {
        return profile
    }

    let profile = UserProfile()
    context.insert(profile)
    return profile
}

private func seedScreenshotFoodEntries(context: ModelContext, calendar: Calendar, today: Date) {
    let mealSession = UUID()
    let items: [(String, Int, Double, Double, Double, Double, Double, String, String, Int, Int)] = [
        ("Greek Yogurt Berry Bowl", 420, 38, 46, 12, 8, 16, "breakfast", "yogurt bowl with berries and granola", 8, 10),
        ("Turkey Avocado Wrap", 610, 47, 58, 22, 10, 7, "lunch", "turkey avocado wrap", 12, 35),
        ("Iced Protein Latte", 190, 25, 14, 4, 0, 6, "snack", "protein latte", 15, 5),
        ("Salmon Rice Bowl", 735, 52, 76, 24, 9, 8, "dinner", "salmon rice bowl with vegetables", 19, 15)
    ]

    for (index, item) in items.enumerated() {
        let entry = FoodEntry()
        entry.name = item.0
        entry.calories = item.1
        entry.proteinGrams = item.2
        entry.carbsGrams = item.3
        entry.fatGrams = item.4
        entry.fiberGrams = item.5
        entry.sugarGrams = item.6
        entry.mealType = item.7
        entry.input = index == 3 ? .camera : .manual
        entry.sessionId = index == 3 ? mealSession : nil
        entry.sessionOrder = index == 3 ? 0 : index
        entry.servingSize = "1 serving"
        entry.userDescription = item.8
        entry.loggedAt = calendar.date(byAdding: .minute, value: item.10, to: calendar.date(byAdding: .hour, value: item.9, to: today) ?? today) ?? Date()
        entry.ensureDisplayMetadata()
        context.insert(entry)
    }
}

private func seedScreenshotWeightEntries(context: ModelContext, calendar: Calendar, today: Date) {
    for dayOffset in stride(from: -42, through: 0, by: 7) {
        let entry = WeightEntry(weightKg: 80.1 + Double(dayOffset) * 0.04, loggedAt: calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today)
        entry.bodyFatPercentage = 17.8 + Double(dayOffset) * 0.01
        context.insert(entry)
    }
}

private func seedScreenshotWorkouts(context: ModelContext, calendar: Calendar, today: Date) {
    let workouts: [(String, LiveWorkout.WorkoutType, [String], Int, Int)] = [
        ("Upper Strength", .strength, ["Chest", "Back", "Shoulders"], -1, 58),
        ("Zone 2 Run", .cardio, ["Conditioning"], -3, 36),
        ("Lower Power", .strength, ["Quads", "Glutes", "Hamstrings"], -5, 62),
        ("Push Hypertrophy", .strength, ["Chest", "Shoulders", "Triceps"], -8, 54)
    ]

    for workoutData in workouts {
        let startedAt = calendar.date(byAdding: .day, value: workoutData.3, to: today) ?? today
        let workout = LiveWorkout(
            name: workoutData.0,
            workoutType: workoutData.1,
            targetMuscleGroups: LiveWorkout.MuscleGroup.fromTargetStrings(workoutData.2),
            focusAreas: workoutData.2
        )
        workout.startedAt = calendar.date(byAdding: .hour, value: 17, to: startedAt) ?? startedAt
        workout.completedAt = calendar.date(byAdding: .minute, value: workoutData.4, to: workout.startedAt)
        workout.healthKitCalories = workoutData.1 == .cardio ? 390 : 260
        workout.healthKitAvgHeartRate = workoutData.1 == .cardio ? 148 : 116

        if workoutData.1 == .cardio {
            let run = LiveWorkoutEntry(exerciseName: "Outdoor Run", orderIndex: 0, exerciseType: "cardio")
            run.durationSeconds = workoutData.4 * 60
            run.distanceMeters = 6200
            run.caloriesBurned = 390
            run.completedAt = workout.completedAt
            workout.entries = [run]
        } else {
            let first = LiveWorkoutEntry(exerciseName: workoutData.0.contains("Lower") ? "Back Squat" : "Incline Dumbbell Press", orderIndex: 0)
            first.addSet(.init(reps: 8, weight: .init(kg: 42.5, lbs: 94), preferredWeightUnit: .lbs, completed: true))
            first.addSet(.init(reps: 8, weight: .init(kg: 45, lbs: 99), preferredWeightUnit: .lbs, completed: true))
            first.addSet(.init(reps: 7, weight: .init(kg: 45, lbs: 99), preferredWeightUnit: .lbs, completed: true))
            first.completedAt = workout.completedAt

            let second = LiveWorkoutEntry(exerciseName: workoutData.0.contains("Lower") ? "Romanian Deadlift" : "Chest-Supported Row", orderIndex: 1)
            second.addSet(.init(reps: 10, weight: .init(kg: 50, lbs: 110), preferredWeightUnit: .lbs, completed: true))
            second.addSet(.init(reps: 10, weight: .init(kg: 52.5, lbs: 116), preferredWeightUnit: .lbs, completed: true))
            second.completedAt = workout.completedAt
            workout.entries = [first, second]
        }
        context.insert(workout)
    }

    context.insert(WorkoutGoal(
        title: "Train 4x this week",
        goalKind: .frequency,
        linkedWorkoutType: .strength,
        targetValue: 4,
        targetUnit: "workouts",
        periodUnit: .week,
        periodCount: 1,
        notes: "Build consistent strength training weeks."
    ))
    context.insert(WorkoutGoal(
        title: "Bench 185 lb for 5",
        goalKind: .weight,
        linkedWorkoutType: .strength,
        linkedActivityName: "Bench Press",
        targetValue: 185,
        targetUnit: "lb",
        notes: "Progress upper-body strength without rushing recovery."
    ))
}

private func seedScreenshotChat(context: ModelContext, sessionId: UUID, now: Date) {
    if AppLaunchArguments.appStoreScreenshotChatScenarioRawValue == "plan" {
        seedScreenshotPlanChat(context: context, sessionId: sessionId, now: now)
        return
    }

    let user = ChatMessage(
        content: "I'm about to start Upper Strength, but my lower back feels tight. Can you adjust it?",
        isFromUser: true,
        sessionId: sessionId
    )
    user.timestamp = now.addingTimeInterval(-240)
    let coach = ChatMessage(
        content: "I used your recent recovery notes and today's plan to make the lift more joint-friendly while keeping the strength work on track.",
        isFromUser: false,
        sessionId: sessionId
    )
    coach.timestamp = now.addingTimeInterval(-210)
    let memory = "Prefers lower-back friendly substitutions when squats feel heavy."
    coach.setSuggestedWorkout(SuggestedWorkoutEntry(
        name: "Adjusted Upper Strength",
        workoutType: "strength",
        targetMuscleGroups: ["legs", "back", "chest"],
        exercises: [
            .init(name: "Back Squat", sets: 1, reps: 6, weightKg: 84),
            .init(name: "Chest-Supported Row", sets: 3, reps: 8, weightKg: 45),
            .init(name: "Incline Dumbbell Press", sets: 3, reps: 10, weightKg: 27)
        ],
        durationMinutes: 38,
        rationale: "Adjusted from your plan and saved preferences."
    ))
    context.insert(user)
    context.insert(coach)
    context.insert(CoachMemory(
        content: memory,
        category: .preference,
        topic: .workout,
        source: "app_store_screenshot_seed",
        importance: 5
    ))
}

private func seedScreenshotPlanChat(context: ModelContext, sessionId: UUID, now: Date) {
    let user = ChatMessage(
        content: "Build this week around strength, recovery, and my Friday Zone 2 run.",
        isFromUser: true,
        sessionId: sessionId
    )
    user.timestamp = now.addingTimeInterval(-240)

    let coach = ChatMessage(
        content: "I matched your recomp goal, recent workouts, and recovery pattern to a 4-day plan that keeps Friday's run protected.",
        isFromUser: false,
        sessionId: sessionId
    )
    coach.timestamp = now.addingTimeInterval(-210)
    coach.setSuggestedWorkoutPlan(WorkoutPlanSuggestionEntry(
        plan: screenshotWorkoutPlan(),
        message: "4-day strength plan with recovery built in."
    ))

    context.insert(user)
    context.insert(coach)
}

private func seedScreenshotGoalsAndMemory(context: ModelContext, now: Date) {
    context.insert(CoachMemory(
        content: "Prefers fast high-protein lunches like bowls, wraps, and protein coffee on training days.",
        category: .preference,
        topic: .food,
        source: "app_store_screenshot_seed",
        importance: 4
    ))
    context.insert(CoachMemory(
        content: "App Store Screenshot Seed",
        category: .context,
        topic: .general,
        source: "app_store_screenshot_seed",
        importance: 1
    ))
}

private func screenshotWorkoutPlan() -> WorkoutPlan {
    WorkoutPlan(
        splitType: .upperLower,
        daysPerWeek: 4,
        templates: [
            WorkoutPlan.WorkoutTemplate(
                name: "Upper Strength",
                targetMuscleGroups: ["chest", "back", "shoulders"],
                exercises: [
                    .init(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: 4, defaultReps: 5, repRange: "4-6", restSeconds: 150, order: 0),
                    .init(exerciseName: "Chest-Supported Row", muscleGroup: "back", defaultSets: 4, defaultReps: 8, repRange: "8-10", restSeconds: 120, order: 1),
                    .init(exerciseName: "Incline Dumbbell Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 10, repRange: "8-12", restSeconds: 90, order: 2)
                ],
                estimatedDurationMinutes: 55,
                order: 0,
                notes: "Heavy upper-body day with controlled progression."
            ),
            WorkoutPlan.WorkoutTemplate(
                name: "Lower Power",
                targetMuscleGroups: ["quads", "glutes", "hamstrings"],
                exercises: [
                    .init(exerciseName: "Back Squat", muscleGroup: "quads", defaultSets: 4, defaultReps: 5, repRange: "4-6", restSeconds: 180, order: 0),
                    .init(exerciseName: "Romanian Deadlift", muscleGroup: "hamstrings", defaultSets: 3, defaultReps: 8, repRange: "8-10", restSeconds: 120, order: 1),
                    .init(exerciseName: "Walking Lunge", muscleGroup: "glutes", defaultSets: 3, defaultReps: 12, repRange: "10-12", restSeconds: 90, order: 2)
                ],
                estimatedDurationMinutes: 60,
                order: 1,
                notes: "Lower-body strength and posterior-chain focus."
            )
        ],
        rationale: "Four focused sessions balance strength progress, recovery, and recomposition.",
        guidelines: [
            "Add weight when all top sets reach the target reps.",
            "Keep two reps in reserve on accessory work.",
            "Pair harder training days with the higher-carb nutrition target."
        ],
        progressionStrategy: .defaultStrategy,
        warnings: nil
    )
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
