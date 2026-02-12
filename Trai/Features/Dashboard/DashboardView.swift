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
            patternProfile: pulsePatternProfile
        )
    }

    var body: some View {
        NavigationStack {
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
                                    onQuickChat: handlePulseQuickChat
                                )
                            }

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
                .background(alignment: .top) {
                    if isViewingToday, profile != nil {
                        DashboardPulseTopGradient()
                    }
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
        _ = withAnimation(.easeInOut(duration: 0.3)) {
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

    private func handleCoachAction(_ action: DailyCoachAction.Kind) {
        switch action {
        case .startWorkout:
            trackPulseInteraction("pulse_action_start_workout")
            startWorkout()
        case .logFood:
            trackPulseInteraction("pulse_action_log_food")
            showingLogFood = true
            HapticManager.selectionChanged()
        case .openChat:
            trackPulseInteraction("pulse_action_open_chat")
            if pendingPulseSeedPrompt.isEmpty {
                pendingPulseSeedPrompt = buildPulseHandoffPrompt()
            }
            selectedTabRaw = AppTab.trai.rawValue
            HapticManager.selectionChanged()
        }
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
        HapticManager.success()
    }

    private func handlePulseQuickChat(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingPulseSeedPrompt = trimmed
        trackPulseInteraction("pulse_quick_chat")
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
            CoachSignal.self
        ], inMemory: true)
}
