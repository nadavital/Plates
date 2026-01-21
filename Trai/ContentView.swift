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
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @State private var isWaitingForSync = true
    @Binding var deepLinkDestination: TraiApp.DeepLinkDestination?

    init(deepLinkDestination: Binding<TraiApp.DeepLinkDestination?> = .constant(nil)) {
        self._deepLinkDestination = deepLinkDestination
    }

    private var hasCompletedOnboarding: Bool {
        profiles.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        Group {
            if isWaitingForSync {
                // Show loading while waiting for CloudKit sync
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                }
            } else if hasCompletedOnboarding {
                MainTabView(deepLinkDestination: $deepLinkDestination)
            } else {
                OnboardingView()
            }
        }
        .task {
            await waitForCloudKitSync()
        }
    }

    private func waitForCloudKitSync() async {
        // If profile already exists locally, no need to wait
        if hasCompletedOnboarding {
            isWaitingForSync = false
            return
        }

        // Wait up to 3 seconds for CloudKit to sync profile
        let maxWaitTime: TimeInterval = 3.0
        let checkInterval: TimeInterval = 0.2
        var elapsed: TimeInterval = 0

        while elapsed < maxWaitTime {
            try? await Task.sleep(for: .milliseconds(200))
            elapsed += checkInterval

            // Check if profile synced
            if hasCompletedOnboarding {
                break
            }
        }

        isWaitingForSync = false
    }
}

// MARK: - Main Tab View

enum AppTab: String, CaseIterable {
    case dashboard
    case trai
    case workouts
    case profile
}

struct MainTabView: View {
    @AppStorage("selectedTab") private var selectedTabRaw: String = AppTab.dashboard.rawValue
    @Environment(\.showRemindersFromNotification) private var showRemindersFromNotification
    @Environment(\.modelContext) private var modelContext
    @Binding var deepLinkDestination: TraiApp.DeepLinkDestination?

    init(deepLinkDestination: Binding<TraiApp.DeepLinkDestination?> = .constant(nil)) {
        self._deepLinkDestination = deepLinkDestination
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .dashboard },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
    @Query(filter: #Predicate<LiveWorkout> { $0.completedAt == nil })
    private var activeWorkouts: [LiveWorkout]

    // Capture the workout when opening sheet to avoid nil issues when workout completes
    @State private var presentedWorkout: LiveWorkout?
    @State private var showingEndConfirmation = false
    @State private var showingReminders = false

    // App Intent / Deep link triggered states
    @State private var showingFoodCamera = false
    @State private var showingLogFood = false
    @State private var showingLogWeight = false
    @State private var intentTriggeredWorkout: LiveWorkout?

    private var activeWorkout: LiveWorkout? {
        activeWorkouts.first
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: .dashboard) {
                DashboardView(showRemindersBinding: $showingReminders)
            }

            Tab("Trai", systemImage: "circle.hexagongrid.circle", value: .trai, role: .search) {
                ChatView()
            }

            Tab("Workouts", systemImage: "figure.run", value: .workouts) {
                WorkoutsView()
            }

            Tab("Profile", systemImage: "person.fill", value: .profile) {
                ProfileView()
            }
        }
        .onChange(of: showRemindersFromNotification.wrappedValue) { _, shouldShow in
            if shouldShow {
                // Switch to dashboard and show reminders
                selectedTabRaw = AppTab.dashboard.rawValue
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
            NavigationStack {
                LiveWorkoutView(workout: workout)
            }
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
        .fullScreenCover(isPresented: $showingFoodCamera) {
            FoodCameraView()
        }
        .sheet(isPresented: $showingLogFood) {
            TraiLensView()
        }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet()
        }
        .sheet(item: $intentTriggeredWorkout) { workout in
            NavigationStack {
                LiveWorkoutView(workout: workout)
            }
        }
        .onAppear {
            checkForAppIntentTriggers()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkForAppIntentTriggers()
        }
        .onChange(of: deepLinkDestination) { _, destination in
            handleDeepLink(destination)
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ destination: TraiApp.DeepLinkDestination?) {
        guard let destination else { return }

        // Reset the deep link after handling
        Task { @MainActor in
            deepLinkDestination = nil
        }

        switch destination {
        case .logFood:
            showingLogFood = true
        case .logWeight:
            showingLogWeight = true
        case .workout:
            startWorkoutFromIntent(name: "custom")
        case .chat:
            selectedTabRaw = AppTab.trai.rawValue
        }
    }

    // MARK: - App Intent Handling

    private func checkForAppIntentTriggers() {
        // Check for food camera intent
        if UserDefaults.standard.bool(forKey: "openFoodCameraFromIntent") {
            UserDefaults.standard.removeObject(forKey: "openFoodCameraFromIntent")
            showingFoodCamera = true
            return
        }

        // Check for start workout intent
        if let workoutName = UserDefaults.standard.string(forKey: "startWorkoutFromIntent") {
            UserDefaults.standard.removeObject(forKey: "startWorkoutFromIntent")
            startWorkoutFromIntent(name: workoutName)
        }
    }

    private func startWorkoutFromIntent(name: String) {
        // Create workout - if "custom", create empty; otherwise try to match template
        let workout: LiveWorkout

        if name == "custom" {
            workout = LiveWorkout(
                name: "Custom Workout",
                workoutType: .strength,
                targetMuscleGroups: []
            )
        } else {
            // Try to find matching template from user's workout plan
            let profileDescriptor = FetchDescriptor<UserProfile>()
            if let profile = try? modelContext.fetch(profileDescriptor).first,
               let plan = profile.workoutPlan,
               let template = plan.templates.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                let muscleGroups = template.targetMuscleGroups.compactMap { LiveWorkout.MuscleGroup(rawValue: $0) }
                workout = LiveWorkout(
                    name: template.name,
                    workoutType: .strength,
                    targetMuscleGroups: muscleGroups
                )
            } else {
                // Fallback to custom workout with the provided name
                workout = LiveWorkout(
                    name: name,
                    workoutType: .strength,
                    targetMuscleGroups: []
                )
            }
        }

        modelContext.insert(workout)
        try? modelContext.save()

        // Switch to workouts tab and present the workout
        selectedTabRaw = AppTab.workouts.rawValue
        intentTriggeredWorkout = workout
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
            ExerciseHistory.self
        ], inMemory: true)
}
