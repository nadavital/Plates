//
//  WorkoutsView.swift
//  Trai
//
//  Plan-first workout tab with template-based workout suggestions
//

import SwiftUI
import SwiftData

struct WorkoutsView: View {
    private struct PendingCustomWorkoutStart {
        let name: String
        let type: LiveWorkout.WorkoutType
        let muscles: [LiveWorkout.MuscleGroup]
        let focusAreas: [String]
    }

    // MARK: - Queries

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    @Query private var allWorkouts: [WorkoutSession]

    @Query private var allLiveWorkouts: [LiveWorkout]
    @Query(sort: \WorkoutGoal.createdAt, order: .reverse) private var workoutGoals: [WorkoutGoal]
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse) private var allExerciseHistory: [ExerciseHistory]

    /// Completed in-app workouts (LiveWorkout with completedAt set)
    private var completedLiveWorkouts: [LiveWorkout] {
        allLiveWorkouts.filter { $0.completedAt != nil }
    }

    // MARK: - Environment

    @Environment(\.appTabSelection) private var appTabSelection
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @EnvironmentObject private var activeWorkoutRuntimeState: ActiveWorkoutRuntimeState
    @AppStorage(SharedStorageKeys.Chat.pendingPrompt) private var pendingChatPrompt: String = ""
    @AppStorage(SharedStorageKeys.Chat.pendingLaunchLabel) private var pendingChatLaunchLabel: String = ""

    // MARK: - Services

    @State private var recoveryService = MuscleRecoveryService.shared
    @State private var templateService = WorkoutTemplateService()

    // MARK: - Computed State

    @State private var recoveryInfo: [MuscleRecoveryService.MuscleRecoveryInfo] = []
    @State private var templateScores: [UUID: (score: Double, reason: String)] = [:]
    @State private var recommendedTemplateId: UUID?
    @State private var cachedWorkoutsByDate: [(date: Date, workouts: [WorkoutSession])] = []
    @State private var cachedLiveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])] = []
    @State private var suggestedWorkoutGoals: [WorkoutGoalSuggestion] = []
    @State private var celebratedWorkoutGoal: WorkoutGoal?

    // MARK: - Sheet States

    @State private var showingPlanSetup = false
    @State private var showingMuscleRecoveryDetail = false
    @State private var showingWorkoutDetail: WorkoutSession?
    @State private var showingLiveWorkoutDetail: LiveWorkout?
    @State private var showingWorkoutGoalDetail: WorkoutGoal?
    @State private var showingWorkoutGoalAISetup = false
    @State private var showingWorkoutSheet = false
    @State private var showingCustomWorkoutSetup = false
    @State private var showingPersonalRecords = false
    @State private var pendingWorkout: LiveWorkout?
    @State private var pendingTemplate: WorkoutPlan.WorkoutTemplate?
    @State private var pendingCustomWorkoutStart: PendingCustomWorkoutStart?
    @State private var lastOpenTrackedAt: Date?
    @State private var historyRefreshTask: Task<Void, Never>?
    @State private var deferredRecoveryRefreshTask: Task<Void, Never>?
    @State private var cloudKitHistoryReconciliationTask: Task<Void, Never>?
    @State private var hasPendingHistoryRefresh = true
    @State private var hasPendingRecoveryRefresh = true
    @State private var pendingRecoveryRefreshShouldForce = true
    @State private var hasExecutedInitialHeavyRefresh = false
    @State private var isWorkoutsTabVisible = false
    @State private var latencyProbeEntries: [String] = []
    @State private var tabActivationPolicy = TabActivationPolicy(minimumDwellMilliseconds: 0)
    private static let workoutHistoryWindowDays = 120
    private static let workoutHistoryFetchLimit = 48
    private static let maxHistoryDayGroups = 56
    private static let sectionSnapshotUserDefaultsKey = "workouts_tab_cached_sections_v1"
    private static let goalSuggestionSnapshotUserDefaultsKey = "workouts_goal_suggestions_v1"
    private static let sectionSnapshotTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let goalSuggestionSnapshotTTLSeconds: TimeInterval = 21 * 24 * 60 * 60
    private static let recoveryReadyThresholdHours: Double = 48
    private static let recoveryRecoveringThresholdHours: Double = 24
    private static var initialHistoryRefreshDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2300 : 420
    }
    private static var initialRecoveryRefreshDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2600 : 520
    }
    private static var tabDwellHistoryRefreshDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2600 : 620
    }
    private static var tabDwellRecoveryRefreshDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2900 : 720
    }
    private static var tabHeavyRefreshMinimumDwellMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1400 : 320
    }
    private static var cloudKitHistoryReconciliationDelaysSeconds: [Int] {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork
            ? [4, 10, 18]
            : [2, 6, 12]
    }

    init() {
        let now = Date()
        let historyCutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.workoutHistoryWindowDays,
            to: now
        ) ?? .distantPast

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        _profiles = Query(profileDescriptor)

        var workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.loggedAt >= historyCutoff },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = Self.workoutHistoryFetchLimit
        _allWorkouts = Query(workoutDescriptor)

        var liveWorkoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { $0.startedAt >= historyCutoff },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        liveWorkoutDescriptor.fetchLimit = Self.workoutHistoryFetchLimit
        _allLiveWorkouts = Query(liveWorkoutDescriptor)

        if let cachedSnapshot = Self.loadCachedSectionSnapshot(now: now) {
            _recoveryInfo = State(initialValue: Self.recoveryInfo(from: cachedSnapshot, now: now))
            _templateScores = State(initialValue: Self.templateScores(from: cachedSnapshot))
            _recommendedTemplateId = State(initialValue: Self.recommendedTemplateId(from: cachedSnapshot))
        }
        if let cachedGoalSuggestionSnapshot = Self.loadCachedGoalSuggestionSnapshot(now: now) {
            _suggestedWorkoutGoals = State(initialValue: cachedGoalSuggestionSnapshot.suggestions)
        }
    }

    // MARK: - Computed Properties

    private var workoutPlan: WorkoutPlan? {
        userProfile?.workoutPlan
    }

    private var activeWorkout: LiveWorkout? {
        allLiveWorkouts.first { $0.isInProgress }
    }

    private var usesMetricExerciseWeight: Bool {
        userProfile?.usesMetricExerciseWeight ?? true
    }

    private var canAccessAIFeatures: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private var activeWorkoutGoals: [WorkoutGoal] {
        workoutGoals
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var workoutGoalInsights: [WorkoutGoalInsight] {
        WorkoutGoalProgressResolver.insights(
            goals: activeWorkoutGoals,
            workouts: completedLiveWorkouts,
            sessions: workoutGoalSessions,
            exerciseHistory: allExerciseHistory,
            useLbs: !usesMetricExerciseWeight
        )
    }

    private var workoutGoalSignals: [RecentWorkoutSignal] {
        WorkoutGoalProgressResolver.globalRecentSignals(
            from: completedLiveWorkouts,
            sessions: workoutGoalSessions
        )
    }

    private var staleWorkoutGoalNeedingCheckIn: WorkoutGoal? {
        WorkoutGoalProgressResolver.staleGoalsNeedingCheckIn(
            goals: activeWorkoutGoals,
            workouts: completedLiveWorkouts,
            sessions: workoutGoalSessions
        ).first
    }

    private var workoutGoalSessions: [WorkoutSession] {
        let mergedHealthKitIDs = Set(completedLiveWorkouts.compactMap(\.mergedHealthKitWorkoutID))
        return allWorkouts.filter { workout in
            guard let healthKitWorkoutID = workout.healthKitWorkoutID else { return true }
            return !mergedHealthKitIDs.contains(healthKitWorkoutID)
        }
    }

    private var recentWorkoutModes: [WorkoutMode] {
        let liveModes = completedLiveWorkouts
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .prefix(8)
            .map(\.type)

        let sessionModes = allWorkouts
            .prefix(8)
            .map(\.inferredWorkoutMode)

        return liveModes + sessionModes
    }

    private var plannedWorkoutModes: [WorkoutMode] {
        workoutPlan?.templates.map(\.sessionType) ?? []
    }

    private var personalizedWorkoutTypes: [WorkoutMode] {
        WorkoutMode.personalizedOrder(
            recentModes: recentWorkoutModes,
            plannedModes: plannedWorkoutModes,
            goalModes: activeWorkoutGoals.compactMap(\.linkedWorkoutType)
        )
    }

    private var customWorkoutSuggestions: [CustomWorkoutSetupSheet.SessionSuggestion] {
        var suggestions: [CustomWorkoutSetupSheet.SessionSuggestion] = []
        var seen = Set<String>()

        for template in workoutPlan?.templates ?? [] {
            let normalizedTitle = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFocus = template.focusAreas.map(\.goalNormalizedKey).joined(separator: "|")
            let key = "\(normalizedTitle.goalNormalizedKey)|\(template.sessionType.rawValue)|\(normalizedFocus)"
            guard !seen.contains(key) else { continue }

            suggestions.append(
                .init(
                    id: key,
                    title: normalizedTitle,
                    workoutType: template.sessionType,
                    focusAreas: template.focusAreas,
                    targetMuscles: LiveWorkout.MuscleGroup.fromTargetStrings(template.targetMuscleGroups)
                )
            )
            seen.insert(key)
        }

        for workout in completedLiveWorkouts.sorted(by: { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }) {
            let normalizedTitle = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFocus = workout.focusAreas.map(\.goalNormalizedKey).joined(separator: "|")
            let key = "\(normalizedTitle.goalNormalizedKey)|\(workout.type.rawValue)|\(normalizedFocus)"
            guard !seen.contains(key) else { continue }

            suggestions.append(
                .init(
                    id: key,
                    title: normalizedTitle,
                    workoutType: workout.type,
                    focusAreas: workout.focusAreas,
                    targetMuscles: workout.muscleGroups
                )
            )
            seen.insert(key)
        }

        return Array(suggestions.prefix(4))
    }

    private var workoutsByDate: [(date: Date, workouts: [WorkoutSession])] { cachedWorkoutsByDate }

    /// Completed in-app workouts grouped by date
    private var liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])] { cachedLiveWorkoutsByDate }

    private var isWorkoutsTabActive: Bool {
        isWorkoutsTabVisible
    }

    private var workoutsRefreshFingerprint: String {
        let count = allWorkouts.count
        guard let newest = allWorkouts.first else {
            return "0"
        }
        let oldest = allWorkouts.last ?? newest
        return [
            String(count),
            newest.id.uuidString,
            String(newest.loggedAt.timeIntervalSinceReferenceDate),
            oldest.id.uuidString,
            String(oldest.loggedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private var liveWorkoutsRefreshFingerprint: String {
        guard !allLiveWorkouts.isEmpty else {
            return "0"
        }

        var parts: [String] = []
        parts.reserveCapacity(1 + (allLiveWorkouts.count * 4))
        parts.append(String(allLiveWorkouts.count))

        for workout in allLiveWorkouts {
            parts.append(workout.id.uuidString)
            parts.append(String(workout.startedAt.timeIntervalSinceReferenceDate))
            if let completedAt = workout.completedAt {
                parts.append(String(completedAt.timeIntervalSinceReferenceDate))
            } else {
                parts.append("nil")
            }
            parts.append(workout.mergedHealthKitWorkoutID ?? "nil")
        }

        return parts.joined(separator: "|")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Workout templates section (shows create CTA if no plan)
                    WorkoutTemplatesSection(
                        templates: workoutPlan?.templates ?? [],
                        recoveryScores: templateScores,
                        recommendedTemplateId: recommendedTemplateId,
                        onStartTemplate: startWorkoutFromTemplate,
                        onCreatePlan: workoutPlan == nil ? { showingPlanSetup = true } : nil
                    )

                    // 3b. Quick start custom workout option
                    QuickStartCard {
                        showingCustomWorkoutSetup = true
                    }

                    WorkoutGoalsOverviewSection(
                        insights: workoutGoalInsights,
                        signals: workoutGoalSignals,
                        celebratedGoal: celebratedWorkoutGoal,
                        canCreateGoalsWithTrai: canAccessAIFeatures,
                        onCreateGoalWithTrai: startWorkoutGoalsWithTrai,
                        onUnlockPro: {
                            proUpsellCoordinator?.present(source: .workoutPlan)
                        },
                        staleCheckInGoal: staleWorkoutGoalNeedingCheckIn,
                        onCheckInWithTrai: startWorkoutGoalCheckIn,
                        onGoalTap: { showingWorkoutGoalDetail = $0 },
                        onToggleCompletion: toggleWorkoutGoalCompletion
                    )

                    // 4. Muscle recovery card (compact view)
                    MuscleRecoveryCard(
                        recoveryInfo: recoveryInfo,
                        onTap: { showingMuscleRecoveryDetail = true }
                    )

                    // 5. Recent workout history (includes both in-app and HealthKit workouts)
                    WorkoutHistorySection(
                        workoutsByDate: workoutsByDate,
                        liveWorkoutsByDate: liveWorkoutsByDate,
                        activeGoals: activeWorkoutGoals,
                        onWorkoutTap: { workout in
                            showingWorkoutDetail = workout
                        },
                        onLiveWorkoutTap: { workout in
                            showingLiveWorkoutDetail = workout
                        },
                        onDelete: deleteWorkout,
                        onDeleteLiveWorkout: deleteLiveWorkout
                    )
                }
                .padding()
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Personal Records", systemImage: "trophy.fill") {
                        showingPersonalRecords = true
                    }
                }
            }
            .refreshable {
                await syncHealthKit()
                markHistoryRefreshNeeded(delayMilliseconds: 80)
                markRecoveryRefreshNeeded(
                    forceRefresh: true,
                    delayMilliseconds: 120
                )
            }
            .onAppear {
                if tabActivationPolicy.activeSince == nil {
                    tabActivationPolicy = TabActivationPolicy(
                        minimumDwellMilliseconds: Self.tabHeavyRefreshMinimumDwellMilliseconds
                    )
                }
                tabActivationPolicy.activate()
                isWorkoutsTabVisible = true
                trackOpenWorkoutsIfNeeded()
                seedHistoryCachesFromCurrentQueriesIfNeeded()
                schedulePendingRefreshesIfNeeded()
                scheduleCloudKitHistoryReconciliationIfNeeded()
            }
            .onChange(of: workoutPlan) {
                markRecoveryRefreshNeeded(delayMilliseconds: 140)
            }
            .onChange(of: workoutsRefreshFingerprint) {
                seedHistoryCachesFromCurrentQueriesIfNeeded()
                markHistoryRefreshNeeded()
                markRecoveryRefreshNeeded()
                autoCompleteEligibleGoalsIfNeeded()
            }
            .onChange(of: liveWorkoutsRefreshFingerprint) {
                seedHistoryCachesFromCurrentQueriesIfNeeded()
                markHistoryRefreshNeeded()
                markRecoveryRefreshNeeded(forceRefresh: true)
                autoCompleteEligibleGoalsIfNeeded()
            }
            .onChange(of: workoutGoals.count) {
                if !activeWorkoutGoals.isEmpty {
                    suggestedWorkoutGoals = []
                    clearCachedGoalSuggestionSnapshot()
                }
            }
            .onChange(of: activeWorkoutRuntimeState.isLiveWorkoutPresented) { _, isPresented in
                if !isPresented {
                    guard activeWorkout == nil else { return }
                    markRecoveryRefreshNeeded(
                        forceRefresh: true,
                        delayMilliseconds: 140
                    )
                }
            }
            .onDisappear {
                isWorkoutsTabVisible = false
                tabActivationPolicy.deactivate()
                historyRefreshTask?.cancel()
                deferredRecoveryRefreshTask?.cancel()
                cloudKitHistoryReconciliationTask?.cancel()
            }
            .sheet(isPresented: $showingPlanSetup) {
                WorkoutPlanChatFlow()
                    .traiSheetBranding()
            }
            .sheet(isPresented: $showingPersonalRecords) {
                PersonalRecordsView()
                    .traiSheetBranding()
            }
            .sheet(isPresented: $showingMuscleRecoveryDetail) {
                MuscleRecoveryDetailSheet(recoveryInfo: recoveryInfo)
                    .traiSheetBranding()
            }
            .sheet(item: $showingWorkoutDetail) { workout in
                WorkoutDetailSheet(workout: workout)
                    .traiSheetBranding()
            }
            .sheet(item: $showingLiveWorkoutDetail) { workout in
                LiveWorkoutDetailSheet(
                    workout: workout,
                    useLbs: !(userProfile?.usesMetricExerciseWeight ?? true)
                )
                .traiSheetBranding()
            }
            .sheet(item: $showingWorkoutGoalDetail) { goal in
                WorkoutGoalDetailSheet(
                    goal: goal,
                    workouts: completedLiveWorkouts,
                    sessions: workoutGoalSessions,
                    exerciseHistory: allExerciseHistory,
                    useLbs: !usesMetricExerciseWeight,
                    onToggleCompletion: toggleWorkoutGoalCompletion
                )
            }
            .sheet(isPresented: $showingWorkoutGoalAISetup) {
                WorkoutGoalAISheet(
                    userGoal: userProfile?.goal.displayName,
                    workoutPlan: workoutPlan,
                    workouts: completedLiveWorkouts,
                    sessions: workoutGoalSessions,
                    exerciseHistory: allExerciseHistory,
                    memoryContext: workoutGoalMemoryContext(),
                    existingGoals: workoutGoals,
                    prefersMetricWeight: usesMetricExerciseWeight,
                    initialSuggestions: suggestedWorkoutGoals,
                    onSuggestionsGenerated: { suggestions in
                        suggestedWorkoutGoals = suggestions
                        persistCachedGoalSuggestionSnapshot(suggestions)
                    }
                ) { goals in
                    for goal in goals {
                        modelContext.insert(goal)
                    }
                    try? modelContext.save()
                    suggestedWorkoutGoals = []
                    clearCachedGoalSuggestionSnapshot()
                    HapticManager.success()
                }
                .traiSheetBranding()
            }
            .sheet(isPresented: $showingWorkoutSheet) {
                if let workout = pendingWorkout {
                    LiveWorkoutView(workout: workout, template: pendingTemplate)
                        .traiSheetBranding()
                }
            }
            .sheet(isPresented: $showingCustomWorkoutSetup) {
                CustomWorkoutSetupSheet(
                    onStart: { name, type, muscles, focusAreas in
                    queueCustomWorkoutStart(name: name, type: type, muscles: muscles, focusAreas: focusAreas)
                    },
                    orderedWorkoutTypes: personalizedWorkoutTypes,
                    sessionSuggestions: customWorkoutSuggestions
                )
                .traiSheetBranding()
            }
            .onChange(of: showingCustomWorkoutSetup) { _, isShowing in
                guard !isShowing, let pendingCustomWorkoutStart else { return }
                self.pendingCustomWorkoutStart = nil
                startCustomWorkout(
                    name: pendingCustomWorkoutStart.name,
                    type: pendingCustomWorkoutStart.type,
                    muscles: pendingCustomWorkoutStart.muscles,
                    focusAreas: pendingCustomWorkoutStart.focusAreas
                )
            }
            .onChange(of: showingWorkoutSheet) { _, isShowing in
                if !isShowing {
                    // Clear template when sheet is dismissed
                    pendingTemplate = nil
                }
            }
        }
        .traiBackground()
        .overlay(alignment: .topLeading) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("workoutsRootReady")
        }
        .overlay(alignment: .topLeading) {
            Text(workoutsLatencyProbeLabel)
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(workoutsLatencyProbeLabel)
                .accessibilityIdentifier("workoutsLatencyProbe")
        }
    }

    // MARK: - Actions

    private var workoutsLatencyProbeLabel: String {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return "disabled" }
        return latencyProbeEntries.isEmpty ? "pending" : latencyProbeEntries.joined(separator: " | ")
    }

    private func recordWorkoutsLatencyProbe(
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

    private func loadRecoveryAndScores(forceRefresh: Bool = false) {
        let startedAt = LatencyProbe.timerStart()
        if activeWorkout != nil, !forceRefresh, !recoveryInfo.isEmpty {
            recordWorkoutsLatencyProbe(
                "loadRecoveryAndScoresSkipped",
                startedAt: startedAt,
                counts: [
                    "activeWorkout": 1,
                    "force": forceRefresh ? 1 : 0,
                    "cachedRecovery": recoveryInfo.count
                ]
            )
            return
        }

        guard forceRefresh || DashboardRefreshPolicy.shouldRefreshRecovery(
            isWorkoutRuntimeActive: activeWorkoutRuntimeState.isLiveWorkoutPresented
        ) else {
            recordWorkoutsLatencyProbe(
                "loadRecoveryAndScoresGuarded",
                startedAt: startedAt,
                counts: [
                    "force": forceRefresh ? 1 : 0,
                    "runtimeActive": activeWorkoutRuntimeState.isLiveWorkoutPresented ? 1 : 0
                ]
            )
            return
        }

        let interval = PerformanceTrace.begin("workouts_recovery_scores_refresh", category: .dataLoad)
        defer { PerformanceTrace.end("workouts_recovery_scores_refresh", interval, category: .dataLoad) }

        let latestRecoveryInfo = recoveryService.getRecoveryStatus(
            modelContext: modelContext,
            forceRefresh: forceRefresh
        )
        recoveryInfo = latestRecoveryInfo

        // Score templates if user has a plan
        guard let plan = workoutPlan else {
            templateScores = [:]
            recommendedTemplateId = nil
            hasPendingRecoveryRefresh = false
            pendingRecoveryRefreshShouldForce = false
            persistCachedSectionSnapshot()
            recordWorkoutsLatencyProbe(
                "loadRecoveryAndScoresNoPlan",
                startedAt: startedAt,
                counts: [
                    "recoveryItems": recoveryInfo.count,
                    "force": forceRefresh ? 1 : 0
                ]
            )
            return
        }

        var scores: [UUID: (score: Double, reason: String)] = [:]
        var bestTemplateId: UUID?
        var bestScore = -Double.greatestFiniteMagnitude

        for template in plan.templates {
            guard template.sessionType.supportsMuscleTargets else { continue }
            let scoredTemplate = recoveryService.scoreTemplate(template, recoveryInfo: latestRecoveryInfo)
            scores[template.id] = scoredTemplate
            if scoredTemplate.score > bestScore {
                bestScore = scoredTemplate.score
                bestTemplateId = template.id
            }
        }

        templateScores = scores
        recommendedTemplateId = bestTemplateId
        hasPendingRecoveryRefresh = false
        pendingRecoveryRefreshShouldForce = false
        persistCachedSectionSnapshot()
        recordWorkoutsLatencyProbe(
            "loadRecoveryAndScores",
            startedAt: startedAt,
            counts: [
                "recoveryItems": recoveryInfo.count,
                "templates": plan.templates.count,
                "scoredTemplates": templateScores.count,
                "force": forceRefresh ? 1 : 0
            ]
        )
    }

    private func refreshWorkoutHistoryCaches() {
        let interval = PerformanceTrace.begin("workouts_history_cache_refresh", category: .dataLoad)
        let startedAt = LatencyProbe.timerStart()
        defer { PerformanceTrace.end("workouts_history_cache_refresh", interval, category: .dataLoad) }

        let workoutsForHistory = loadWorkoutHistorySource()
        let liveWorkoutsForHistory = loadLiveWorkoutHistorySource()
        let mergedHealthKitIDs = Set(liveWorkoutsForHistory.compactMap(\.mergedHealthKitWorkoutID))
        let filteredWorkouts = workoutsForHistory.filter { workout in
            guard let healthKitWorkoutID = workout.healthKitWorkoutID else { return true }
            return !mergedHealthKitIDs.contains(healthKitWorkoutID)
        }
        let filteredLiveWorkouts = liveWorkoutsForHistory.filter { $0.completedAt != nil }

        cachedWorkoutsByDate = groupWorkoutsByDay(
            filteredWorkouts,
            maxGroups: Self.maxHistoryDayGroups
        )
        cachedLiveWorkoutsByDate = groupLiveWorkoutsByDay(
            filteredLiveWorkouts,
            maxGroups: Self.maxHistoryDayGroups
        )
        hasPendingHistoryRefresh = false
        recordWorkoutsLatencyProbe(
            "refreshWorkoutHistoryCaches",
            startedAt: startedAt,
            counts: [
                "queryWorkouts": allWorkouts.count,
                "queryLive": allLiveWorkouts.count,
                "historyWorkouts": workoutsForHistory.count,
                "historyLive": liveWorkoutsForHistory.count,
                "filteredWorkouts": filteredWorkouts.count,
                "filteredLive": filteredLiveWorkouts.count,
                "groupedWorkoutDays": cachedWorkoutsByDate.count,
                "groupedLiveDays": cachedLiveWorkoutsByDate.count
            ]
        )
    }

    private func seedHistoryCachesFromCurrentQueriesIfNeeded() {
        guard cachedWorkoutsByDate.isEmpty, cachedLiveWorkoutsByDate.isEmpty else { return }

        let completedInAppWorkouts = completedLiveWorkouts
        guard !allWorkouts.isEmpty || !completedInAppWorkouts.isEmpty else { return }

        let mergedHealthKitIDs = Set(completedInAppWorkouts.compactMap(\.mergedHealthKitWorkoutID))
        let filteredWorkouts = allWorkouts.filter { workout in
            guard let healthKitWorkoutID = workout.healthKitWorkoutID else { return true }
            return !mergedHealthKitIDs.contains(healthKitWorkoutID)
        }

        cachedWorkoutsByDate = groupWorkoutsByDay(
            filteredWorkouts,
            maxGroups: Self.maxHistoryDayGroups
        )
        cachedLiveWorkoutsByDate = groupLiveWorkoutsByDay(
            completedInAppWorkouts,
            maxGroups: Self.maxHistoryDayGroups
        )
    }

    private func persistCachedSectionSnapshot() {
        let snapshot = CachedSectionSnapshot(
            generatedAt: Date(),
            recovery: recoveryInfo.map { info in
                CachedSectionSnapshot.RecoveryInfoItem(
                    muscleGroupRawValue: info.muscleGroup.rawValue,
                    lastTrainedAt: info.lastTrainedAt
                )
            },
            templateScores: templateScores.map { entry in
                CachedSectionSnapshot.TemplateScoreItem(
                    templateId: entry.key.uuidString,
                    score: entry.value.score,
                    reason: entry.value.reason
                )
            },
            recommendedTemplateId: recommendedTemplateId?.uuidString
        )

        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: Self.sectionSnapshotUserDefaultsKey)
    }

    private static func loadCachedSectionSnapshot(now: Date) -> CachedSectionSnapshot? {
        guard let json = UserDefaults.standard.string(forKey: sectionSnapshotUserDefaultsKey),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(CachedSectionSnapshot.self, from: data) else {
            return nil
        }

        let age = now.timeIntervalSince(snapshot.generatedAt)
        guard age >= 0, age <= sectionSnapshotTTLSeconds else { return nil }
        return snapshot
    }

    private static func recoveryInfo(
        from snapshot: CachedSectionSnapshot,
        now: Date
    ) -> [MuscleRecoveryService.MuscleRecoveryInfo] {
        snapshot.recovery.compactMap { item in
            guard let muscleGroup = LiveWorkout.MuscleGroup(rawValue: item.muscleGroupRawValue) else {
                return nil
            }

            let hoursSinceTraining = item.lastTrainedAt.map {
                max(0, now.timeIntervalSince($0) / 3600)
            }
            return MuscleRecoveryService.MuscleRecoveryInfo(
                muscleGroup: muscleGroup,
                status: recoveryStatus(hoursSinceTraining: hoursSinceTraining),
                lastTrainedAt: item.lastTrainedAt,
                hoursSinceTraining: hoursSinceTraining
            )
        }
    }

    private static func recoveryStatus(hoursSinceTraining: Double?) -> MuscleRecoveryService.RecoveryStatus {
        guard let hoursSinceTraining else {
            return .ready
        }
        if hoursSinceTraining >= recoveryReadyThresholdHours {
            return .ready
        }
        if hoursSinceTraining >= recoveryRecoveringThresholdHours {
            return .recovering
        }
        return .tired
    }

    private static func templateScores(
        from snapshot: CachedSectionSnapshot
    ) -> [UUID: (score: Double, reason: String)] {
        var scores: [UUID: (score: Double, reason: String)] = [:]
        for item in snapshot.templateScores {
            guard let id = UUID(uuidString: item.templateId) else { continue }
            scores[id] = (item.score, item.reason)
        }
        return scores
    }

    private static func recommendedTemplateId(from snapshot: CachedSectionSnapshot) -> UUID? {
        guard let rawValue = snapshot.recommendedTemplateId else { return nil }
        return UUID(uuidString: rawValue)
    }

    private static func loadCachedGoalSuggestionSnapshot(now: Date) -> CachedGoalSuggestionSnapshot? {
        guard let json = UserDefaults.standard.string(forKey: goalSuggestionSnapshotUserDefaultsKey),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(CachedGoalSuggestionSnapshot.self, from: data) else {
            return nil
        }

        let age = now.timeIntervalSince(snapshot.generatedAt)
        guard age >= 0, age <= goalSuggestionSnapshotTTLSeconds else { return nil }
        return snapshot
    }

    private struct CachedSectionSnapshot: Codable {
        struct RecoveryInfoItem: Codable {
            let muscleGroupRawValue: String
            let lastTrainedAt: Date?
        }

        struct TemplateScoreItem: Codable {
            let templateId: String
            let score: Double
            let reason: String
        }

        let generatedAt: Date
        let recovery: [RecoveryInfoItem]
        let templateScores: [TemplateScoreItem]
        let recommendedTemplateId: String?
    }

    private struct CachedGoalSuggestionSnapshot: Codable {
        let generatedAt: Date
        let suggestions: [WorkoutGoalSuggestion]
    }

    private func historyWindowStartDate(now: Date = Date()) -> Date {
        Calendar.current.date(
            byAdding: .day,
            value: -Self.workoutHistoryWindowDays,
            to: now
        ) ?? .distantPast
    }

    private func loadWorkoutHistorySource() -> [WorkoutSession] {
        guard hasWorkoutHistoryOverflowBeyondQueryWindow() else {
            return allWorkouts
        }

        let historyCutoff = historyWindowStartDate()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { workout in
                workout.loggedAt >= historyCutoff
            },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? allWorkouts
    }

    private func loadLiveWorkoutHistorySource() -> [LiveWorkout] {
        guard hasLiveWorkoutHistoryOverflowBeyondQueryWindow() else {
            return allLiveWorkouts
        }

        let historyCutoff = historyWindowStartDate()
        let descriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { workout in
                workout.startedAt >= historyCutoff
            },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? allLiveWorkouts
    }

    private func hasWorkoutHistoryOverflowBeyondQueryWindow() -> Bool {
        guard allWorkouts.count >= Self.workoutHistoryFetchLimit else { return false }
        let historyCutoff = historyWindowStartDate()
        var overflowDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { workout in
                workout.loggedAt >= historyCutoff
            },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        overflowDescriptor.fetchOffset = Self.workoutHistoryFetchLimit
        overflowDescriptor.fetchLimit = 1
        let overflow = (try? modelContext.fetch(overflowDescriptor)) ?? []
        return !overflow.isEmpty
    }

    private func hasLiveWorkoutHistoryOverflowBeyondQueryWindow() -> Bool {
        guard allLiveWorkouts.count >= Self.workoutHistoryFetchLimit else { return false }
        let historyCutoff = historyWindowStartDate()
        var overflowDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { workout in
                workout.startedAt >= historyCutoff
            },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        overflowDescriptor.fetchOffset = Self.workoutHistoryFetchLimit
        overflowDescriptor.fetchLimit = 1
        let overflow = (try? modelContext.fetch(overflowDescriptor)) ?? []
        return !overflow.isEmpty
    }

    private func scheduleWorkoutHistoryRefresh(delayMilliseconds: Int = 120) {
        historyRefreshTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        historyRefreshTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isWorkoutsTabActive, hasPendingHistoryRefresh else { return }
                refreshWorkoutHistoryCaches()
            }
        }
    }

    private func scheduleRecoveryAndScoresRefresh(
        forceRefresh: Bool = false,
        delayMilliseconds: Int = 120
    ) {
        deferredRecoveryRefreshTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        deferredRecoveryRefreshTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isWorkoutsTabActive, hasPendingRecoveryRefresh else { return }
                if activeWorkout != nil, !forceRefresh, !recoveryInfo.isEmpty {
                    return
                }
                loadRecoveryAndScores(forceRefresh: forceRefresh)
            }
        }
    }

    private func markHistoryRefreshNeeded(delayMilliseconds: Int = 120) {
        hasPendingHistoryRefresh = true
        guard isWorkoutsTabActive else { return }
        scheduleWorkoutHistoryRefresh(delayMilliseconds: delayMilliseconds)
    }

    private func markRecoveryRefreshNeeded(
        forceRefresh: Bool = false,
        delayMilliseconds: Int = 120
    ) {
        hasPendingRecoveryRefresh = true
        pendingRecoveryRefreshShouldForce = pendingRecoveryRefreshShouldForce || forceRefresh
        guard isWorkoutsTabActive else { return }
        scheduleRecoveryAndScoresRefresh(
            forceRefresh: pendingRecoveryRefreshShouldForce,
            delayMilliseconds: delayMilliseconds
        )
    }

    private func toggleWorkoutGoalCompletion(_ goal: WorkoutGoal) {
        if goal.status == .completed {
            goal.markActive()
            goal.lastCelebratedAt = nil
        } else {
            goal.markCompleted()
            goal.markCelebrated()
            celebratedWorkoutGoal = goal
            HapticManager.success()
        }
        try? modelContext.save()
        HapticManager.selectionChanged()
    }

    private func autoCompleteEligibleGoalsIfNeeded() {
        let eligibleInsights = workoutGoalInsights.filter { insight in
            guard insight.goal.isActive else { return false }
            guard insight.goal.goalKind != .milestone else { return false }
            guard insight.goal.goalKind != .frequency else { return false }
            guard let progressFraction = insight.progressFraction else { return false }
            return progressFraction >= 1
        }

        guard let firstEligible = eligibleInsights.first else { return }
        let goal = firstEligible.goal
        guard goal.lastCelebratedAt == nil else { return }

        goal.markCompleted()
        goal.markCelebrated()
        celebratedWorkoutGoal = goal
        try? modelContext.save()
        HapticManager.success()
    }

    private func startWorkoutGoalsWithTrai() {
        guard canAccessAIFeatures else {
            proUpsellCoordinator?.present(source: .workoutPlan)
            return
        }
        showingWorkoutGoalAISetup = true
        HapticManager.selectionChanged()
    }

    private func startWorkoutGoalCheckIn(_ goal: WorkoutGoal) {
        guard canAccessAIFeatures else {
            proUpsellCoordinator?.present(source: .workoutPlan)
            return
        }

        goal.markCheckedIn()
        try? modelContext.save()

        let context = [
            "Goal: \(goal.trimmedTitle)",
            "Scope: \(goal.scopeSummary)",
            goal.trackingSummary.map { "Tracking: \($0)" },
            goal.horizonSummary,
            goal.trimmedNotes.isEmpty ? nil : "Notes: \(goal.trimmedNotes)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        pendingChatPrompt = """
        Can you check in on this workout goal and help me assess whether it still makes sense, how it has been going lately, and whether it should be refined or updated?

        \(context)
        """
        pendingChatLaunchLabel = "Checking in on your workout goal..."
        appTabSelection.wrappedValue = .trai
        HapticManager.selectionChanged()
    }

    private func persistCachedGoalSuggestionSnapshot(_ suggestions: [WorkoutGoalSuggestion]) {
        let snapshot = CachedGoalSuggestionSnapshot(generatedAt: Date(), suggestions: suggestions)
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: Self.goalSuggestionSnapshotUserDefaultsKey)
    }

    private func clearCachedGoalSuggestionSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.goalSuggestionSnapshotUserDefaultsKey)
    }

    private func workoutGoalMemoryContext() -> [String] {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate<CoachMemory> { memory in
                memory.isActive
            },
            sortBy: [
                SortDescriptor(\CoachMemory.importance, order: .reverse),
                SortDescriptor(\CoachMemory.createdAt, order: .reverse)
            ]
        )

        let memories = (try? modelContext.fetch(descriptor)) ?? []

        return memories
            .filter {
                $0.topic == .workout || $0.topic == .general || $0.category == .goal || $0.category == .context || $0.category == .restriction
            }
            .prefix(8)
            .map(\.promptFormat)
    }

    private func schedulePendingRefreshesIfNeeded() {
        guard isWorkoutsTabActive else { return }

        let isInitialHeavyRefresh = !hasExecutedInitialHeavyRefresh
        if hasPendingHistoryRefresh {
            scheduleWorkoutHistoryRefresh(
                delayMilliseconds: isInitialHeavyRefresh
                    ? Self.initialHistoryRefreshDelayMilliseconds
                    : Self.tabDwellHistoryRefreshDelayMilliseconds
            )
        }
        if hasPendingRecoveryRefresh {
            scheduleRecoveryAndScoresRefresh(
                forceRefresh: pendingRecoveryRefreshShouldForce || isInitialHeavyRefresh,
                delayMilliseconds: isInitialHeavyRefresh
                    ? Self.initialRecoveryRefreshDelayMilliseconds
                    : Self.tabDwellRecoveryRefreshDelayMilliseconds
            )
        }
        if isInitialHeavyRefresh, hasPendingHistoryRefresh || hasPendingRecoveryRefresh {
            hasExecutedInitialHeavyRefresh = true
        }
    }

    private func scheduleCloudKitHistoryReconciliationIfNeeded() {
        cloudKitHistoryReconciliationTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let delays = Self.cloudKitHistoryReconciliationDelaysSeconds
        cloudKitHistoryReconciliationTask = Task(priority: .utility) {
            for delaySeconds in delays {
                if delaySeconds > 0 {
                    try? await Task.sleep(for: .seconds(delaySeconds))
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                    guard isWorkoutsTabActive else { return }
                    // Reconcile history after launch in case CloudKit rows arrive after first paint.
                    markHistoryRefreshNeeded(delayMilliseconds: 80)
                }
            }
        }
    }

    private func groupWorkoutsByDay(
        _ workouts: [WorkoutSession],
        maxGroups: Int
    ) -> [(date: Date, workouts: [WorkoutSession])] {
        guard !workouts.isEmpty, maxGroups > 0 else { return [] }

        let calendar = Calendar.current
        var grouped: [(date: Date, workouts: [WorkoutSession])] = []
        var currentDate = calendar.startOfDay(for: workouts[0].loggedAt)
        var currentItems: [WorkoutSession] = []

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.loggedAt)
            if day == currentDate {
                currentItems.append(workout)
                continue
            }

            grouped.append((date: currentDate, workouts: currentItems))
            if grouped.count >= maxGroups {
                return grouped
            }

            currentDate = day
            currentItems = [workout]
        }

        if !currentItems.isEmpty, grouped.count < maxGroups {
            grouped.append((date: currentDate, workouts: currentItems))
        }
        return grouped
    }

    private func groupLiveWorkoutsByDay(
        _ workouts: [LiveWorkout],
        maxGroups: Int
    ) -> [(date: Date, workouts: [LiveWorkout])] {
        guard !workouts.isEmpty, maxGroups > 0 else { return [] }

        let calendar = Calendar.current
        var grouped: [(date: Date, workouts: [LiveWorkout])] = []
        var currentDate = calendar.startOfDay(for: workouts[0].startedAt)
        var currentItems: [LiveWorkout] = []

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startedAt)
            if day == currentDate {
                currentItems.append(workout)
                continue
            }

            grouped.append((date: currentDate, workouts: currentItems))
            if grouped.count >= maxGroups {
                return grouped
            }

            currentDate = day
            currentItems = [workout]
        }

        if !currentItems.isEmpty, grouped.count < maxGroups {
            grouped.append((date: currentDate, workouts: currentItems))
        }
        return grouped
    }

    private func trackOpenWorkoutsIfNeeded() {
        let now = Date()
        if let lastOpenTrackedAt, now.timeIntervalSince(lastOpenTrackedAt) < 8 * 60 {
            return
        }
        lastOpenTrackedAt = now
        BehaviorTracker(modelContext: modelContext).recordDeferred(
            actionKey: BehaviorActionKey.openWorkouts,
            domain: .workout,
            surface: .workouts,
            outcome: .opened,
            metadata: ["source": "workouts_tab"]
        )
    }

    private func startWorkoutFromTemplate(_ template: WorkoutPlan.WorkoutTemplate) {
        let workout = templateService.createStartWorkout(from: template)
        _ = templateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .workouts,
            outcome: .performed,
            relatedEntityId: workout.id,
            metadata: [
                "type": "template",
                "template_name": template.name
            ]
        )

        // Store template for suggestions and open the workout sheet
        pendingTemplate = template
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func startCustomWorkout(
        name: String = "Custom Workout",
        type: LiveWorkout.WorkoutType = .strength,
        muscles: [LiveWorkout.MuscleGroup] = [],
        focusAreas: [String] = []
    ) {
        let workout = templateService.createCustomWorkout(
            name: name,
            type: type,
            muscles: muscles,
            focusAreas: focusAreas
        )
        _ = templateService.persistWorkout(workout, modelContext: modelContext)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.startWorkout,
            domain: .workout,
            surface: .workouts,
            outcome: .performed,
            relatedEntityId: workout.id,
            metadata: [
                "type": "custom",
                "workout_type": type.rawValue
            ]
        )

        // Open the workout sheet
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func queueCustomWorkoutStart(
        name: String,
        type: LiveWorkout.WorkoutType,
        muscles: [LiveWorkout.MuscleGroup],
        focusAreas: [String]
    ) {
        let request = PendingCustomWorkoutStart(name: name, type: type, muscles: muscles, focusAreas: focusAreas)
        guard showingCustomWorkoutSetup else {
            startCustomWorkout(
                name: request.name,
                type: request.type,
                muscles: request.muscles,
                focusAreas: request.focusAreas
            )
            return
        }
        pendingCustomWorkoutStart = request
    }

    private func deleteWorkout(_ workout: WorkoutSession) {
        modelContext.delete(workout)
        try? modelContext.save()
    }

    private func deleteLiveWorkout(_ workout: LiveWorkout) {
        // Delete associated ExerciseHistory entries
        if let entries = workout.entries {
            for entry in entries {
                let entryId = entry.id
                let descriptor = FetchDescriptor<ExerciseHistory>(
                    predicate: #Predicate<ExerciseHistory> { history in
                        history.sourceWorkoutEntryId == entryId
                    }
                )
                let historyToDelete = (try? modelContext.fetch(descriptor)) ?? []
                for history in historyToDelete {
                    modelContext.delete(history)
                }
            }
        }

        modelContext.delete(workout)
        try? modelContext.save()
    }

    private func syncHealthKit() async {
        guard let healthKitService else { return }

        do {
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let healthKitWorkouts = try await healthKitService.fetchWorkoutsAuthorized(from: oneMonthAgo, to: Date())

            // Filter out already imported workouts
            let existingIDs = fetchExistingHealthKitWorkoutIDs(from: oneMonthAgo)
            let newWorkouts = healthKitWorkouts.filter { workout in
                guard let id = workout.healthKitWorkoutID, !id.isEmpty else { return true }
                return !existingIDs.contains(id)
            }

            for workout in newWorkouts {
                modelContext.insert(workout)
            }

            if !newWorkouts.isEmpty {
                try? modelContext.save()
            }

            // Retroactively merge past workouts that weren't merged at completion time
            await mergeUnmergedWorkouts(healthKitWorkouts: healthKitWorkouts, healthKitService: healthKitService)
        } catch {
            // Handle error silently
        }
    }

    private func fetchExistingHealthKitWorkoutIDs(from startDate: Date) -> Set<String> {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { workout in
                workout.loggedAt >= startDate && workout.healthKitWorkoutID != nil
            }
        )
        let existingWorkouts = (try? modelContext.fetch(descriptor)) ?? []
        return Set(existingWorkouts.compactMap(\.healthKitWorkoutID))
    }

    /// Retroactively merge completed in-app workouts with HealthKit data
    private func mergeUnmergedWorkouts(
        healthKitWorkouts: [WorkoutSession],
        healthKitService: HealthKitService
    ) async {
        // Find completed workouts without HealthKit merge inside the sync window.
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { workout in
                workout.completedAt != nil &&
                workout.mergedHealthKitWorkoutID == nil &&
                workout.startedAt >= oneMonthAgo
            },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        let unmergedWorkouts = (try? modelContext.fetch(descriptor)) ?? []

        guard !unmergedWorkouts.isEmpty else { return }

        var merged = false
        for workout in unmergedWorkouts {
            if let match = healthKitService.bestOverlappingWorkout(
                for: workout,
                from: healthKitWorkouts,
                searchBufferMinutes: 15
            ) {
                workout.mergedHealthKitWorkoutID = match.healthKitWorkoutID
                if let calories = match.caloriesBurned {
                    workout.healthKitCalories = Double(calories)
                }
                if let avgHR = match.averageHeartRate {
                    workout.healthKitAvgHeartRate = Double(avgHR)
                }
                merged = true
            }
        }

        if merged {
            try? modelContext.save()
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutsView()
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            Exercise.self,
            LiveWorkout.self,
            LiveWorkoutEntry.self,
            ExerciseHistory.self
        ], inMemory: true)
}
