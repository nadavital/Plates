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
    @Query(filter: #Predicate<CoachSignal> { !$0.isResolved }, sort: \CoachSignal.createdAt, order: .reverse)
    private var coachSignals: [CoachSignal]
    @Query private var suggestionUsage: [SuggestionUsage]
    @Query(sort: \BehaviorEvent.occurredAt, order: .reverse)
    private var behaviorEvents: [BehaviorEvent]

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @State private var recoveryService = MuscleRecoveryService()

    // Custom reminders (fetched manually to avoid @Query freeze)
    @State private var customReminders: [CustomReminder] = []
    @State private var todaysCompletedReminderIds: Set<UUID> = []
    @State private var remindersLoaded = false
    @State private var pendingScrollToReminders = false
    @State private var reminderCompletionHistory: [ReminderCompletion] = []
    private let reminderCompletionHistoryCapPerWindow = 400

    // Sheet presentation state
    @State private var showingLogFood = false
    @State private var showingLogWeight = false
    @State private var showingWeightTracking = false
    @State private var showingCalorieDetail = false
    @State private var showingMacroDetail = false
    @State private var entryToEdit: FoodEntry?
    @State private var sessionIdToAddTo: UUID?

    // Workout sheet state
    @State private var showingWorkoutSheet = false
    @State private var pendingWorkout: LiveWorkout?
    @State private var pendingTemplate: WorkoutPlan.WorkoutTemplate?
    @AppStorage("pendingPlanReviewRequest") var pendingPlanReviewRequest = false
    @AppStorage("pendingWorkoutPlanReviewRequest") var pendingWorkoutPlanReviewRequest = false
    @AppStorage("pendingPulseSeedPrompt") private var pendingPulseSeedPrompt: String = ""
    @AppStorage("selectedTab") private var selectedTabRaw: String = AppTab.dashboard.rawValue

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

    private let reminderHabitWindowDays = 30

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

    private var coachRecommendedWorkoutName: String? {
        guard let plan = profile?.workoutPlan else { return nil }
        let recommendedId = recoveryService.getRecommendedTemplateId(plan: plan, modelContext: modelContext)
        let template = plan.templates.first { $0.id == recommendedId } ?? plan.templates.first
        return template?.name
    }

    private var hasActiveLiveWorkout: Bool {
        liveWorkouts.contains { $0.completedAt == nil }
    }

    private var dailyCoachContext: DailyCoachContext? {
        guard isViewingToday, let profile else { return nil }

        let recoveryInfo = recoveryService.getRecoveryStatus(modelContext: modelContext)
        let readyMuscleCount = recoveryInfo.filter { $0.status == .ready }.count
        let hasWorkout = todayTotalWorkoutCount > 0
        let calorieGoal = profile.effectiveCalorieGoal(hasWorkoutToday: hasWorkout || hasActiveLiveWorkout)
        let activeSignals = coachSignals.active(now: .now)
        let behaviorProfile = BehaviorProfileService.buildProfile(now: .now, events: behaviorEvents)
        let todayActionState = behaviorActionStateForToday()
        let reminderCompletionRate = todaysReminderCompletionRate
        let missedReminderCount = todaysMissedReminderCount
        let daysSinceLatestWeightLog = daysSinceLastWeightLog
            ?? behaviorProfile.daysSinceLastAction(BehaviorActionKey.logWeight, now: .now)
        let weightLoggedThisWeek = loggedWeightThisWeek
        let weightLoggedThisWeekDays = inferredWeightLogWeekdays
        let weightLikelyLogTimes = mergeUniqueStrings(
            inferredWeightLogTimes,
            behaviorProfile.likelyTimeLabels(
                for: BehaviorActionKey.logWeight,
                maxLabels: 2,
                minimumEvents: 2
            )
        )
        let likelyReminderTimes = todaysReminderItemsAll.map(\.time)
        let likelyWorkoutTimes = mergeUniqueStrings(
            TraiPulsePatternService.learnedWorkoutTimeWindows(from: pulsePatternProfile),
            behaviorProfile.likelyTimeLabels(
                for: BehaviorActionKey.startWorkout,
                maxLabels: 2,
                minimumEvents: 2
            )
        )
        let lastActiveWorkoutHour = lastRecentWorkoutHour
        let lastActiveWorkoutAt = lastRecentWorkoutAt
        let planReviewRecommendation = pendingPlanReviewRecommendation
        let reminderCandidateScores = todaysReminderCandidateScores

        return DailyCoachContext(
            now: .now,
            hasWorkoutToday: hasWorkout,
            hasActiveWorkout: hasActiveLiveWorkout,
            caloriesConsumed: totalCalories,
            calorieGoal: calorieGoal,
            proteinConsumed: Int(totalProtein.rounded()),
            proteinGoal: profile.dailyProteinGoal,
            readyMuscleCount: readyMuscleCount,
            recommendedWorkoutName: coachRecommendedWorkoutName,
                activeSignals: activeSignals,
                trend: pulseTrendSnapshot,
                patternProfile: pulsePatternProfile,
                reminderCompletionRate: reminderCompletionRate,
                recentMissedReminderCount: missedReminderCount,
            daysSinceLastWeightLog: daysSinceLatestWeightLog,
            weightLoggedThisWeek: weightLoggedThisWeek,
            weightLoggedThisWeekDays: weightLoggedThisWeekDays,
            weightLikelyLogTimes: weightLikelyLogTimes,
            weightRecentRangeKg: recentWeightRangeKg,
                weightLogRoutineScore: inferredWeightLogRoutineScore,
                todaysExerciseMinutes: todayExerciseMinutes,
                lastActiveWorkoutHour: lastActiveWorkoutHour,
                likelyReminderTimes: likelyReminderTimes,
                likelyWorkoutTimes: likelyWorkoutTimes,
                planReviewTrigger: planReviewRecommendation?.trigger.rawValue,
                planReviewMessage: pendingPlanReviewMessage,
                planReviewDaysSince: planReviewRecommendation?.details.daysSinceReview,
                planReviewWeightDeltaKg: planReviewRecommendation?.details.weightChangeKg,
                behaviorProfile: behaviorProfile,
                todayOpenedActionKeys: todayActionState.openedActionKeys,
                todayCompletedActionKeys: todayActionState.completedActionKeys,
                lastActiveWorkoutAt: lastActiveWorkoutAt,
                pendingReminderCandidates: todaysReminderCandidates,
                pendingReminderCandidateScores: reminderCandidateScores
            )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if isViewingToday, profile != nil {
                    DashboardPulseTopGradient()
                }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                    VStack(spacing: 18) {
                        // Date Navigation
                        DateNavigationBar(
                            selectedDate: $selectedDate,
                            isToday: isViewingToday
                        )

                        if isViewingToday, profile != nil {
                            if let coachContext = dailyCoachContext {
                                TraiPulseHeroCard(
                                    context: coachContext,
                                    onAction: handleCoachAction,
                                    onQuestionAnswer: handleCoachQuestionAnswer,
                                    onPlanProposalDecision: handlePlanProposalDecision,
                                    onQuickChat: handlePulseQuickChat,
                                    onPromptPresented: handlePulsePromptPresented
                                )
                            }

                            // Quick action buttons (only on today)
                            QuickActionsCard(
                                onLogFood: { openFoodCameraFromDashboard(source: "quick_actions") },
                                onAddWorkout: { startWorkout() },
                                onLogWeight: { openLogWeightFromDashboard(source: "quick_actions") },
                                workoutName: quickAddWorkoutName
                            )
                            .traiEntrance(index: 0)

                            // Today's reminders
                            if !todaysReminderItems.isEmpty {
                                TodaysRemindersCard(
                                    reminders: todaysReminderItems,
                                    onReminderTap: { _ in /* Tap to expand/interact */ },
                                    onComplete: completeReminder,
                                    onViewAll: { /* Already viewing on dashboard */ }
                                )
                                .id("reminders-section")
                                .traiEntrance(index: 1)
                            }
                        }

                    CalorieProgressCard(
                        consumed: totalCalories,
                        goal: profile?.dailyCalorieGoal ?? 2000,
                        onTap: { openCalorieDetailFromDashboard(source: "calorie_progress_card") }
                    )
                    .traiEntrance(index: 2)

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
                    .traiEntrance(index: 3)

                    DailyFoodTimeline(
                        entries: selectedDayFoodEntries,
                        enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                        onAddFood: isViewingToday ? { openFoodCameraFromDashboard(source: "food_timeline_add") } : nil,
                        onAddToSession: isViewingToday ? { sessionId in
                            sessionIdToAddTo = sessionId
                            openFoodCameraFromDashboard(source: "food_timeline_add_to_session")
                        } : nil,
                        onEditEntry: { entryToEdit = $0 },
                        onDeleteEntry: deleteFoodEntry
                    )
                    .traiEntrance(index: 4)

                    TodaysActivityCard(
                        steps: todaySteps,
                        activeCalories: todayActiveCalories,
                        exerciseMinutes: todayExerciseMinutes,
                        workoutCount: todayTotalWorkoutCount,
                        isLoading: isLoadingActivity
                    )
                    .traiEntrance(index: 5)

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
                        .traiEntrance(index: 6)
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
            .task {
                _ = CoachSignalService(modelContext: modelContext).pruneExpiredSignals()
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
            .sheet(isPresented: $showingWeightTracking) {
                WeightTrackingView()
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

    private var pulseTrendSnapshot: TraiPulseTrendSnapshot? {
        guard isViewingToday else { return nil }

        return TraiPulsePatternService.buildTrendSnapshot(
            now: .now,
            foodEntries: allFoodEntries,
            workouts: allWorkouts,
            liveWorkouts: liveWorkouts,
            profile: profile,
            daysWindow: 7
        )
    }

    private var pulsePatternProfile: TraiPulsePatternProfile? {
        guard isViewingToday else { return nil }

        return TraiPulsePatternService.buildProfile(
            now: .now,
            foodEntries: allFoodEntries,
            workouts: allWorkouts,
            liveWorkouts: liveWorkouts,
            suggestionUsage: suggestionUsage,
            behaviorEvents: behaviorEvents,
            profile: profile
        )
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

    private var todaysReminderItemsAll: [TodaysRemindersCard.ReminderItem] {
        guard let profile else { return [] }

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

    private var todaysReminderCandidates: [TraiPulseReminderCandidate] {
        let candidates = todaysReminderItems.map {
            TraiPulseReminderCandidate(
                id: $0.id.uuidString,
                title: $0.title,
                time: $0.time,
                hour: $0.hour,
                minute: $0.minute
            )
        }

        return candidates.sorted { lhs, rhs in
            let lhsScore = todaysReminderCandidateScores[lhs.id] ?? 0
            let rhsScore = todaysReminderCandidateScores[rhs.id] ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            return lhs.minute < rhs.minute
        }
    }

    private var todaysReminderCandidateScores: [String: Double] {
        let groupedCompletions = reminderCompletionsByReminderId
        return todaysReminderItems.reduce(into: [:]) { scores, item in
            let candidate = TraiPulseReminderCandidate(
                id: item.id.uuidString,
                title: item.title,
                time: item.time,
                hour: item.hour,
                minute: item.minute
            )
            let candidateCompletions = groupedCompletions[item.id] ?? []
            scores[candidate.id] = reminderHabitScore(for: candidate, completions: candidateCompletions)
        }
    }

    private var reminderCompletionsByReminderId: [UUID: [ReminderCompletion]] {
        let start = Calendar.current.date(
            byAdding: .day,
            value: -reminderHabitWindowDays,
            to: Date()
        ) ?? Date()

        return Dictionary(grouping: reminderCompletionHistory.filter { $0.completedAt >= start }) { $0.reminderId }
    }

    private func reminderHabitScore(
        for reminder: TraiPulseReminderCandidate,
        completions: [ReminderCompletion]
    ) -> Double {
        guard !completions.isEmpty else { return 0 }

        let now = Date()
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        let scheduledMinutes = reminder.hour * 60 + reminder.minute
        let maxClockDistance = 180.0

        var weightedSum = 0.0
        for completion in completions {
            let dayDiff = max(0, calendar.dateComponents([.day], from: completion.completedAt, to: now).day ?? 0)
            let recency = max(0.0, Double(reminderHabitWindowDays - dayDiff)) / Double(reminderHabitWindowDays)

            let completionMinutes = calendar.component(.hour, from: completion.completedAt) * 60
                + calendar.component(.minute, from: completion.completedAt)
            let rawDistance = abs(completionMinutes - scheduledMinutes)
            let circularDistance = min(rawDistance, (24 * 60) - rawDistance)
            let timeMatch = 1.0 - min(1.0, Double(circularDistance) / maxClockDistance)
            let weekdayMatch = calendar.component(.weekday, from: completion.completedAt) == currentWeekday ? 0.2 : 0.0
            let onTimeMatch = completion.wasOnTime ? 0.15 : 0.0

            weightedSum += (0.5 * recency) + (0.25 * timeMatch) + onTimeMatch + weekdayMatch
        }

        let completionRate = reminderHabitCompletionRate(completions)
        let averageConfidence = min(1.0, (weightedSum / Double(completions.count)) / 1.35)
        return clamp((0.75 * averageConfidence) + (0.25 * completionRate))
    }

    private func reminderHabitCompletionRate(_ completions: [ReminderCompletion]) -> Double {
        min(1.0, Double(completions.count) / 3.0)
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
            foodEntries: Array(allFoodEntries)
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

    private var lastRecentWorkoutHour: Int? {
        guard let latest = lastRecentWorkoutAt else { return nil }
        return Calendar.current.component(.hour, from: latest)
    }

    private func fetchCustomReminders() {
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
        let completions = (try? modelContext.fetch(completionDescriptor)) ?? []
        reminderCompletionHistory = completions
        trimReminderCompletionHistory(to: now)
        todaysCompletedReminderIds = Set(
            completions
                .filter { $0.completedAt >= startOfDay }
                .map { $0.reminderId }
        )
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
        reminderCompletionHistory.insert(completion, at: 0)
        trimReminderCompletionHistory(to: now)

        // Update local state with animation for smooth removal
        _ = withAnimation(.easeInOut(duration: 0.3)) {
            todaysCompletedReminderIds.insert(reminder.id)
        }

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

    private func openFoodCameraFromDashboard(source: String) {
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.logFood,
            domain: .nutrition,
            surface: .dashboard,
            outcome: .opened,
            metadata: ["source": source]
        )
        showingLogFood = true
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

    private func openCalorieDetailFromDashboard(source: String) {
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

    private func startWorkoutTemplate(_ action: DailyCoachAction) {
        guard let metadata = action.metadata else {
            startWorkout()
            return
        }

        let templateID = metadata["template_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = metadata["template_name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? metadata["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? metadata["workout_name"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let profile, let plan = profile.workoutPlan else {
            startCustomWorkout()
            return
        }

        if let templateID,
           let id = UUID(uuidString: templateID),
           let template = plan.templates.first(where: { $0.id == id }) {
            startWorkoutFromTemplate(template)
            return
        }

        if let templateName, !templateName.isEmpty,
           let template = plan.templates.first(where: { $0.name.caseInsensitiveCompare(templateName) == .orderedSame }) {
            startWorkoutFromTemplate(template)
            return
        }

        startWorkout()
    }

    private func startWorkoutFromTemplate(_ template: WorkoutPlan.WorkoutTemplate) {
        let muscleGroups = LiveWorkout.MuscleGroup.fromTargetStrings(template.targetMuscleGroups)

        let workout = LiveWorkout(
            name: template.name,
            workoutType: .strength,
            targetMuscleGroups: muscleGroups
        )
        modelContext.insert(workout)
        try? modelContext.save()
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
        let workout = LiveWorkout(
            name: "Custom Workout",
            workoutType: .strength,
            targetMuscleGroups: []
        )
        modelContext.insert(workout)
        try? modelContext.save()
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

    private func handleCoachAction(_ action: DailyCoachAction) {
        recordPulseActionTap(action)
        switch action.kind {
        case .startWorkout:
            trackPulseInteraction("pulse_action_start_workout")
            startWorkout()
        case .startWorkoutTemplate:
            trackPulseInteraction("pulse_action_start_workout_template")
            startWorkoutTemplate(action)
        case .logFood:
            trackPulseInteraction("pulse_action_log_food")
            recordPulseActionExecution(action)
            showingLogFood = true
            HapticManager.selectionChanged()
        case .logFoodCamera:
            trackPulseInteraction("pulse_action_log_food_camera")
            recordPulseActionExecution(action)
            showingLogFood = true
            HapticManager.selectionChanged()
        case .logWeight:
            trackPulseInteraction("pulse_action_log_weight")
            recordPulseActionExecution(action)
            showingLogWeight = true
            HapticManager.selectionChanged()
        case .openWeight:
            trackPulseInteraction("pulse_action_open_weight")
            recordPulseActionExecution(action)
            selectedDate = .now
            showingWeightTracking = true
            HapticManager.selectionChanged()
        case .openCalorieDetail:
            trackPulseInteraction("pulse_action_open_calorie_detail")
            recordPulseActionExecution(action)
            selectedDate = .now
            showingCalorieDetail = true
            HapticManager.selectionChanged()
        case .openMacroDetail:
            trackPulseInteraction("pulse_action_open_macro_detail")
            recordPulseActionExecution(action)
            selectedDate = .now
            showingMacroDetail = true
            HapticManager.selectionChanged()
        case .openProfile:
            trackPulseInteraction("pulse_action_open_profile")
            recordPulseActionExecution(action)
            selectedTabRaw = AppTab.profile.rawValue
            HapticManager.selectionChanged()
        case .openWorkouts:
            trackPulseInteraction("pulse_action_open_workouts")
            recordPulseActionExecution(action)
            selectedTabRaw = AppTab.workouts.rawValue
            HapticManager.selectionChanged()
        case .openWorkoutPlan:
            trackPulseInteraction("pulse_action_open_workout_plan")
            recordPulseActionExecution(action)
            selectedTabRaw = AppTab.workouts.rawValue
            HapticManager.selectionChanged()
        case .openRecovery:
            trackPulseInteraction("pulse_action_open_recovery")
            recordPulseActionExecution(action)
            selectedTabRaw = AppTab.workouts.rawValue
            HapticManager.selectionChanged()
        case .reviewNutritionPlan:
            trackPulseInteraction("pulse_action_review_nutrition_plan")
            recordPulseActionExecution(action)
            pendingPlanReviewRequest = true
            selectedTabRaw = AppTab.trai.rawValue
            HapticManager.selectionChanged()
        case .reviewWorkoutPlan:
            trackPulseInteraction("pulse_action_review_workout_plan")
            recordPulseActionExecution(action)
            pendingWorkoutPlanReviewRequest = true
            selectedTabRaw = AppTab.trai.rawValue
            HapticManager.selectionChanged()
        case .completeReminder:
            trackPulseInteraction("pulse_action_complete_reminder")
            guard let reminder = reminderToComplete(action: action) else {
                return
            }
            selectedDate = .now
            completeReminder(reminder)
            HapticManager.selectionChanged()
        }
    }

    private func reminderToComplete(action: DailyCoachAction) -> TodaysRemindersCard.ReminderItem? {
        guard let metadata = action.metadata else { return nil }
        let candidates = todaysReminderItems

        if let reminderID = metadata["reminder_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let id = UUID(uuidString: reminderID),
           let matched = candidates.first(where: { $0.id == id }) {
            return matched
        }

        if let title = metadata["reminder_title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let byTitle = candidates.filter { $0.title == title }
            if byTitle.count == 1 {
                return byTitle.first
            }

            if let time = metadata["reminder_time"]?.trimmingCharacters(in: .whitespacesAndNewlines), !time.isEmpty {
                let byTime = byTitle.filter { $0.time == time }
                if byTime.count == 1 {
                    return byTime.first
                }
            }
        }

        if let hourValue = parseInt(metadata["reminder_hour"]),
           let minuteValue = parseInt(metadata["reminder_minute"]) {
            let byClock = candidates.filter { $0.hour == hourValue && $0.minute == minuteValue }
            if byClock.count == 1 {
                return byClock.first
            }
            if let title = metadata["reminder_title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                let exact = byClock.filter { $0.title == title }
                if exact.count == 1 {
                    return exact.first
                }
            }
        }

        if candidates.count == 1 {
            return candidates.first
        }

        return nil
    }

    private func parseInt(_ raw: String?) -> Int? {
        raw
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(Int.init)
    }

    private func handleCoachQuestionAnswer(_ question: TraiPulseQuestion, _ answer: String) {
        let interpretation = TraiPulseResponseInterpreter.interpret(question: question, answer: answer)
        let detail = "[PulseQuestion:\(question.id)] \(question.prompt) Answer: \(answer) [PulseAdaptation:\(interpretation.adaptationLine)]"

        _ = CoachSignalService(modelContext: modelContext).addSignal(
            title: interpretation.signalTitle,
            detail: detail,
            source: .dashboardNote,
            domain: interpretation.domain,
            severity: interpretation.severity,
            confidence: interpretation.confidence,
            expiresAfter: interpretation.expiresAfter,
            metadata: [
                "question_id": question.id,
                "question_prompt": question.prompt
            ]
        )

        savePulseMemoryIfNeeded(interpretation.memoryCandidate)
        pendingPulseSeedPrompt = interpretation.handoffPrompt
        trackPulseInteraction("pulse_question_answered_\(question.id)")
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: "engagement.pulse_question.\(question.id)",
            domain: .engagement,
            surface: .dashboard,
            outcome: .completed,
            metadata: ["answer": answer]
        )
        HapticManager.success()
    }

    private func handlePlanProposalDecision(_ proposal: TraiPulsePlanProposal, _ decision: TraiPulsePlanProposalDecision) {
        let decisionTitle: String
        let prompt: String

        switch decision {
        case .apply:
            decisionTitle = "Plan adjustment approved"
            prompt = "Pulse plan proposal approved. Proposal: \(proposal.title). Changes: \(proposal.changes.joined(separator: "; ")). Rationale: \(proposal.rationale). Any plan mutation must still require explicit user confirmation."
            selectedTabRaw = AppTab.trai.rawValue
        case .review:
            decisionTitle = "Plan adjustment review requested"
            prompt = "Pulse plan proposal review requested. Proposal: \(proposal.title). Changes: \(proposal.changes.joined(separator: "; ")). Impact: \(proposal.impact)."
            selectedTabRaw = AppTab.trai.rawValue
        case .later:
            decisionTitle = "Plan adjustment deferred"
            prompt = "Pulse plan proposal deferred: \(proposal.title). Do not re-suggest daily; revisit later with lighter framing."
        }

        _ = CoachSignalService(modelContext: modelContext).addSignal(
            title: decisionTitle,
            detail: "[PulsePlanProposal:\(proposal.id)] \(proposal.title) [Decision:\(decision.rawValue)]",
            source: .dashboardNote,
            domain: .general,
            severity: decision == .later ? 0.25 : 0.45,
            confidence: 0.85,
            expiresAfter: 5 * 24 * 60 * 60,
            metadata: [
                "proposal_id": proposal.id,
                "decision": decision.rawValue
            ]
        )

        pendingPulseSeedPrompt = prompt
        trackPulseInteraction("pulse_plan_proposal_\(decision.rawValue)")
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: "planning.pulse_plan_proposal.\(decision.rawValue)",
            domain: .planning,
            surface: .dashboard,
            outcome: decision == .later ? .dismissed : .completed,
            metadata: ["proposal_id": proposal.id]
        )
        HapticManager.success()
    }

    private func handlePulseQuickChat(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingPulseSeedPrompt = trimmed
        trackPulseInteraction("pulse_quick_chat")
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: "engagement.pulse_quick_chat",
            domain: .engagement,
            surface: .dashboard,
            outcome: .opened
        )
        selectedTabRaw = AppTab.trai.rawValue
        HapticManager.selectionChanged()
    }

    private func buildPulseHandoffPrompt() -> String {
        var sections: [String] = []

        if let context = dailyCoachContext {
            let inferredWindow = TraiPulseAdaptivePreferences.inferWorkoutWindow(for: context)
            let inferredMinutes = TraiPulseAdaptivePreferences.inferTomorrowWorkoutMinutes(for: context)
            let window = inferredWindow.hours
            let activeSnapshots = coachSignals.activeSnapshots(now: .now)
            let pulseInput = TraiPulseInputContext(
                now: context.now,
                hasWorkoutToday: context.hasWorkoutToday,
                hasActiveWorkout: context.hasActiveWorkout,
                caloriesConsumed: context.caloriesConsumed,
                calorieGoal: context.calorieGoal,
                proteinConsumed: context.proteinConsumed,
                proteinGoal: context.proteinGoal,
                readyMuscleCount: context.readyMuscleCount,
                recommendedWorkoutName: context.recommendedWorkoutName,
                workoutWindowStartHour: window.start,
                workoutWindowEndHour: window.end,
                activeSignals: activeSnapshots,
                tomorrowWorkoutMinutes: inferredMinutes,
                trend: context.trend,
                patternProfile: context.patternProfile,
                reminderCompletionRate: context.reminderCompletionRate,
                recentMissedReminderCount: context.recentMissedReminderCount,
                daysSinceLastWeightLog: context.daysSinceLastWeightLog,
                weightLoggedThisWeek: context.weightLoggedThisWeek,
                weightLoggedThisWeekDays: context.weightLoggedThisWeekDays,
                weightLikelyLogTimes: context.weightLikelyLogTimes,
                weightRecentRangeKg: context.weightRecentRangeKg,
                weightLogRoutineScore: context.weightLogRoutineScore,
                todaysExerciseMinutes: context.todaysExerciseMinutes,
                lastActiveWorkoutHour: context.lastActiveWorkoutHour,
                likelyReminderTimes: context.likelyReminderTimes,
                likelyWorkoutTimes: context.likelyWorkoutTimes,
                planReviewTrigger: context.planReviewTrigger,
                planReviewMessage: context.planReviewMessage,
                planReviewDaysSince: context.planReviewDaysSince,
                planReviewWeightDeltaKg: context.planReviewWeightDeltaKg,
                pendingReminderCandidates: todaysReminderCandidates,
                pendingReminderCandidateScores: context.pendingReminderCandidateScores,
                contextPacket: nil
            )

            let packet = TraiPulseContextAssembler.assemble(
                patternProfile: context.patternProfile ?? .empty,
                activeSignals: activeSnapshots,
                context: pulseInput,
                tokenBudget: 550
            )
            sections.append("Pulse packet: \(packet.promptSummary)")
        }

        if let recentAnswer = TraiPulseResponseInterpreter.recentPulseAnswer(
            from: coachSignals.activeSnapshots(now: .now),
            now: .now
        ) {
            sections.append("Recent check-in: \(recentAnswer.answer).")
        }

        sections.append("User opened Trai from Pulse. Use this context when relevant.")
        return sections.joined(separator: " ")
    }

    private func trackPulseInteraction(_ suggestionType: String) {
        if let existing = suggestionUsage.first(where: { $0.suggestionType == suggestionType }) {
            existing.recordTap()
        } else {
            let usage = SuggestionUsage(suggestionType: suggestionType)
            usage.recordTap()
            modelContext.insert(usage)
        }
        try? modelContext.save()
    }

    private func handlePulsePromptPresented(_ snapshot: TraiPulseContentSnapshot) {
        switch snapshot.prompt {
        case .question(let question):
            BehaviorTracker(modelContext: modelContext).record(
                actionKey: "engagement.pulse_question_presented.\(question.id)",
                domain: .engagement,
                surface: .dashboard,
                outcome: .presented,
                metadata: ["prompt": question.prompt]
            )
        case .action(let action):
            let descriptor = behaviorDescriptor(for: action)
            BehaviorTracker(modelContext: modelContext).record(
                actionKey: descriptor.actionKey,
                domain: descriptor.domain,
                surface: .dashboard,
                outcome: .presented,
                metadata: pulseTelemetryMetadata(for: action)
            )
        case .planProposal(let proposal):
            BehaviorTracker(modelContext: modelContext).record(
                actionKey: "planning.pulse_plan_proposal.presented",
                domain: .planning,
                surface: .dashboard,
                outcome: .presented,
                metadata: ["proposal_id": proposal.id]
            )
        case .none:
            break
        }
    }

    private func recordPulseActionTap(_ action: DailyCoachAction) {
        let descriptor = behaviorDescriptor(for: action)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: "engagement.pulse_action_tap.\(action.kind.rawValue)",
            domain: descriptor.domain,
            surface: .dashboard,
            outcome: .suggestedTap,
            metadata: pulseTelemetryMetadata(for: action)
        )
    }

    private func recordPulseActionExecution(_ action: DailyCoachAction) {
        let descriptor = behaviorDescriptor(for: action)
        var metadata = pulseTelemetryMetadata(for: action)
        metadata["source"] = "pulse"
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: descriptor.actionKey,
            domain: descriptor.domain,
            surface: .dashboard,
            outcome: .opened,
            metadata: metadata
        )
    }

    private func behaviorDescriptor(for action: DailyCoachAction) -> (actionKey: String, domain: BehaviorDomain) {
        switch action.kind {
        case .startWorkout, .startWorkoutTemplate:
            return (BehaviorActionKey.startWorkout, .workout)
        case .logFood, .logFoodCamera:
            return (BehaviorActionKey.logFood, .nutrition)
        case .logWeight:
            return (BehaviorActionKey.logWeight, .body)
        case .openWeight:
            return (BehaviorActionKey.openWeight, .body)
        case .openCalorieDetail:
            return (BehaviorActionKey.openCalorieDetail, .nutrition)
        case .openMacroDetail:
            return (BehaviorActionKey.openMacroDetail, .nutrition)
        case .openProfile:
            return (BehaviorActionKey.openProfile, .profile)
        case .openWorkouts:
            return (BehaviorActionKey.openWorkouts, .workout)
        case .openWorkoutPlan:
            return (BehaviorActionKey.openWorkoutPlan, .planning)
        case .openRecovery:
            return (BehaviorActionKey.openRecovery, .workout)
        case .reviewNutritionPlan:
            return (BehaviorActionKey.reviewNutritionPlan, .planning)
        case .reviewWorkoutPlan:
            return (BehaviorActionKey.reviewWorkoutPlan, .planning)
        case .completeReminder:
            return (BehaviorActionKey.completeReminder, .reminder)
        }
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

    private func pulseTelemetryMetadata(for action: DailyCoachAction) -> [String: String] {
        var metadata: [String: String] = ["title": action.title]
        let telemetryKeys = [
            "pulse_recommendation_id",
            "pulse_policy_version",
            "pulse_rank_position",
            "pulse_rank_score",
            "pulse_reco_origin",
            "pulse_candidate_set"
        ]
        if let actionMetadata = action.metadata {
            for key in telemetryKeys {
                if let value = actionMetadata[key], !value.isEmpty {
                    metadata[key] = value
                }
            }
        }
        return metadata
    }

    private func savePulseMemoryIfNeeded(_ candidate: TraiPulseMemoryCandidate?) {
        guard let candidate else { return }

        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let activeMemories = (try? modelContext.fetch(descriptor)) ?? []
        let normalizedCandidate = normalizeMemoryContent(candidate.content)
        let duplicateExists = activeMemories.contains { memory in
            let normalizedExisting = normalizeMemoryContent(memory.content)
            return normalizedExisting == normalizedCandidate ||
                normalizedExisting.contains(normalizedCandidate) ||
                normalizedCandidate.contains(normalizedExisting)
        }

        guard !duplicateExists else { return }

        let memory = CoachMemory(
            content: candidate.content,
            category: candidate.category,
            topic: candidate.topic,
            source: "pulse",
            importance: candidate.importance
        )
        modelContext.insert(memory)
        try? modelContext.save()
    }

    private func normalizeMemoryContent(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
