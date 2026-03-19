//
//  DashboardView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

private struct DashboardNutritionTotals {
    var calories: Int = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0

    init() {}

    init(entries: [FoodEntry]) {
        calories = entries.reduce(0) { $0 + $1.calories }
        protein = entries.reduce(0) { $0 + $1.proteinGrams }
        carbs = entries.reduce(0) { $0 + $1.carbsGrams }
        fat = entries.reduce(0) { $0 + $1.fatGrams }
        fiber = entries.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
        sugar = entries.reduce(0) { $0 + ($1.sugarGrams ?? 0) }
    }
}

struct DashboardView: View {
    /// Optional binding to control reminders sheet from parent (for notification taps)
    @Binding var showRemindersBinding: Bool
    let onSelectTab: ((AppTab) -> Void)?

    @Query private var profiles: [UserProfile]
    @Query private var allFoodEntries: [FoodEntry]
    @Query private var insightFoodEntries: [FoodEntry]
    @Query private var allWorkouts: [WorkoutSession]
    @Query private var liveWorkouts: [LiveWorkout]
    @Query private var weightEntries: [WeightEntry]
    @Query private var coachSignals: [CoachSignal]
    @Query private var suggestionUsage: [SuggestionUsage]
    @Query private var behaviorEvents: [BehaviorEvent]

    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService: NotificationService?
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @EnvironmentObject private var activeWorkoutRuntimeState: ActiveWorkoutRuntimeState
    @State private var recoveryService = MuscleRecoveryService.shared
    @State private var workoutTemplateService = WorkoutTemplateService()

    // Custom reminders (fetched manually to avoid @Query freeze)
    @State private var customReminders: [CustomReminder] = []
    @State private var todaysCompletedReminderIds: Set<UUID> = []
    @State private var remindersLoaded = false
    @State private var pendingScrollToReminders = false
    @State private var reminderCompletionHistory: [ReminderCompletion] = []
    @State private var cachedRecommendedTemplateId: UUID?
    @State private var didPrimeInitialData = false
    @State private var coachContextRefreshTask: Task<Void, Never>?
    @State private var deferredInitialLoadTask: Task<Void, Never>?
    @State private var remindersLoadTask: Task<Void, Never>?
    @State private var hasPerformedDeferredStartupWork = false
    @State private var isDashboardTabVisible = false
    @State private var latencyProbeEntries: [String] = []
    @State private var tabActivationPolicy = TabActivationPolicy(minimumDwellMilliseconds: 0)
    private let reminderCompletionHistoryCapPerWindow = 180

    // Sheet presentation state
    @State private var foodCameraPresentation: FoodCameraPresentation?
    @State private var isPreparingFoodCamera = false
    @State private var showingLogWeight = false
    @State private var showingWeightTracking = false
    @State private var showingCalorieDetail = false
    @State private var showingMacroDetail = false
    @State private var entryToEdit: FoodEntry?

