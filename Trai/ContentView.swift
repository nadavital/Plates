//
//  ContentView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

// MARK: - Environment Key for Notification Trigger

private struct ShowRemindersFromNotificationKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showRemindersFromNotification: Binding<Bool> {
        get { self[ShowRemindersFromNotificationKey.self] }
        set { self[ShowRemindersFromNotificationKey.self] = newValue }
    }
}

struct ContentView: View {
    private enum StartupResolutionState {
        case determining
        case waitingForCloudProfile
        case ready
        case needsOnboarding
    }

    private static let cloudProfileGracePeriodSeconds: TimeInterval = 3.0
    private static let cloudProfilePollIntervalMilliseconds = 200

    @Query private var completedProfiles: [UserProfile]
    @AppStorage(AppLaunchArguments.onboardingCompletedCacheKey)
    private var cachedOnboardingReady = false
    @Environment(\.modelContext) private var modelContext
    @State private var didRunStartupFlow = false
    @State private var startupResolutionState: StartupResolutionState = .determining
    @StateObject private var activeWorkoutRuntimeState = ActiveWorkoutRuntimeState()
    @Binding var deepLinkDestination: AppRoute?

    init(deepLinkDestination: Binding<AppRoute?> = .constant(nil)) {
        var completedProfileDescriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate<UserProfile> { $0.hasCompletedOnboarding == true }
        )
        completedProfileDescriptor.fetchLimit = 1
        _completedProfiles = Query(completedProfileDescriptor)
        self._deepLinkDestination = deepLinkDestination
    }

    private var hasCompletedOnboarding: Bool {
        AppLaunchArguments.isUITesting
            || cachedOnboardingReady
            || !completedProfiles.isEmpty
    }

    /// Fast query-backed readiness used for first paint.
    /// Cached readiness is validated in `runStartupFlow()`.
    private var hasCompletedOnboardingFromQuery: Bool {
        AppLaunchArguments.isUITesting || !completedProfiles.isEmpty
    }

    var body: some View {
        Group {
            if hasCompletedOnboardingFromQuery || startupResolutionState == .ready {
                MainTabView(deepLinkDestination: $deepLinkDestination)
            } else if startupResolutionState == .determining
                        || startupResolutionState == .waitingForCloudProfile {
                StartupReadinessView(
                    statusText: "Syncing your profile...",
                    lensState: .thinking
                )
            } else {
                OnboardingView()
            }
        }
        .environmentObject(activeWorkoutRuntimeState)
        .task {
            guard !didRunStartupFlow else { return }
            didRunStartupFlow = true
            await runStartupFlow()
        }
        .onChange(of: !completedProfiles.isEmpty) { _, hasCompleted in
            if hasCompleted {
                cachedOnboardingReady = true
                startupResolutionState = .ready
            }
        }
    }

    @MainActor
    private func runStartupFlow() async {
        guard !AppLaunchArguments.isUITesting else { return }

        let interval = PerformanceTrace.begin("content_startup_flow", category: .launch)
        defer { PerformanceTrace.end("content_startup_flow", interval, category: .launch) }

        // Validate cached onboarding readiness before trusting it for navigation.
        if cachedOnboardingReady, completedProfiles.isEmpty, !hasCompletedOnboardingLocally() {
            cachedOnboardingReady = false
        }

        if hasCompletedOnboarding {
            cachedOnboardingReady = true
            startupResolutionState = .ready
            PerformanceTrace.event("content_startup_ready_local", category: .launch)
            return
        }

        if hasCompletedOnboardingLocally() {
            startupResolutionState = .ready
            PerformanceTrace.event("content_startup_ready_local_fetch", category: .launch)
            return
        }

        // Give @Query one render cycle to settle before concluding no local profile exists.
        try? await Task.sleep(for: .milliseconds(120))
        if hasCompletedOnboarding {
            cachedOnboardingReady = true
            startupResolutionState = .ready
            PerformanceTrace.event("content_startup_ready_after_settle", category: .launch)
            return
        }
        if hasCompletedOnboardingLocally() {
            startupResolutionState = .ready
            PerformanceTrace.event("content_startup_ready_after_settle_fetch", category: .launch)
            return
        }

        startupResolutionState = .waitingForCloudProfile
        let deadline = Date().addingTimeInterval(Self.cloudProfileGracePeriodSeconds)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(Self.cloudProfilePollIntervalMilliseconds))
            if hasCompletedOnboarding {
                cachedOnboardingReady = true
                startupResolutionState = .ready
                PerformanceTrace.event("content_startup_ready_after_cloud_sync", category: .launch)
                return
            }
            if hasCompletedOnboardingLocally() {
                startupResolutionState = .ready
                PerformanceTrace.event("content_startup_ready_after_cloud_fetch", category: .launch)
                return
            }
        }

        startupResolutionState = .needsOnboarding
        cachedOnboardingReady = false
        PerformanceTrace.event("content_startup_no_local_profile", category: .launch)
    }

    @MainActor
    private func hasCompletedOnboardingLocally() -> Bool {
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate<UserProfile> { $0.hasCompletedOnboarding == true }
        )
        descriptor.fetchLimit = 1
        let isReady = ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
        if isReady {
            cachedOnboardingReady = true
        }
        return isReady
    }
}

