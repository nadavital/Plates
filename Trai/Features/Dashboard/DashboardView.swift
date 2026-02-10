//
//  DashboardView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    /// Optional binding to control reminders sheet from parent (for notification taps)
    @Binding var showRemindersBinding: Bool

    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    private var allFoodEntries: [FoodEntry]

    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    private var allWorkouts: [WorkoutSession]

    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    private var liveWorkouts: [LiveWorkout]

    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var weightEntries: [WeightEntry]

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @State private var recoveryService = MuscleRecoveryService()

    // Custom reminders (fetched manually to avoid @Query freeze)
    @State private var customReminders: [CustomReminder] = []
    @State private var todaysCompletedReminderIds: Set<UUID> = []
    @State private var remindersLoaded = false
    @State private var pendingScrollToReminders = false

    // Sheet presentation state
    @State private var showingLogFood = false
    @State private var showingLogWeight = false
    @State private var showingCalorieDetail = false
    @State private var showingMacroDetail = false
    @State private var entryToEdit: FoodEntry?
    @State private var sessionIdToAddTo: UUID?

    // Workout sheet state
    @State private var showingWorkoutSheet = false
    @State private var pendingWorkout: LiveWorkout?
    @State private var pendingTemplate: WorkoutPlan.WorkoutTemplate?

    init(showRemindersBinding: Binding<Bool> = .constant(false)) {
        _showRemindersBinding = showRemindersBinding
    }

    // Date navigation
    @State private var selectedDate = Date()

    // Activity data from HealthKit
    @State private var todaySteps = 0
    @State private var todayActiveCalories = 0
    @State private var todayExerciseMinutes = 0
    @State private var isLoadingActivity = false

    private var profile: UserProfile? { profiles.first }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDayFoodEntries: [FoodEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allFoodEntries.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay }
    }

    /// Last 7 days of food entries for trend charts
    private var last7DaysFoodEntries: [FoodEntry] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
        return allFoodEntries.filter { $0.loggedAt >= startDate }
    }

    private var selectedDayWorkouts: [WorkoutSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allWorkouts.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay }
    }

    private var selectedDayLiveWorkouts: [LiveWorkout] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return liveWorkouts.filter { workout in
            workout.startedAt >= startOfDay && workout.startedAt < endOfDay
        }
    }

    /// HealthKit workout IDs that have been merged into LiveWorkouts (to avoid double-counting)
    private var mergedHealthKitIDs: Set<String> {
        Set(liveWorkouts.compactMap { $0.mergedHealthKitWorkoutID })
    }

    /// Workouts for today, excluding HealthKit workouts that were merged into in-app workouts
    private var todayTotalWorkoutCount: Int {
        // Filter out HealthKit workouts that have been merged into LiveWorkouts
        let uniqueHealthKitWorkouts = selectedDayWorkouts.filter { workout in
            guard let hkID = workout.healthKitWorkoutID else { return true }
            return !mergedHealthKitIDs.contains(hkID)
        }
        return uniqueHealthKitWorkouts.count + selectedDayLiveWorkouts.count
    }

    /// Returns the workout name to display on the quick action button
    /// Only shows a name when set to recommended workout and a plan exists
    private var quickAddWorkoutName: String? {
        guard let profile,
              profile.defaultWorkoutActionValue == .recommendedWorkout,
              let plan = profile.workoutPlan else {
            return nil
        }

        let recommendedId = recoveryService.getRecommendedTemplateId(plan: plan, modelContext: modelContext)
        let template = plan.templates.first { $0.id == recommendedId } ?? plan.templates.first
        return template?.name
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Date Navigation
                        DateNavigationBar(
                            selectedDate: $selectedDate,
                            isToday: isViewingToday
                        )

                        if isViewingToday, let profile {
                            GreetingCard(name: profile.name, goal: profile.goal)

                            // Quick action buttons (only on today)
                            QuickActionsCard(
                                onLogFood: { showingLogFood = true },
                                onAddWorkout: { startWorkout() },
                                onLogWeight: { showingLogWeight = true },
                                workoutName: quickAddWorkoutName
                            )

                            // Today's reminders
                            if !todaysReminderItems.isEmpty {
                                TodaysRemindersCard(
                                    reminders: todaysReminderItems,
                                    onReminderTap: { _ in /* Tap to expand/interact */ },
                                    onComplete: completeReminder,
                                    onViewAll: { /* Already viewing on dashboard */ }
                                )
                                .id("reminders-section")
                            }
                        }

                    CalorieProgressCard(
                        consumed: totalCalories,
                        goal: profile?.dailyCalorieGoal ?? 2000,
                        onTap: { showingCalorieDetail = true }
                    )

                    MacroBreakdownCard(
                        protein: totalProtein,
                        carbs: totalCarbs,
                        fat: totalFat,
                        fiber: totalFiber,
                        sugar: totalSugar,
                        proteinGoal: profile?.dailyProteinGoal ?? 150,
                        carbsGoal: profile?.dailyCarbsGoal ?? 200,
                        fatGoal: profile?.dailyFatGoal ?? 65,
                        fiberGoal: profile?.dailyFiberGoal ?? 30,
                        sugarGoal: profile?.dailySugarGoal ?? 50,
                        enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                        onTap: { showingMacroDetail = true }
                    )

                    DailyFoodTimeline(
                        entries: selectedDayFoodEntries,
                        enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                        onAddFood: isViewingToday ? { showingLogFood = true } : nil,
                        onAddToSession: isViewingToday ? { sessionId in
                            sessionIdToAddTo = sessionId
                            showingLogFood = true
                        } : nil,
                        onEditEntry: { entryToEdit = $0 },
                        onDeleteEntry: deleteFoodEntry
                    )

                    TodaysActivityCard(
                        steps: todaySteps,
                        activeCalories: todayActiveCalories,
                        exerciseMinutes: todayExerciseMinutes,
                        workoutCount: todayTotalWorkoutCount,
                        isLoading: isLoadingActivity
                    )

                    if isViewingToday, let latestWeight = weightEntries.first {
                        NavigationLink {
                            WeightTrackingView()
                        } label: {
                            WeightTrendCard(
                                currentWeight: latestWeight.weightKg,
                                targetWeight: profile?.targetWeightKg,
                                useLbs: !(profile?.usesMetricWeight ?? true)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    }
                    .padding()
                }
                .onChange(of: showRemindersBinding) { _, isShowing in
                    // Scroll to reminders section when triggered by notification
                    if isShowing {
                        if remindersLoaded && !todaysReminderItems.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo("reminders-section", anchor: .top)
                            }
                            showRemindersBinding = false
                        } else {
                            // Data not ready yet - wait for it
                            pendingScrollToReminders = true
                        }
                    }
                }
                .onChange(of: remindersLoaded) { _, loaded in
                    // Execute pending scroll after reminders load
                    if loaded && pendingScrollToReminders {
                        if !todaysReminderItems.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo("reminders-section", anchor: .top)
                            }
                        }
                        // Reset state even if no reminders to scroll to
                        pendingScrollToReminders = false
                        showRemindersBinding = false
                    }
                }
            }
            .navigationTitle("Dashboard")
            .task {
                fetchCustomReminders()
                remindersLoaded = true
                await loadActivityData()
            }
            .onChange(of: selectedDate) { _, newDate in
                if Calendar.current.isDateInToday(newDate) {
                    Task { await loadActivityData() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
                // Refresh after workout completed to update muscle recovery
                Task { await loadActivityData() }
            }
            .refreshable {
                await refreshHealthData()
            }
            .fullScreenCover(isPresented: $showingLogFood) {
                FoodCameraView(sessionId: sessionIdToAddTo)
                    .onDisappear {
                        sessionIdToAddTo = nil
                    }
            }
            .sheet(isPresented: $showingLogWeight) {
                LogWeightSheet()
            }
            .sheet(isPresented: $showingWorkoutSheet) {
                if let workout = pendingWorkout {
                    NavigationStack {
                        LiveWorkoutView(workout: workout, template: pendingTemplate)
                    }
                }
            }
            .onChange(of: showingWorkoutSheet) { _, isShowing in
                if !isShowing {
                    pendingTemplate = nil
                }
            }
            .sheet(isPresented: $showingCalorieDetail) {
                CalorieDetailSheet(
                    entries: selectedDayFoodEntries,
                    goal: profile?.dailyCalorieGoal ?? 2000,
                    historicalEntries: last7DaysFoodEntries,
                    onAddFood: isViewingToday ? {
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    } : nil,
                    onEditEntry: { entry in
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            entryToEdit = entry
                        }
                    },
                    onDeleteEntry: deleteFoodEntry
                )
            }
            .sheet(isPresented: $showingMacroDetail) {
                MacroDetailSheet(
                    entries: selectedDayFoodEntries,
                    proteinGoal: profile?.dailyProteinGoal ?? 150,
                    carbsGoal: profile?.dailyCarbsGoal ?? 200,
                    fatGoal: profile?.dailyFatGoal ?? 65,
                    fiberGoal: profile?.dailyFiberGoal ?? 30,
                    sugarGoal: profile?.dailySugarGoal ?? 50,
                    enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                    historicalEntries: last7DaysFoodEntries,
                    onAddFood: isViewingToday ? {
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    } : nil,
                    onEditEntry: { entry in
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            entryToEdit = entry
                        }
                    }
                )
            }
            .sheet(item: $entryToEdit) { entry in
                EditFoodEntrySheet(entry: entry)
            }
        }
    }

    private var totalCalories: Int {
        selectedDayFoodEntries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.fatGrams }
    }

    private var totalFiber: Double {
        selectedDayFoodEntries.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
    }

    private var totalSugar: Double {
        selectedDayFoodEntries.reduce(0) { $0 + ($1.sugarGrams ?? 0) }
    }

    private var todaysReminderItems: [TodaysRemindersCard.ReminderItem] {
        guard let profile else { return [] }

        let enabledMeals = Set(profile.enabledMealReminders.split(separator: ",").map(String.init))
        let workoutDays = Set(profile.workoutReminderDays.split(separator: ",").compactMap { Int($0) })

        let allItems = TodaysRemindersCard.buildReminderItems(
            from: customReminders,
            mealRemindersEnabled: profile.mealRemindersEnabled,
            enabledMeals: enabledMeals,
            workoutRemindersEnabled: profile.workoutRemindersEnabled,
            workoutDays: workoutDays,
            workoutHour: profile.workoutReminderHour,
            workoutMinute: profile.workoutReminderMinute
        )

        // Filter out completed reminders
        return allItems.filter { !todaysCompletedReminderIds.contains($0.id) }
    }

    private func fetchCustomReminders() {
        let descriptor = FetchDescriptor<CustomReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        customReminders = (try? modelContext.fetch(descriptor)) ?? []

        // Fetch today's completed reminder IDs
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let completionDescriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { $0.completedAt >= startOfDay }
        )
        let completions = (try? modelContext.fetch(completionDescriptor)) ?? []
        todaysCompletedReminderIds = Set(completions.map { $0.reminderId })
    }

    private func completeReminder(_ reminder: TodaysRemindersCard.ReminderItem) {
        // Calculate if completed on time (within 30 min of scheduled time)
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentMinutes = currentHour * 60 + currentMinute
        let reminderMinutes = reminder.hour * 60 + reminder.minute
        let wasOnTime = currentMinutes <= reminderMinutes + 30

        // Create and save completion record
        let completion = ReminderCompletion(
            reminderId: reminder.id,
            completedAt: now,
            wasOnTime: wasOnTime
        )
        modelContext.insert(completion)

        // Update local state with animation for smooth removal
        withAnimation(.easeInOut(duration: 0.3)) {
            todaysCompletedReminderIds.insert(reminder.id)
        }

        HapticManager.success()
    }

    private func loadActivityData() async {
        guard isViewingToday else { return }
        isLoadingActivity = true
        defer { isLoadingActivity = false }
        guard let healthKitService else { return }

        do {
            let summary = try await healthKitService.fetchTodayActivitySummaryAuthorized()
            todaySteps = summary.steps
            todayActiveCalories = summary.activeCalories
            todayExerciseMinutes = summary.exerciseMinutes
        } catch {
            // Silently fail - user may not have granted HealthKit permissions
            print("Failed to load activity data: \(error)")
        }
    }

    private func refreshHealthData() async {
        await loadActivityData()
    }

    private func deleteFoodEntry(_ entry: FoodEntry) {
        modelContext.delete(entry)
        HapticManager.success()
    }

    // MARK: - Workout Actions

    private func startWorkout() {
        guard let profile else {
            startCustomWorkout()
            return
        }

        switch profile.defaultWorkoutActionValue {
        case .customWorkout:
            startCustomWorkout()
        case .recommendedWorkout:
            startRecommendedWorkout()
        }
    }

    private func startCustomWorkout() {
        let workout = LiveWorkout(
            name: "Custom Workout",
            workoutType: .strength,
            targetMuscleGroups: []
        )
        modelContext.insert(workout)
        try? modelContext.save()

        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func startRecommendedWorkout() {
        guard let plan = profile?.workoutPlan else {
            // Fall back to custom workout if no plan exists
            startCustomWorkout()
            return
        }

        // Get recommended template based on muscle recovery
        let recommendedId = recoveryService.getRecommendedTemplateId(plan: plan, modelContext: modelContext)
        let template = plan.templates.first { $0.id == recommendedId } ?? plan.templates.first

        guard let template else {
            startCustomWorkout()
            return
        }

        let muscleGroups = LiveWorkout.MuscleGroup.fromTargetStrings(template.targetMuscleGroups)

        let workout = LiveWorkout(
            name: template.name,
            workoutType: .strength,
            targetMuscleGroups: muscleGroups
        )
        modelContext.insert(workout)
        try? modelContext.save()

        pendingTemplate = template
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