    // Workout sheet state
    @State private var showingWorkoutSheet = false
    @State private var pendingWorkout: LiveWorkout?
    @State private var pendingTemplate: WorkoutPlan.WorkoutTemplate?
    @AppStorage("pendingPlanReviewRequest") var pendingPlanReviewRequest = false
    @AppStorage("pendingWorkoutPlanReviewRequest") var pendingWorkoutPlanReviewRequest = false
    private static let dashboardHistoryWindowDays = 100
    private static let dashboardFastFoodWindowDays = 2
    private static let behaviorHistoryWindowDays = 90
    private static let dashboardEntryFetchLimit = 48
    private static let dashboardFastFoodFetchLimit = 72
    private static let dashboardInsightFoodWindowDays = 45
    private static let dashboardInsightFoodFetchLimit = 360
    private static let dashboardLazyFoodTrendWindowDays = 7
    private static let dashboardHistoricalFoodFetchLimit = 240
    private static let behaviorEventFetchLimit = 90
    private static let coachSignalFetchLimit = 48
    private static let suggestionUsageFetchLimit = 64
    private static var deferredStartupWorkDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2400 : 420
    }
    private static var dashboardResumeDeferredWorkDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1800 : 220
    }
    private static var remindersInitialLoadDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1400 : 120
    }
    private static var coachContextRefreshDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1200 : 180
    }
    private static var dashboardHeavyRefreshMinimumDwellMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1600 : 320
    }

    init(
        showRemindersBinding: Binding<Bool> = .constant(false),
        onSelectTab: ((AppTab) -> Void)? = nil
    ) {
        _showRemindersBinding = showRemindersBinding
        self.onSelectTab = onSelectTab

        let now = Date()
        let calendar = Calendar.current
        let historyCutoff = calendar.date(
            byAdding: .day,
            value: -Self.dashboardHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let foodFastWindowCutoff = calendar.date(
            byAdding: .day,
            value: -(Self.dashboardFastFoodWindowDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? historyCutoff
        let insightFoodWindowCutoff = calendar.date(
            byAdding: .day,
            value: -Self.dashboardInsightFoodWindowDays,
            to: now
        ) ?? .distantPast
        let behaviorCutoff = calendar.date(
            byAdding: .day,
            value: -Self.behaviorHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let coachSignalCutoff = calendar.date(
            byAdding: .day,
            value: -30,
            to: now
        ) ?? .distantPast

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        _profiles = Query(profileDescriptor)

        var foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.loggedAt >= foodFastWindowCutoff },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        foodDescriptor.fetchLimit = Self.dashboardFastFoodFetchLimit
        _allFoodEntries = Query(foodDescriptor)

        var insightFoodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.loggedAt >= insightFoodWindowCutoff },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        insightFoodDescriptor.fetchLimit = Self.dashboardInsightFoodFetchLimit
        _insightFoodEntries = Query(insightFoodDescriptor)

        var workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.loggedAt >= historyCutoff },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = Self.dashboardEntryFetchLimit
        _allWorkouts = Query(workoutDescriptor)

        var liveWorkoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { $0.startedAt >= historyCutoff },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        liveWorkoutDescriptor.fetchLimit = Self.dashboardEntryFetchLimit
        _liveWorkouts = Query(liveWorkoutDescriptor)

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate<WeightEntry> { $0.loggedAt >= historyCutoff },
            sortBy: [SortDescriptor(\WeightEntry.loggedAt, order: .reverse)]
        )
        weightDescriptor.fetchLimit = Self.dashboardEntryFetchLimit
        _weightEntries = Query(weightDescriptor)

        var behaviorDescriptor = FetchDescriptor<BehaviorEvent>(
            predicate: #Predicate<BehaviorEvent> { $0.occurredAt >= behaviorCutoff },
            sortBy: [SortDescriptor(\BehaviorEvent.occurredAt, order: .reverse)]
        )
        behaviorDescriptor.fetchLimit = Self.behaviorEventFetchLimit
        _behaviorEvents = Query(behaviorDescriptor)

        var coachSignalDescriptor = FetchDescriptor<CoachSignal>(
            predicate: #Predicate<CoachSignal> {
                !$0.isResolved && $0.createdAt >= coachSignalCutoff
            },
            sortBy: [SortDescriptor(\CoachSignal.createdAt, order: .reverse)]
        )
        coachSignalDescriptor.fetchLimit = Self.coachSignalFetchLimit
        _coachSignals = Query(coachSignalDescriptor)

        var suggestionDescriptor = FetchDescriptor<SuggestionUsage>(
            sortBy: [SortDescriptor(\SuggestionUsage.tapCount, order: .reverse)]
        )
        suggestionDescriptor.fetchLimit = Self.suggestionUsageFetchLimit
        _suggestionUsage = Query(suggestionDescriptor)
    }

    // Date navigation
    @State private var selectedDate = Date()

    // Activity data from HealthKit
    @State private var todaySteps = 0
    @State private var todayActiveCalories = 0
    @State private var todayExerciseMinutes = 0
    @State private var isLoadingActivity = false
    @State private var cachedSelectedDayFoodEntries: [FoodEntry] = []
    @State private var cachedLast7DaysFoodEntries: [FoodEntry] = []
    @State private var cachedOnDemandFoodTrendEntries: [FoodEntry] = []
    @State private var cachedOnDemandFoodTrendAnchor: Date?
    @State private var cachedSelectedDayWorkouts: [WorkoutSession] = []
    @State private var cachedSelectedDayLiveWorkouts: [LiveWorkout] = []
    @State private var selectedDayNutritionTotals = DashboardNutritionTotals()

    private let reminderHabitWindowDays = 30

    private var profile: UserProfile? { profiles.first }

    private var isDashboardTabActive: Bool {
        isDashboardTabVisible
    }

    private var shouldDeferCoachContextRefreshDuringStartup: Bool {
        false
    }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var foodEntriesRefreshFingerprint: String {
        guard !allFoodEntries.isEmpty else { return "0" }
        var parts: [String] = []
        parts.reserveCapacity(1 + (allFoodEntries.count * 8))
        parts.append(String(allFoodEntries.count))
        for entry in allFoodEntries {
            parts.append(entry.id.uuidString)
            parts.append(String(entry.loggedAt.timeIntervalSinceReferenceDate))
            parts.append(String(entry.calories))
            parts.append(String(entry.proteinGrams))
            parts.append(String(entry.carbsGrams))
            parts.append(String(entry.fatGrams))
            parts.append(String(entry.fiberGrams ?? -1))
            parts.append(String(entry.sugarGrams ?? -1))
        }
        return parts.joined(separator: "|")
    }

    private var weightEntriesRefreshFingerprint: String {
        guard !weightEntries.isEmpty else { return "0" }
        var parts: [String] = []
        parts.reserveCapacity(1 + (weightEntries.count * 4))
        parts.append(String(weightEntries.count))
        for entry in weightEntries {
            parts.append(entry.id.uuidString)
            parts.append(String(entry.loggedAt.timeIntervalSinceReferenceDate))
            parts.append(String(entry.weightKg))
            parts.append(String(entry.bodyFatPercentage ?? -1))
        }
        return parts.joined(separator: "|")
    }

    private var coachSignalsRefreshFingerprint: String {
        guard !coachSignals.isEmpty else { return "0" }
        var parts: [String] = []
        parts.reserveCapacity(1 + (coachSignals.count * 8))
        parts.append(String(coachSignals.count))
        for signal in coachSignals {
            parts.append(signal.id.uuidString)
            parts.append(String(signal.createdAt.timeIntervalSinceReferenceDate))
            parts.append(String(signal.expiresAt.timeIntervalSinceReferenceDate))
            parts.append(signal.title)
            parts.append(signal.detail)
            parts.append(String(signal.severity))
            parts.append(String(signal.confidence))
            parts.append(signal.isResolved ? "1" : "0")
        }
        return parts.joined(separator: "|")
    }

    private var behaviorEventsRefreshFingerprint: String {
        guard !behaviorEvents.isEmpty else { return "0" }
        var parts: [String] = []
        parts.reserveCapacity(1 + (behaviorEvents.count * 5))
        parts.append(String(behaviorEvents.count))
        for event in behaviorEvents {
            parts.append(event.id.uuidString)
            parts.append(String(event.occurredAt.timeIntervalSinceReferenceDate))
            parts.append(event.actionKey)
            parts.append(event.domainRaw)
            parts.append(event.outcomeRaw)
        }
        return parts.joined(separator: "|")
    }

    private var suggestionUsageRefreshFingerprint: String {
        guard !suggestionUsage.isEmpty else { return "0" }
        var parts: [String] = []
        parts.reserveCapacity(1 + (suggestionUsage.count * 5))
        parts.append(String(suggestionUsage.count))
        for usage in suggestionUsage {
            parts.append(usage.id.uuidString)
            parts.append(usage.suggestionType)
            parts.append(String(usage.tapCount))
            parts.append(String(usage.lastTapped?.timeIntervalSinceReferenceDate ?? 0))
            parts.append(String(usage.hourlyTapsData?.count ?? 0))
        }
        return parts.joined(separator: "|")
    }

    private var selectedDayFoodEntries: [FoodEntry] { cachedSelectedDayFoodEntries }

    /// Last 7 days of food entries for trend charts
    private var last7DaysFoodEntries: [FoodEntry] { cachedLast7DaysFoodEntries }

    /// Detail sheets read a lazy-loaded 7-day history keyed to the selected date.
    private var detailSheetHistoricalFoodEntries: [FoodEntry] {
        let selectedStart = Calendar.current.startOfDay(for: selectedDate)
        if cachedOnDemandFoodTrendAnchor == selectedStart {
            return cachedOnDemandFoodTrendEntries
        }
        return last7DaysFoodEntries
    }

    private var selectedDayWorkouts: [WorkoutSession] { cachedSelectedDayWorkouts }

    private var selectedDayLiveWorkouts: [LiveWorkout] { cachedSelectedDayLiveWorkouts }

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

        if let cachedId = cachedRecommendedTemplateId,
           let template = plan.templates.first(where: { $0.id == cachedId }) {
            return template.name
        }

        return plan.templates.first?.name
    }

    private var hasActiveLiveWorkout: Bool {
        liveWorkouts.contains { $0.completedAt == nil }
    }

    private func computeRecommendedTemplateId() -> UUID? {
        guard isViewingToday, let plan = profile?.workoutPlan else { return nil }

        let startedAt = LatencyProbe.timerStart()
        defer {
            recordDashboardLatencyProbe(
                "computeRecommendedTemplateId",
                startedAt: startedAt,
                counts: [
                    "templates": plan.templates.count,
                    "workouts": allWorkouts.count,
                    "liveWorkouts": liveWorkouts.count
                ]
            )
        }

        return recoveryService.getRecommendedTemplateId(
            plan: plan,
            modelContext: modelContext
        ) ?? plan.templates.first?.id
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DashboardTopGradient()
                ScrollViewReader { scrollProxy in
                    GeometryReader { geometry in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 18) {
                            // Date Navigation
                            DateNavigationBar(
                                selectedDate: $selectedDate,
                                isToday: isViewingToday
                            )

                            if isViewingToday, profile != nil {
                                // Quick action buttons (only on today)
                                QuickActionsCard(
                                    onLogFood: { openFoodCameraFromDashboard(source: "quick_actions") },
                                    onAddWorkout: { startWorkout() },
                                    onLogWeight: { openLogWeightFromDashboard(source: "quick_actions") },
                                    workoutName: quickAddWorkoutName
                                )
                                .traiEntrance(index: 0)

                                ChatWithTraiCard(action: { openTraiChatFromDashboard() })
                                    .traiEntrance(index: 1)

                                // Today's reminders
                                if !todaysReminderItems.isEmpty {
                                    TodaysRemindersCard(
                                        reminders: todaysReminderItems,
                                        onReminderTap: { _ in /* Tap to expand/interact */ },
                                        onComplete: completeReminder,
                                        onViewAll: { /* Already viewing on dashboard */ }
                                    )
                                    .id("reminders-section")
                                    .traiEntrance(index: 2)
                                }
                            }

                            CalorieProgressCard(
                                consumed: totalCalories,
                                goal: profile?.dailyCalorieGoal ?? 2000,
                                onTap: { openCalorieDetailFromDashboard(source: "calorie_progress_card") }
                            )
                            .traiEntrance(index: 3)

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
                                onTap: { openMacroDetailFromDashboard(source: "macro_breakdown_card") }
                            )
                            .traiEntrance(index: 4)

                            DailyFoodTimeline(
                                entries: selectedDayFoodEntries,
                                enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                                onAddFood: isViewingToday ? { openFoodCameraFromDashboard(source: "food_timeline_add") } : nil,
                                onAddToSession: isViewingToday ? { sessionId in
                                    openFoodCameraFromDashboard(source: "food_timeline_add_to_session", sessionId: sessionId)
                                } : nil,
                                onEditEntry: { entryToEdit = $0 },
                                onDeleteEntry: deleteFoodEntry
                            )
                            .traiEntrance(index: 5)

                            TodaysActivityCard(
                                steps: todaySteps,
                                activeCalories: todayActiveCalories,
                                exerciseMinutes: todayExerciseMinutes,
                                workoutCount: todayTotalWorkoutCount,
                                isLoading: isLoadingActivity
                            )
                            .traiEntrance(index: 6)

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
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        trackOpenWeightFromDashboard(source: "weight_trend_card")
                                    }
                                )
                                .buttonStyle(.plain)
                                .traiEntrance(index: 7)
                            }
                            }
                            .frame(width: max(0, geometry.size.width - 32), alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
            .task {
                guard !didPrimeInitialData else { return }
                didPrimeInitialData = true
                if showRemindersBinding {
                    pendingScrollToReminders = true
                }
                await Task.yield()
                refreshDateScopedCaches()
                scheduleRemindersLoad(
                    delayMilliseconds: Self.remindersInitialLoadDelayMilliseconds
                )
                scheduleDeferredStartupWork(
                    delayMilliseconds: Self.deferredStartupWorkDelayMilliseconds
                )
            }
            .onAppear {
                if tabActivationPolicy.activeSince == nil {
                    tabActivationPolicy = TabActivationPolicy(
                        minimumDwellMilliseconds: Self.dashboardHeavyRefreshMinimumDwellMilliseconds
                    )
                }
                tabActivationPolicy.activate()
                isDashboardTabVisible = true
                guard didPrimeInitialData else { return }

                if showRemindersBinding {
                    pendingScrollToReminders = true
                }
                if !remindersLoaded {
                    scheduleRemindersLoad(delayMilliseconds: 0)
                }

                refreshDateScopedCaches()
                if isViewingToday {
                    Task {
                        await loadActivityData()
                    }
                }

                if !hasPerformedDeferredStartupWork {
                    scheduleDeferredStartupWork(
                        delayMilliseconds: Self.dashboardResumeDeferredWorkDelayMilliseconds
                    )
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                refreshDateScopedCaches()
                if Calendar.current.isDateInToday(newDate) {
                    Task {
                        await loadActivityData()
                    }
                }
            }
            .onChange(of: foodEntriesRefreshFingerprint) { _, _ in
                guard isDashboardTabActive else { return }
                refreshFoodDateCaches()
            }
            .onChange(of: allWorkouts.count) {
                guard isDashboardTabActive else { return }
                refreshWorkoutDateCache()
                if isViewingToday {
                    scheduleCoachContextRefresh(forceRefresh: true)
                }
            }
            .onChange(of: liveWorkouts.count) {
                guard isDashboardTabActive else { return }
                refreshLiveWorkoutDateCache()
                if isViewingToday {
                    scheduleCoachContextRefresh(forceRefresh: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
                guard isDashboardTabActive else { return }
                // Refresh after workout completed to update muscle recovery
                Task {
                    await loadActivityData()
                }
            }
            .onChange(of: activeWorkoutRuntimeState.isLiveWorkoutPresented) { _, isPresented in
                guard isDashboardTabActive else { return }
                if !isPresented {
                    guard !hasActiveLiveWorkout else { return }
                }
            }
            .onDisappear {
                isDashboardTabVisible = false
                tabActivationPolicy.deactivate()
                deferredInitialLoadTask?.cancel()
                remindersLoadTask?.cancel()
            }
            .refreshable {
                await refreshHealthData()
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
            .sheet(isPresented: $showingWeightTracking) {
                WeightTrackingView()
            }
            .sheet(isPresented: $showingWorkoutSheet) {
                if let workout = pendingWorkout {
                    LiveWorkoutView(workout: workout, template: pendingTemplate)
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
                    historicalEntries: detailSheetHistoricalFoodEntries,
                    onAddFood: isViewingToday ? {
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            presentFoodCamera()
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
                    historicalEntries: detailSheetHistoricalFoodEntries,
                    onAddFood: isViewingToday ? {
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            presentFoodCamera()
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
            .overlay(alignment: .topLeading) {
                Text("ready")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("dashboardRootReady")
            }
            .overlay(alignment: .topLeading) {
                Text(dashboardLatencyProbeLabel)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dashboardLatencyProbeLabel)
                    .accessibilityIdentifier("dashboardLatencyProbe")
            }
            }
        }
        .traiBackground()
    }

    private var dashboardLatencyProbeLabel: String {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return "disabled" }
        return latencyProbeEntries.isEmpty ? "pending" : latencyProbeEntries.joined(separator: " | ")
    }

    private func recordDashboardLatencyProbe(
        _ operation: String,
        startedAt: UInt64,
        counts: [String: Int] = [:]
    ) {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return }
        let entry = LatencyProbe.makeEntry(
            operation: operation,
            durationMilliseconds: LatencyProbe.elapsedMilliseconds(since: startedAt),
            counts: counts
        )
        LatencyProbe.append(entry: entry, to: &latencyProbeEntries)
    }

    private func refreshDateScopedCaches() {
        let interval = PerformanceTrace.begin("dashboard_date_cache_refresh", category: .dataLoad)
        let startedAt = LatencyProbe.timerStart()
        defer {
            PerformanceTrace.end("dashboard_date_cache_refresh", interval, category: .dataLoad)
            recordDashboardLatencyProbe(
                "refreshDateScopedCaches",
                startedAt: startedAt,
                counts: [
                    "food": allFoodEntries.count,
                    "workouts": allWorkouts.count,
                    "liveWorkouts": liveWorkouts.count
                ]
            )
        }
        refreshFoodDateCaches()
        refreshWorkoutDateCache()
        refreshLiveWorkoutDateCache()
    }

    private func scheduleDeferredStartupWork(delayMilliseconds: Int) {
        deferredInitialLoadTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        deferredInitialLoadTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                runDeferredStartupWorkIfNeeded()
            }
        }
    }

    @MainActor
    private func runDeferredStartupWorkIfNeeded() {
        guard !hasPerformedDeferredStartupWork else { return }
        guard isDashboardTabActive else { return }

        hasPerformedDeferredStartupWork = true
        Task(priority: .utility) { @MainActor in
            guard isDashboardTabActive else { return }
            _ = CoachSignalService(modelContext: modelContext).pruneExpiredSignals()
        }
        Task { @MainActor in
            guard isDashboardTabActive else { return }
            await loadActivityData()
        }
        scheduleCoachContextRefresh(forceRefresh: true, immediate: true)
    }

    private func refreshFoodDateCaches() {
        let startedAt = LatencyProbe.timerStart()
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedDate)
        guard let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart) else { return }
        let fastWindowCutoff = calendar.date(
            byAdding: .day,
            value: -(Self.dashboardFastFoodWindowDays - 1),
            to: calendar.startOfDay(for: .now)
        ) ?? .distantPast
        let selectedDateInFastWindow = selectedStart >= fastWindowCutoff

        if selectedDateInFastWindow {
            cachedSelectedDayFoodEntries = allFoodEntries.filter {
                $0.loggedAt >= selectedStart && $0.loggedAt < selectedEnd
            }
        } else {
            cachedSelectedDayFoodEntries = fetchFoodEntries(start: selectedStart, end: selectedEnd)
        }
        selectedDayNutritionTotals = DashboardNutritionTotals(entries: cachedSelectedDayFoodEntries)

        let todayStart = calendar.startOfDay(for: Date())
        if let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
           let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) {
            cachedLast7DaysFoodEntries = fetchFoodEntries(start: sevenDayStart, end: tomorrowStart)
        } else {
            cachedLast7DaysFoodEntries = []
        }
        if cachedOnDemandFoodTrendAnchor != selectedStart {
            cachedOnDemandFoodTrendEntries = []
            cachedOnDemandFoodTrendAnchor = nil
        }
        recordDashboardLatencyProbe(
            "refreshFoodDateCaches",
            startedAt: startedAt,
            counts: [
                "allFood": allFoodEntries.count,
                "fastWindow": selectedDateInFastWindow ? 1 : 0,
                "selectedFood": cachedSelectedDayFoodEntries.count,
                "last7Food": cachedLast7DaysFoodEntries.count
            ]
        )
    }

    private func fetchFoodEntries(start: Date, end: Date) -> [FoodEntry] {
        let from = start
        let to = end
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> {
                $0.loggedAt >= from && $0.loggedAt < to
            },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.dashboardHistoricalFoodFetchLimit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadFoodTrendHistoryForSelectedDateIfNeeded() {
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedDate)
        guard cachedOnDemandFoodTrendAnchor != selectedStart else { return }
        guard
            let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart),
            let trendStart = calendar.date(
                byAdding: .day,
                value: -(Self.dashboardLazyFoodTrendWindowDays - 1),
                to: selectedStart
            )
        else { return }

        let startedAt = LatencyProbe.timerStart()
        cachedOnDemandFoodTrendEntries = fetchFoodEntries(start: trendStart, end: selectedEnd)
        cachedOnDemandFoodTrendAnchor = selectedStart
        recordDashboardLatencyProbe(
            "loadFoodTrendHistoryForSelectedDate",
            startedAt: startedAt,
            counts: [
                "trendFood": cachedOnDemandFoodTrendEntries.count,
                "days": Self.dashboardLazyFoodTrendWindowDays
            ]
        )
    }

    private func refreshWorkoutDateCache() {
        let startedAt = LatencyProbe.timerStart()
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedDate)
        guard let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart) else { return }

        cachedSelectedDayWorkouts = allWorkouts.filter {
            $0.loggedAt >= selectedStart && $0.loggedAt < selectedEnd
        }
        recordDashboardLatencyProbe(
            "refreshWorkoutDateCache",
            startedAt: startedAt,
            counts: [
                "allWorkouts": allWorkouts.count,
                "selectedWorkouts": cachedSelectedDayWorkouts.count
            ]
        )
    }

    private func refreshLiveWorkoutDateCache() {
        let startedAt = LatencyProbe.timerStart()
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedDate)
        guard let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart) else { return }

        cachedSelectedDayLiveWorkouts = liveWorkouts.filter {
            $0.startedAt >= selectedStart && $0.startedAt < selectedEnd
        }
        recordDashboardLatencyProbe(
            "refreshLiveWorkoutDateCache",
            startedAt: startedAt,
            counts: [
                "allLive": liveWorkouts.count,
                "selectedLive": cachedSelectedDayLiveWorkouts.count
            ]
        )
    }

    private var totalCalories: Int {
        selectedDayNutritionTotals.calories
    }

    private var totalProtein: Double {
        selectedDayNutritionTotals.protein
    }

    private var totalCarbs: Double {
        selectedDayNutritionTotals.carbs
    }

    private var totalFat: Double {
        selectedDayNutritionTotals.fat
    }

    private var totalFiber: Double {
        selectedDayNutritionTotals.fiber
    }

    private var totalSugar: Double {
        selectedDayNutritionTotals.sugar
    }

    private var todaysReminderItems: [TodaysRemindersCard.ReminderItem] {
        guard remindersLoaded, let profile else { return [] }

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

    private var todaysReminderItemsAll: [TodaysRemindersCard.ReminderItem] {
        guard remindersLoaded, let profile else { return [] }

        return TodaysRemindersCard.buildReminderItems(
            from: customReminders,
            mealRemindersEnabled: profile.mealRemindersEnabled,
            enabledMeals: Set(profile.enabledMealReminders.split(separator: ",").map(String.init)),
            workoutRemindersEnabled: profile.workoutRemindersEnabled,
            workoutDays: Set(profile.workoutReminderDays.split(separator: ",").compactMap { Int($0) }),
            workoutHour: profile.workoutReminderHour,
            workoutMinute: profile.workoutReminderMinute
        )
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    private var todaysReminderCompletionRate: Double? {
        guard !todaysReminderItemsAll.isEmpty else { return nil }
        let completed = todaysReminderItemsAll.filter { todaysCompletedReminderIds.contains($0.id) }.count
        return Double(completed) / Double(todaysReminderItemsAll.count)
    }

    private var todaysMissedReminderCount: Int? {
        guard !todaysReminderItemsAll.isEmpty else { return nil }
        return max(0, todaysReminderItemsAll.count - todaysReminderItems.count)
    }

    private var daysSinceLastWeightLog: Int? {
        guard let latest = weightEntries.first else { return nil }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latest.loggedAt)
        let today = calendar.startOfDay(for: Date())
        let delta = calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0
        return max(delta, 0)
    }

    private var loggedWeightThisWeek: Bool? {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) else {
            return nil
        }
        return weightEntries.contains { $0.loggedAt >= weekStart }
    }

    private var inferredWeightLogWeekdays: [String] {
        let recentWeightEntries = Array(weightEntries.prefix(12))
        guard recentWeightEntries.count >= 3 else { return [] }

        let weekdayCounts = recentWeightEntries.reduce(into: [Int: Int]()) { counts, entry in
            let weekday = Calendar.current.component(.weekday, from: entry.loggedAt)
            counts[weekday, default: 0] += 1
        }

        let sortedDays = weekdayCounts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }

        guard let topCount = sortedDays.first?.value, topCount >= 2 else { return [] }
        let threshold = max(2, Int(Double(topCount) * 0.5.rounded(.up)))

        return sortedDays
            .filter { $0.value >= threshold }
            .compactMap { weekday in
                switch weekday.key {
                case 1: return "Sunday"
                case 2: return "Monday"
                case 3: return "Tuesday"
                case 4: return "Wednesday"
                case 5: return "Thursday"
                case 6: return "Friday"
                case 7: return "Saturday"
                default: return nil
                }
            }
    }

    private var inferredWeightLogTimes: [String] {
        let recentWeightEntries = Array(weightEntries.prefix(10))
        guard recentWeightEntries.count >= 3 else { return [] }

        let timeCounts = recentWeightEntries.reduce(into: [String: Int]()) { counts, entry in
            let hour = Calendar.current.component(.hour, from: entry.loggedAt)
            let bucket: String
            switch hour {
            case 4..<9:
                bucket = "Morning (4-9 AM)"
            case 9..<12:
                bucket = "Late Morning (9-12 PM)"
            case 12..<15:
                bucket = "Early Afternoon (12-3 PM)"
            case 15..<18:
                bucket = "Mid-Afternoon (3-6 PM)"
            case 18..<22:
                bucket = "Evening (6-10 PM)"
            default:
                bucket = "Night (10 PM-4 AM)"
            }
            counts[bucket, default: 0] += 1
        }

        guard !timeCounts.isEmpty else { return [] }
        let topCount = timeCounts.values.max() ?? 0
        guard topCount >= 2 else { return [] }
        let threshold = max(2, Int(Double(topCount) * 0.5.rounded(.up)))

        return timeCounts
            .filter { $0.value >= threshold }
            .keys
            .sorted()
    }

    private var inferredWeightLogRoutineScore: Double {
        guard weightEntries.count >= 4 else { return 0 }
        guard let daysSince = daysSinceLastWeightLog else { return 0 }

        let calendar = Calendar.current
        let currentWeekday = weekdayLabel(for: calendar.component(.weekday, from: Date()))
        let currentHour = calendar.component(.hour, from: Date())
        let isUsualWeekday = inferredWeightLogWeekdays.contains(currentWeekday)
        let isUsualTime = matchingWeightLogWindow(hour: currentHour, windows: inferredWeightLogTimes) != nil

        let daysSinceScore = min(Double(daysSince), 10.0) / 20.0
        let recurrenceScore = isUsualWeekday ? 0.22 : 0.0
        let timeScore = isUsualTime ? 0.2 : 0.0
        let volumeScore = min(Double(min(weightEntries.count, 20)), 20.0) / 100.0
        let routinePenalty = isUsualWeekday && isUsualTime ? 0.0 : -0.12

        return clamp(daysSinceScore + recurrenceScore + timeScore + volumeScore + routinePenalty)
    }

    private func weekdayLabel(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }

    private func matchingWeightLogWindow(hour: Int, windows: [String]) -> String? {
        guard (0...23).contains(hour) else { return nil }

        for window in windows {
            switch window {
            case "Morning (4-9 AM)":
                if (4...8).contains(hour) { return "morning window" }
            case "Late Morning (9-12 PM)":
                if (9...11).contains(hour) { return "late morning window" }
            case "Early Afternoon (12-3 PM)":
                if (12...14).contains(hour) { return "early afternoon window" }
            case "Mid-Afternoon (3-6 PM)":
                if (15...17).contains(hour) { return "mid afternoon window" }
            case "Evening (6-10 PM)":
                if (18...21).contains(hour) { return "evening window" }
            case "Night (10 PM-4 AM)":
                if hour >= 22 || hour <= 3 { return "night window" }
            default:
                continue
            }
        }

        return nil
    }

    private var recentWeightRangeKg: Double? {
        let recentWeightEntries = Array(weightEntries.prefix(20))
        guard recentWeightEntries.count >= 5 else { return nil }

        let weights = recentWeightEntries.map(\.weightKg)
        guard let minWeight = weights.min(), let maxWeight = weights.max() else { return nil }

        return maxWeight - minWeight
    }

    private var pendingPlanReviewRecommendation: PlanRecommendation? {
        guard let profile else { return nil }
        return PlanAssessmentService().checkForRecommendation(
            profile: profile,
            weightEntries: Array(weightEntries),
            foodEntries: Array(insightFoodEntries)
        )
    }

    private var pendingPlanReviewMessage: String? {
        guard
            let profile,
            let recommendation = pendingPlanReviewRecommendation
        else { return nil }
        return PlanAssessmentService().getRecommendationMessage(
            recommendation,
            useLbs: !(profile.usesMetricWeight)
        )
    }

    private var lastRecentWorkoutAt: Date? {
        let referenceDate = Date()
        let recentWorkoutDate = (allWorkouts.map(\.loggedAt) + liveWorkouts.map { $0.completedAt ?? $0.startedAt })
            .filter { $0 <= referenceDate }
        guard let latest = recentWorkoutDate.max() else { return nil }
        return latest
    }

    private var lastRecentCompletedWorkoutName: String? {
        let referenceDate = Date()

        let latestLoggedWorkout = allWorkouts
            .filter { $0.loggedAt <= referenceDate }
            .max { $0.loggedAt < $1.loggedAt }
            .map { workout -> (date: Date, name: String) in
                let name = workout.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return (workout.loggedAt, name.isEmpty ? "Workout" : name)
            }

        let latestCompletedLiveWorkout = liveWorkouts
            .compactMap { workout -> (date: Date, name: String)? in
                guard let completedAt = workout.completedAt, completedAt <= referenceDate else {
                    return nil
                }
                let rawName = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = rawName.isEmpty ? "\(workout.type.displayName) Workout" : rawName
                return (completedAt, resolvedName)
            }
            .max { $0.date < $1.date }

        switch (latestLoggedWorkout, latestCompletedLiveWorkout) {
        case let (logged?, live?):
            return logged.date >= live.date ? logged.name : live.name
        case let (logged?, nil):
            return logged.name
        case let (nil, live?):
            return live.name
        case (nil, nil):
            return nil
        }
    }

    private var lastRecentWorkoutHour: Int? {
        guard let latest = lastRecentWorkoutAt else { return nil }
        return Calendar.current.component(.hour, from: latest)
    }

    private func fetchCustomReminders() {
        let startedAt = LatencyProbe.timerStart()
        let descriptor = FetchDescriptor<CustomReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        customReminders = (try? modelContext.fetch(descriptor)) ?? []

        let now = Date()
        let lookbackStart = Calendar.current.date(byAdding: .day, value: -reminderHabitWindowDays, to: now) ?? now
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let completionDescriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { $0.completedAt >= lookbackStart },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        var limitedCompletionDescriptor = completionDescriptor
        limitedCompletionDescriptor.fetchLimit = reminderCompletionHistoryCapPerWindow
        let completions = (try? modelContext.fetch(limitedCompletionDescriptor)) ?? []
        reminderCompletionHistory = completions
        trimReminderCompletionHistory(to: now)
        todaysCompletedReminderIds = Set(
            completions
                .filter { $0.completedAt >= startOfDay }
                .map { $0.reminderId }
        )
        recordDashboardLatencyProbe(
            "fetchCustomReminders",
            startedAt: startedAt,
            counts: [
                "customReminders": customReminders.count,
                "completionHistory": reminderCompletionHistory.count,
                "completedToday": todaysCompletedReminderIds.count
            ]
        )
    }

    private func scheduleRemindersLoad(delayMilliseconds: Int = 0) {
        remindersLoadTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        remindersLoadTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                fetchCustomReminders()
                remindersLoaded = true
            }
        }
    }

    private func trimReminderCompletionHistory(to referenceDate: Date) {
        let start = Calendar.current.date(
            byAdding: .day,
            value: -reminderHabitWindowDays,
            to: referenceDate
        ) ?? referenceDate

        reminderCompletionHistory.removeAll { $0.completedAt < start }
        while reminderCompletionHistory.count > reminderCompletionHistoryCapPerWindow {
            reminderCompletionHistory.removeLast()
        }
    }

    private func completeReminder(_ reminder: TodaysRemindersCard.ReminderItem) {
        if todaysCompletedReminderIds.contains(reminder.id) {
            notificationService?.cancelPendingRequest(identifier: reminder.pendingNotificationIdentifier)
            return
        }

        // Calculate if completed on time (within 30 min of scheduled time)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let reminderID = reminder.id
        let existingDescriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { completion in
                completion.reminderId == reminderID && completion.completedAt >= startOfDay
            }
        )
        if let existing = try? modelContext.fetch(existingDescriptor), !existing.isEmpty {
            _ = withAnimation(.easeInOut(duration: 0.3)) {
                todaysCompletedReminderIds.insert(reminder.id)
            }
            notificationService?.cancelPendingRequest(identifier: reminder.pendingNotificationIdentifier)
            return
        }

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
        do {
            try modelContext.save()
        } catch {
            print("Failed to save reminder completion: \(error)")
        }
        reminderCompletionHistory.insert(completion, at: 0)
        trimReminderCompletionHistory(to: now)

        // Update local state with animation for smooth removal
        _ = withAnimation(.easeInOut(duration: 0.3)) {
            todaysCompletedReminderIds.insert(reminder.id)
        }
        notificationService?.cancelPendingRequest(identifier: reminder.pendingNotificationIdentifier)

        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.completeReminder,
            domain: .reminder,
            surface: .dashboard,
            outcome: .completed,
            relatedEntityId: reminder.id,
            metadata: [
                "title": reminder.title,
                "time": reminder.time
            ]
        )

        scheduleCoachContextRefresh(forceRefresh: true, immediate: true)
        HapticManager.success()
    }

    private func loadActivityData() async {
        let interval = PerformanceTrace.begin("dashboard_activity_summary_load", category: .dataLoad)
        defer { PerformanceTrace.end("dashboard_activity_summary_load", interval, category: .dataLoad) }

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
        scheduleCoachContextRefresh(forceRefresh: true, immediate: true)
    }

    private func scheduleCoachContextRefresh(forceRefresh: Bool = false, immediate: Bool = false) {
        coachContextRefreshTask?.cancel()
        let requestedDelayMilliseconds = immediate ? 0 : Self.coachContextRefreshDelayMilliseconds
        let activationToken = tabActivationPolicy.activationToken
        let delayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: requestedDelayMilliseconds
        )
        coachContextRefreshTask = Task(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isDashboardTabActive else { return }
                refreshRecommendedTemplateCacheIfNeeded(forceRefresh: forceRefresh)
            }
        }
    }

    private func refreshRecommendedTemplateCacheIfNeeded(forceRefresh: Bool = false) {
        let shouldRefresh = forceRefresh || DashboardRefreshPolicy.shouldRefreshRecovery(
            isWorkoutRuntimeActive: activeWorkoutRuntimeState.isLiveWorkoutPresented || hasActiveLiveWorkout
        )
        guard shouldRefresh || cachedRecommendedTemplateId == nil else {
            return
        }

        let interval = PerformanceTrace.begin("dashboard_recommended_template_refresh", category: .dataLoad)
        let startedAt = LatencyProbe.timerStart()
        cachedRecommendedTemplateId = computeRecommendedTemplateId()
        PerformanceTrace.end("dashboard_recommended_template_refresh", interval, category: .dataLoad)
        recordDashboardLatencyProbe(
            "refreshRecommendedTemplateCache",
            startedAt: startedAt,
            counts: [
                "hasTemplate": cachedRecommendedTemplateId == nil ? 0 : 1,
                "force": forceRefresh ? 1 : 0
            ]
        )
    }

    private func deleteFoodEntry(_ entry: FoodEntry) {
        entry.imageData = nil
        modelContext.delete(entry)
        HapticManager.success()
    }

    private func behaviorActionStateForToday() -> (openedActionKeys: Set<String>, completedActionKeys: Set<String>) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        var opened: Set<String> = []
        var completed: Set<String> = []

        for event in behaviorEvents {
            if event.occurredAt < startOfDay {
                break
            }

            switch event.outcome {
            case .opened:
                opened.insert(event.actionKey)
            case .performed:
                opened.insert(event.actionKey)
                completed.insert(event.actionKey)
            case .completed:
                opened.insert(event.actionKey)
                completed.insert(event.actionKey)
            case .presented, .suggestedTap, .dismissed:
                continue
            }
        }

        return (opened, completed)
    }

    private func openFoodCameraFromDashboard(source: String, sessionId: UUID? = nil) {
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.logFood,
            domain: .nutrition,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
        presentFoodCamera(sessionId: sessionId)
    }

    private func presentFoodCamera(sessionId: UUID? = nil) {
        guard foodCameraPresentation == nil, !isPreparingFoodCamera else { return }
        isPreparingFoodCamera = true

        Task { @MainActor in
            let presentation = FoodCameraPresentation(sessionId: sessionId)
            await presentation.cameraService.requestPermission()
            foodCameraPresentation = presentation
            isPreparingFoodCamera = false
        }
    }

    private func openLogWeightFromDashboard(source: String) {
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.logWeight,
            domain: .body,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
        showingLogWeight = true
    }

    private func openTraiChatFromDashboard() {
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: "engagement.dashboard_chat_shortcut",
            domain: .engagement,
            surface: .dashboard,
            outcome: .opened
        )
        onSelectTab?(.trai)
        HapticManager.selectionChanged()
    }

    private func openCalorieDetailFromDashboard(source: String) {
        loadFoodTrendHistoryForSelectedDateIfNeeded()
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.openCalorieDetail,
            domain: .nutrition,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
        showingCalorieDetail = true
    }

    private func openMacroDetailFromDashboard(source: String) {
        loadFoodTrendHistoryForSelectedDateIfNeeded()
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.openMacroDetail,
            domain: .nutrition,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
        showingMacroDetail = true
    }

    private func trackOpenWeightFromDashboard(source: String) {
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.openWeight,
            domain: .body,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
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

    private func startWorkoutFromTemplate(_ template: WorkoutPlan.WorkoutTemplate) {
        let workout = workoutTemplateService.createStartWorkout(from: template)
        _ = workoutTemplateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .dashboard,
            outcome: .performed,
            relatedEntityId: workout.id,
            metadata: [
                "type": "template",
                "template_name": template.name
            ]
        )

        pendingTemplate = template
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func startCustomWorkout() {
        let workout = workoutTemplateService.createCustomWorkout()
        _ = workoutTemplateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .dashboard,
            outcome: .performed,
            relatedEntityId: workout.id,
            metadata: ["type": "custom"]
        )

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

        let template: WorkoutPlan.WorkoutTemplate?
        if let cachedTemplateId = cachedRecommendedTemplateId {
            template = plan.templates.first(where: { $0.id == cachedTemplateId }) ?? plan.templates.first
        } else {
            if let recommendedTemplateId = recoveryService.getRecommendedTemplateId(
                plan: plan,
                modelContext: modelContext
            ) {
                template = plan.templates.first(where: { $0.id == recommendedTemplateId }) ?? plan.templates.first
            } else {
                template = plan.templates.first
            }
        }

        guard let template else {
            startCustomWorkout()
            return
        }

        let workout = workoutTemplateService.createStartWorkout(from: template)
        _ = workoutTemplateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .dashboard,
            outcome: .performed,
            relatedEntityId: workout.id,
            metadata: [
                "type": "recommended",
                "template_name": template.name
            ]
        )

        pendingTemplate = template
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func mergeUniqueStrings(_ base: [String], _ extra: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for value in base + extra {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

}

private struct DashboardTopGradient: View {
    private var lensColors: [Color] {
        TraiLensPalette.energy.colors
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    lensColors[0].opacity(0.34),
                    lensColors[1].opacity(0.26),
                    lensColors[2].opacity(0.20),
                    lensColors[3].opacity(0.14),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(lensColors[2].opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: 130, y: -120)

            Circle()
                .fill(lensColors[0].opacity(0.20))
                .frame(width: 260, height: 260)
                .blur(radius: 44)
                .offset(x: -130, y: -80)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(height: 420)
        .offset(y: -140)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            WorkoutSession.self,
            WeightEntry.self,
            CoachSignal.self,
            BehaviorEvent.self
        ], inMemory: true)
}