// MARK: - Main Tab View

enum AppTab: String, CaseIterable {
    case dashboard
    case trai
    case workouts
    case profile
}

private struct AppTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<AppTab> = .constant(.dashboard)
}

extension EnvironmentValues {
    var appTabSelection: Binding<AppTab> {
        get { self[AppTabSelectionKey.self] }
        set { self[AppTabSelectionKey.self] = newValue }
    }
}

struct MainTabView: View {
    @AppStorage("selectedTab") private var persistedSelectedTabRaw: String = AppTab.dashboard.rawValue
    @Environment(\.showRemindersFromNotification) private var showRemindersFromNotification
    @Environment(\.modelContext) private var modelContext
    @Binding var deepLinkDestination: AppRoute?
    @State private var selectedTabState: AppTab = .dashboard
    @State private var hasInitializedSelection = false
    @State private var loadedTabs: Set<AppTab> = []
    private let tabPrewarmPolicy = TabPrewarmPolicy(
        initialDelayMilliseconds: 160,
        interTabDelayMilliseconds: 1200
    )
    @State private var tabPrewarmTask: Task<Void, Never>?
    @State private var hasScheduledTabPrewarm = false
    @Query private var activeWorkouts: [LiveWorkout]

    init(deepLinkDestination: Binding<AppRoute?> = .constant(nil)) {
        var activeWorkoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { $0.completedAt == nil },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        activeWorkoutDescriptor.fetchLimit = 1
        _activeWorkouts = Query(activeWorkoutDescriptor)
        self._deepLinkDestination = deepLinkDestination
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { selectedTabState },
            set: { newValue in
                _ = loadedTabs.insert(newValue)
                selectedTabState = newValue
            }
        )
    }

    // Capture the workout when opening sheet to avoid nil issues when workout completes
    @State private var presentedWorkout: LiveWorkout?
    @State private var showingEndConfirmation = false
    @State private var showingReminders = false

    // App Intent / Deep link triggered states
    @State private var foodCameraPresentation: FoodCameraPresentation?
    @State private var isPreparingFoodCamera = false
    @State private var showingLogWeight = false
    @State private var intentTriggeredWorkout: LiveWorkout?
    @State private var workoutTemplateService = WorkoutTemplateService()

    private var activeWorkout: LiveWorkout? {
        activeWorkouts.first
    }

    private var activeTab: AppTab {
        selectedTabState
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: .dashboard) {
                cachedTabContent(for: .dashboard) {
                    DashboardView(
                        showRemindersBinding: $showingReminders,
                        onSelectTab: selectTab
                    )
                }
            }

            Tab("Trai", systemImage: "circle.hexagongrid.circle", value: .trai, role: .search) {
                cachedTabContent(for: .trai) {
                    ChatView()
                }
            }

            Tab("Workouts", systemImage: "figure.run", value: .workouts) {
                cachedTabContent(for: .workouts) {
                    WorkoutsView()
                }
            }

            Tab("Profile", systemImage: "person.fill", value: .profile) {
                cachedTabContent(for: .profile) {
                    ProfileView(onSelectTab: selectTab)
                }
            }
        }
        .scrollIndicators(.hidden)
        .environment(\.appTabSelection, selectedTab)
        .onAppear {
            if !hasInitializedSelection {
                hasInitializedSelection = true
                if AppLaunchArguments.isUITesting {
                    selectedTabState = .dashboard
                    persistedSelectedTabRaw = AppTab.dashboard.rawValue
                } else {
                    selectedTabState = AppTab(rawValue: persistedSelectedTabRaw) ?? .dashboard
                }
            }
            if loadedTabs.isEmpty {
                _ = loadedTabs.insert(selectedTabState)
            }
            scheduleTabPrewarmIfNeeded()
            PerformanceTrace.event("main_tab_first_frame", category: .launch)
        }
        .onChange(of: selectedTabState) { _, tab in
            persistedSelectedTabRaw = tab.rawValue
            scheduleTabPrewarmIfNeeded()
        }
        .onChange(of: persistedSelectedTabRaw) { _, newValue in
            guard let tab = AppTab(rawValue: newValue) else { return }
            guard tab != selectedTabState else { return }
            selectedTabState = tab
        }
        .onChange(of: showRemindersFromNotification.wrappedValue) { _, shouldShow in
            if shouldShow {
                // Switch to dashboard and show reminders
                selectTab(.dashboard)
                showingReminders = true
                showRemindersFromNotification.wrappedValue = false
            }
        }
        .tabViewBottomAccessory(isEnabled: activeWorkout != nil) {
            if let workout = activeWorkout {
                WorkoutBanner(
                    workout: workout,
                    onTap: { presentedWorkout = workout },
                    onEnd: { showingEndConfirmation = true }
                )
            }
        }
        .sheet(item: $presentedWorkout) { workout in
            LiveWorkoutView(workout: workout)
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                if let workout = activeWorkout {
                    workout.completedAt = Date()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this workout?")
        }
        .fullScreenCover(item: $foodCameraPresentation) { presentation in
            FoodCameraView(
                sessionId: presentation.sessionId,
                cameraService: presentation.cameraService
            )
        }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet()
        }
        .sheet(item: $intentTriggeredWorkout) { workout in
            LiveWorkoutView(workout: workout)
        }
        .onAppear {
            consumePendingRoute()
            // Handle deep links that may have been set before this view appeared (cold launch from widget).
            handleRoute(deepLinkDestination)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumePendingRoute()
        }
        .onChange(of: deepLinkDestination) { _, destination in
            handleRoute(destination)
        }
        .onDisappear {
            tabPrewarmTask?.cancel()
        }
    }

    @ViewBuilder
    private func cachedTabContent<Content: View>(
        for tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if loadedTabs.contains(tab) {
            content()
        } else if activeTab == tab {
            tabLoadingPlaceholder()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func tabLoadingPlaceholder() -> some View {
        ZStack {
            Color.clear
            ProgressView().tint(.accentColor)
        }
    }

    private func scheduleTabPrewarmIfNeeded() {
        guard AppLaunchArguments.shouldEnableTabPrewarm else { return }
        guard !hasScheduledTabPrewarm else { return }

        let preloadOrder = tabPrewarmPolicy.preloadOrder(
            for: selectedTabState,
            loadedTabs: loadedTabs
        )
        guard !preloadOrder.isEmpty else { return }

        hasScheduledTabPrewarm = true
        tabPrewarmTask?.cancel()
        let initialDelay = tabPrewarmPolicy.initialDelayMilliseconds
        let interTabDelay = tabPrewarmPolicy.interTabDelayMilliseconds

        tabPrewarmTask = Task(priority: .utility) { @MainActor in
            for (index, tab) in preloadOrder.enumerated() {
                let delayMilliseconds = index == 0 ? initialDelay : interTabDelay
                if delayMilliseconds > 0 {
                    try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                }
                guard !Task.isCancelled else { return }
                if loadedTabs.contains(tab) {
                    continue
                }
                _ = loadedTabs.insert(tab)
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleRoute(_ destination: AppRoute?) {
        guard let destination else { return }

        // Reset the deep link after handling
        Task { @MainActor in
            deepLinkDestination = nil
        }

        switch destination {
        case .logFood:
            guard foodCameraPresentation == nil, !isPreparingFoodCamera else { return }
            isPreparingFoodCamera = true
            Task { @MainActor in
                let presentation = FoodCameraPresentation()
                await presentation.cameraService.requestPermission()
                foodCameraPresentation = presentation
                isPreparingFoodCamera = false
            }
        case .logWeight:
            showingLogWeight = true
        case .workout(let templateName):
            startWorkoutFromIntent(name: templateName ?? "custom")
        case .chat:
            selectTab(.trai)
        }
    }

    private func selectTab(_ tab: AppTab) {
        _ = loadedTabs.insert(tab)
        selectedTabState = tab
    }

    // MARK: - App Intent Handling

    private func consumePendingRoute() {
        guard let route = PendingAppRouteStore.consumePendingRoute() else { return }
        handleRoute(route)
    }

    private func startWorkoutFromIntent(name: String) {
        // Guard: Don't start a new workout if one is already active
        guard activeWorkout == nil else {
            // Show the existing workout instead
            presentedWorkout = activeWorkout
            return
        }

        let workout = workoutTemplateService.createWorkoutForIntent(
            name: name,
            modelContext: modelContext
        )

        if AppLaunchArguments.isUITesting, AppLaunchArguments.shouldUseLiveWorkoutUITestPreset {
            applyLiveWorkoutUITestPresetIfNeeded(to: workout)
        }

        _ = workoutTemplateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .intent,
            outcome: .completed,
            relatedEntityId: workout.id,
            metadata: [
                "source": "deep_link",
                "name": workout.name
            ]
        )

        // Switch to workouts tab and present the workout
        selectTab(.workouts)
        intentTriggeredWorkout = workout
    }

    private func applyLiveWorkoutUITestPresetIfNeeded(to workout: LiveWorkout) {
        if let entries = workout.entries, !entries.isEmpty {
            return
        }

        let primary = LiveWorkoutEntry(exerciseName: "UI Test Squat", orderIndex: 0)
        let cleanWeight = CleanWeight(kg: 60, lbs: 132.3)
        for _ in 0..<4 {
            primary.addSet(LiveWorkoutEntry.SetData(
                reps: 8,
                weight: cleanWeight,
                completed: false,
                isWarmup: false
            ))
        }

        let secondary = LiveWorkoutEntry(exerciseName: "UI Test Press", orderIndex: 1)
        for _ in 0..<3 {
            secondary.addSet(LiveWorkoutEntry.SetData(
                reps: 10,
                weight: CleanWeight(kg: 35, lbs: 77.2),
                completed: false,
                isWarmup: false
            ))
        }

        workout.entries = [primary, secondary]
    }
}

private struct StartupReadinessView: View {
    let statusText: String
    let lensState: TraiLensState

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                TraiLensView(size: 72, state: lensState, palette: .energy)
                    .accessibilityHidden(true)
                Text("Trai")
                    .font(.title3.weight(.semibold))
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            Exercise.self,
            WorkoutSession.self,
            WeightEntry.self,
            ChatMessage.self,
            LiveWorkout.self,
            LiveWorkoutEntry.self,
            ExerciseHistory.self,
            BehaviorEvent.self
        ], inMemory: true)
}
