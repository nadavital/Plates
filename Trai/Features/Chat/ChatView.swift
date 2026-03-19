//
//  ChatView.swift
//  Trai
//
//  Main chat view with AI fitness coach
//  Components: ChatMessageViews.swift, ChatMealComponents.swift,
//              ChatInputBar.swift, ChatCameraComponents.swift
//

import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    struct MealSuggestionKey: Hashable {
        let messageId: UUID
        let mealId: String
    }

    // Track if we've started a fresh session this app launch
    static var hasStartedFreshSession = false
    private static let foodHistoryWindowDays = 120
    private static let workoutHistoryWindowDays = 120
    private static let weightHistoryWindowDays = 240
    private static let behaviorHistoryWindowDays = 90
    private static let chatMessageFetchLimit = 64
    private static let foodFetchLimit = 48
    private static let workoutFetchLimit = 48
    private static let weightFetchLimit = 48
    private static let behaviorFetchLimit = 48
    private static let activeMemoriesFetchLimit = 48
    private static let activeSignalsFetchLimit = 48
    private static let suggestionUsageFetchLimit = 64
    private static let initialSessionPreviewMessageLimit = 20
    private static let startupMessageCacheDelayMilliseconds = 3200
    private static let startupSmartStarterDelayMilliseconds = 2600
    private static let chatReactivationCooldownSeconds: TimeInterval = 45
    private static let chatRecommendationCooldownSeconds: TimeInterval = 90
    private static var chatHeavyRefreshMinimumDwellMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 1400 : 320
    }
    private static var chatActivationWorkDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2600 : 260
    }
    private static var startupFullHistoryHydrationDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 3600 : 680
    }

    /// Optional workout context for mid-workout chat
    var workoutContext: GeminiService.WorkoutContext?

    @Query var allMessages: [ChatMessage]

    @Query var profiles: [UserProfile]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    var allFoodEntries: [FoodEntry]
    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    var recentWorkouts: [WorkoutSession]
    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    var liveWorkouts: [LiveWorkout]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    var weightEntries: [WeightEntry]
    @Query var activeMemories: [CoachMemory]
    @Query var activeSignals: [CoachSignal]
    @Query var suggestionUsage: [SuggestionUsage]
    @Query(sort: \BehaviorEvent.occurredAt, order: .reverse)
    var behaviorEvents: [BehaviorEvent]

    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTabSelection) private var appTabSelection
    @Environment(HealthKitService.self) var healthKitService: HealthKitService?
    @State var geminiService = GeminiService()
    @State var recoveryService = MuscleRecoveryService.shared
    @State var isLoading = false
    @State var currentActivity: String?
    @State var selectedImage: UIImage?
    @State var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var enlargedImage: UIImage?
    @State private var editingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)?
    @State private var editingPlanSuggestion: (message: ChatMessage, plan: PlanUpdateSuggestionEntry)?
    @State private var viewingLoggedMealId: UUID?
    @State private var viewingAppliedPlan: PlanUpdateSuggestionEntry?
    @FocusState private var isInputFocused: Bool
    @AppStorage("currentChatSessionId") var currentSessionIdString: String = ""
    @AppStorage("lastChatActivityDate") var lastActivityTimestamp: Double = 0
    @AppStorage("pendingPlanReviewRequest") var pendingPlanReviewRequest: Bool = false
    @AppStorage("pendingWorkoutPlanReviewRequest") var pendingWorkoutPlanReviewRequest: Bool = false
    @AppStorage(TraiCoachTone.storageKey) var coachToneRaw: String = TraiCoachTone.encouraging.rawValue
    @State var isTemporarySession = false
    @State var temporaryMessages: [ChatMessage] = []
    @State var processingMealSuggestionKeys: Set<MealSuggestionKey> = []

    // Plan assessment
    @State var planAssessmentService = PlanAssessmentService()
    @State var pendingPlanRecommendation: PlanRecommendation?
    @State var planRecommendationMessage: String?

    // Reminder editing
    @State var pendingReminderEdit: SuggestedReminder?
    @State var showReminderEditSheet = false

    // Task tracking for cancellation
    @State var currentMessageTask: Task<Void, Never>?

    let sessionTimeoutHours: Double = 1.5

    var profile: UserProfile? { profiles.first }
    var coachTone: TraiCoachTone { TraiCoachTone.resolve(rawValue: coachToneRaw) }

    @State private var cachedSessionMessages: [ChatMessage] = []
    @State private var cachedChatSessions: [(id: UUID, firstMessage: String, date: Date)] = []
    @State private var cachedMessagesBySession: [UUID: [ChatMessage]] = [:]
    @State private var messageCacheRebuildTask: Task<Void, Never>?
    @State private var fullHistoryHydrationTask: Task<Void, Never>?
    @State private var deferredRecommendationTask: Task<Void, Never>?
    @State private var startupHydrationTask: Task<Void, Never>?
    @State private var deferredActivationWorkTask: Task<Void, Never>?
    @State private var suppressAutomaticMessageCacheRebuild = false
    @State private var lastMessageCacheFingerprint: MessageCacheFingerprint?
    @State private var activationWorkPolicy = ChatActivationWorkPolicy(
        fullActivationCooldownSeconds: Self.chatReactivationCooldownSeconds,
        recommendationCooldownSeconds: Self.chatRecommendationCooldownSeconds
    )
    @State private var smartStarterTodayFoodCount = 0
    @State private var smartStarterTodayCalories = 0
    @State private var smartStarterTodayProtein = 0
    @State private var smartStarterLastWorkoutDate: Date?
    @State private var isChatTabVisible = false
    @State private var hasHydratedFullMessageHistory = false
    @State private var latencyProbeEntries: [String] = []
    @State private var tabActivationPolicy = TabActivationPolicy(minimumDwellMilliseconds: 0)

    private struct MessageCacheFingerprint: Equatable {
        let count: Int
        let newestMessageId: UUID?
        let newestTimestamp: Date?
        let oldestMessageId: UUID?
        let oldestTimestamp: Date?
    }

    init(workoutContext: GeminiService.WorkoutContext? = nil) {
        self.workoutContext = workoutContext

        let now = Date()
        let calendar = Calendar.current
        let foodCutoff = calendar.date(
            byAdding: .day,
            value: -Self.foodHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let workoutCutoff = calendar.date(
            byAdding: .day,
            value: -Self.workoutHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let weightCutoff = calendar.date(
            byAdding: .day,
            value: -Self.weightHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let behaviorCutoff = calendar.date(
            byAdding: .day,
            value: -Self.behaviorHistoryWindowDays,
            to: now
        ) ?? .distantPast
        let signalCutoff = calendar.date(
            byAdding: .day,
            value: -30,
            to: now
        ) ?? .distantPast

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        _profiles = Query(profileDescriptor)

        var activeMemoriesDescriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate<CoachMemory> { $0.isActive },
            sortBy: [
                SortDescriptor(\CoachMemory.importance, order: .reverse),
                SortDescriptor(\CoachMemory.createdAt, order: .reverse)
            ]
        )
        activeMemoriesDescriptor.fetchLimit = Self.activeMemoriesFetchLimit
        _activeMemories = Query(activeMemoriesDescriptor)

        var activeSignalsDescriptor = FetchDescriptor<CoachSignal>(
            predicate: #Predicate<CoachSignal> {
                !$0.isResolved && $0.createdAt >= signalCutoff
            },
            sortBy: [SortDescriptor(\CoachSignal.createdAt, order: .reverse)]
        )
        activeSignalsDescriptor.fetchLimit = Self.activeSignalsFetchLimit
        _activeSignals = Query(activeSignalsDescriptor)

        var suggestionUsageDescriptor = FetchDescriptor<SuggestionUsage>(
            sortBy: [SortDescriptor(\SuggestionUsage.tapCount, order: .reverse)]
        )
        suggestionUsageDescriptor.fetchLimit = Self.suggestionUsageFetchLimit
        _suggestionUsage = Query(suggestionUsageDescriptor)

        var messageDescriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\ChatMessage.timestamp, order: .reverse)]
        )
        messageDescriptor.fetchLimit = Self.chatMessageFetchLimit
        _allMessages = Query(messageDescriptor)

        var foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.loggedAt >= foodCutoff },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        foodDescriptor.fetchLimit = Self.foodFetchLimit
        _allFoodEntries = Query(foodDescriptor)

        var workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.loggedAt >= workoutCutoff },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = Self.workoutFetchLimit
        _recentWorkouts = Query(workoutDescriptor)

        var liveWorkoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { $0.startedAt >= workoutCutoff },
            sortBy: [SortDescriptor(\LiveWorkout.startedAt, order: .reverse)]
        )
        liveWorkoutDescriptor.fetchLimit = Self.workoutFetchLimit
        _liveWorkouts = Query(liveWorkoutDescriptor)

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate<WeightEntry> { $0.loggedAt >= weightCutoff },
            sortBy: [SortDescriptor(\WeightEntry.loggedAt, order: .reverse)]
        )
        weightDescriptor.fetchLimit = Self.weightFetchLimit
        _weightEntries = Query(weightDescriptor)

        var behaviorDescriptor = FetchDescriptor<BehaviorEvent>(
            predicate: #Predicate<BehaviorEvent> { $0.occurredAt >= behaviorCutoff },
            sortBy: [SortDescriptor(\BehaviorEvent.occurredAt, order: .reverse)]
        )
        behaviorDescriptor.fetchLimit = Self.behaviorFetchLimit
        _behaviorEvents = Query(behaviorDescriptor)
    }

    var currentSessionId: UUID {
        if let uuid = UUID(uuidString: currentSessionIdString) {
            return uuid
        }
        let newId = UUID()
        currentSessionIdString = newId.uuidString
        return newId
    }

    var currentSessionMessages: [ChatMessage] {
        cachedSessionMessages
    }

    private var chatSessions: [(id: UUID, firstMessage: String, date: Date)] {
        cachedChatSessions
    }

    private var isStreamingResponse: Bool {
        guard let lastMessage = currentSessionMessages.last else { return false }
        // Only consider it "streaming" if we have content arriving (not initial thinking state)
        return !lastMessage.isFromUser && isLoading && !lastMessage.content.isEmpty
    }

    var todaysFoodEntries: [FoodEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allFoodEntries.filter { $0.loggedAt >= startOfDay }
    }

    var pendingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)? {
        for message in currentSessionMessages.reversed() {
            if let meal = message.pendingMealSuggestions.first?.meal {
                return (message, meal)
            }
        }
        return nil
    }

    private var viewingFoodEntry: FoodEntry? {
        guard let id = viewingLoggedMealId else { return nil }
        return allFoodEntries.first { $0.id == id }
    }

    private var enabledMacrosValue: Set<MacroType> {
        profile?.enabledMacros ?? MacroType.defaultEnabled
    }

    private var smartStarterContext: SmartStarterContext {
        return SmartStarterContext(
            userName: profile?.name ?? "",
            todayFoodCount: smartStarterTodayFoodCount,
            todayCalories: smartStarterTodayCalories,
            calorieGoal: profile?.dailyCalorieGoal ?? 2000,
            todayProtein: smartStarterTodayProtein,
            proteinGoal: profile?.dailyProteinGoal ?? 150,
            lastWorkoutDate: smartStarterLastWorkoutDate,
            hasActiveWorkout: workoutContext != nil,
            goalType: profile?.goal.rawValue ?? "maintenance"
        )
    }

    private var hasPendingStartupActions: Bool {
        pendingPlanReviewRequest
            || pendingWorkoutPlanReviewRequest
    }

    private var isChatTabActive: Bool {
        isChatTabVisible
    }

    private var isTraiTabSelected: Bool {
        appTabSelection.wrappedValue == .trai
    }

    private var smartStarterFoodRefreshFingerprint: String {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayEntries = allFoodEntries.filter { $0.loggedAt >= startOfDay }
        guard !todayEntries.isEmpty else { return "0" }

        var parts: [String] = []
        parts.reserveCapacity(1 + (todayEntries.count * 5))
        parts.append(String(todayEntries.count))
        for entry in todayEntries {
            parts.append(entry.id.uuidString)
            parts.append(String(entry.loggedAt.timeIntervalSinceReferenceDate))
            parts.append(String(entry.calories))
            parts.append(String(entry.proteinGrams))
            parts.append(String(entry.carbsGrams))
        }
        return parts.joined(separator: "|")
    }

    private var allMessagesWindowFingerprint: String {
        let count = allMessages.count
        guard let newest = allMessages.first else {
            return "0"
        }
        let oldest = allMessages.last ?? newest
        return [
            String(count),
            newest.id.uuidString,
            String(newest.timestamp.timeIntervalSinceReferenceDate),
            oldest.id.uuidString,
            String(oldest.timestamp.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private var chatContentList: some View {
        ChatContentSection(
            messages: currentSessionMessages,
            isLoading: isLoading,
            isStreamingResponse: isStreamingResponse,
            isTemporarySession: isTemporarySession,
            smartStarterContext: smartStarterContext,
            currentActivity: currentActivity,
            currentCalories: profile?.dailyCalorieGoal,
            currentProtein: profile?.dailyProteinGoal,
            currentCarbs: profile?.dailyCarbsGoal,
            currentFat: profile?.dailyFatGoal,
            enabledMacros: enabledMacrosValue,
            planRecommendation: pendingPlanRecommendation,
            planRecommendationMessage: planRecommendationMessage,
            onAcceptMeal: acceptMealSuggestion,
            isMealLogging: isMealSuggestionProcessing,
            onEditMeal: { message, meal in
                editingMealSuggestion = (message, meal)
            },
            onDismissMeal: { meal, message in dismissMealSuggestion(meal, for: message) },
            onViewLoggedMeal: { entryId in
                viewingLoggedMealId = entryId
            },
            onAcceptPlan: acceptPlanSuggestion,
            onEditPlan: { message, plan in
                editingPlanSuggestion = (message, plan)
            },
            onDismissPlan: dismissPlanSuggestion,
            onAcceptFoodEdit: acceptFoodEditSuggestion,
            onDismissFoodEdit: dismissFoodEditSuggestion,
            onAcceptWorkout: acceptWorkoutSuggestion,
            onDismissWorkout: dismissWorkoutSuggestion,
            onAcceptWorkoutLog: acceptWorkoutLogSuggestion,
            onDismissWorkoutLog: dismissWorkoutLogSuggestion,
            onAcceptReminder: acceptReminderSuggestion,
            onEditReminder: { reminder, message in
                pendingReminderEdit = reminder
                showReminderEditSheet = true
            },
            onDismissReminder: dismissReminderSuggestion,
            useExerciseWeightLbs: !(profile?.usesMetricExerciseWeight ?? true),
            onRetry: retryMessage,
            onImageTapped: { image in enlargedImage = image },
            onViewAppliedPlan: { plan in viewingAppliedPlan = plan },
            onReviewPlan: handlePlanReviewRequest,
            onDismissPlanRecommendation: handleDismissPlanRecommendation
        )
    }

    func mealSuggestionKey(for meal: SuggestedFoodEntry, in message: ChatMessage) -> MealSuggestionKey {
        MealSuggestionKey(messageId: message.id, mealId: meal.id)
    }

    private func isMealSuggestionProcessing(_ meal: SuggestedFoodEntry, for message: ChatMessage) -> Bool {
        processingMealSuggestionKeys.contains(mealSuggestionKey(for: meal, in: message))
    }

    var body: some View {
        NavigationStack {
            ChatRootView(
                content: chatContentAnyView,
                inputBar: chatInputBarAnyView,
                isInputFocused: isInputFocusedBinding,
                messageCount: currentSessionMessages.count,
                lastMessageId: currentSessionMessages.last?.id,
                selectedPhotoItem: selectedPhotoItem,
                onPhotoSelected: handleSelectedPhotoItem,
                onAppear: {
                    handleChatTabAppear()
                },
                onSessionIdChange: {
                    rebuildSessionMessages()
                },
                onTemporaryChange: {
                    rebuildSessionMessages()
                },
                onTemporaryMessagesChange: {
                    rebuildSessionMessages()
                },
                onAllMessagesChange: {
                    if suppressAutomaticMessageCacheRebuild {
                        rebuildSessionMessages(preferLiveQueryData: true)
                        return
                    }
                    scheduleMessageCacheRebuild()
                },
                currentSessionIdString: currentSessionIdString,
                isTemporarySession: isTemporarySession,
                temporaryMessagesCount: temporaryMessages.count,
                allMessagesFingerprint: allMessagesWindowFingerprint,
                chatSessions: chatSessions,
                onToggleTemporaryMode: {
                    toggleTemporaryMode()
                    HapticManager.lightTap()
                },
                onSelectSession: switchToSession,
                onClearHistory: clearAllChats,
                onNewChat: { startNewSession() },
                showingCamera: $showingCamera,
                onCameraImage: { image in selectedImage = image },
                enlargedImage: $enlargedImage,
                editingMealSuggestion: $editingMealSuggestion,
                enabledMacrosValue: enabledMacrosValue,
                onAcceptMeal: { meal, message in acceptMealSuggestion(meal, for: message) },
                editingPlanSuggestion: $editingPlanSuggestion,
                currentCalories: profile?.dailyCalorieGoal ?? 2000,
                currentProtein: profile?.dailyProteinGoal ?? 150,
                currentCarbs: profile?.dailyCarbsGoal ?? 200,
                currentFat: profile?.dailyFatGoal ?? 65,
                onAcceptPlan: { plan, message in acceptPlanSuggestion(plan, for: message) },
                viewingFoodEntry: viewingFoodEntry,
                viewingLoggedMealId: $viewingLoggedMealId,
                viewingAppliedPlan: $viewingAppliedPlan
            )
        }
        .onDisappear {
            handleChatTabDeactivation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                guard isTraiTabSelected else { return }
                handleChatTabAppear()
            } else {
                handleChatTabDeactivation()
            }
        }
        .onChange(of: appTabSelection.wrappedValue) { _, selectedTab in
            if selectedTab == .trai {
                guard scenePhase == .active else { return }
                handleChatTabAppear()
            } else {
                handleChatTabDeactivation()
            }
        }
        .onChange(of: smartStarterFoodRefreshFingerprint) { _, _ in
            guard isChatTabActive else { return }
            refreshSmartStarterCache()
        }
        .onChange(of: recentWorkouts.count) {
            guard isChatTabActive else { return }
            refreshSmartStarterCache()
        }
        .onChange(of: liveWorkouts.count) {
            guard isChatTabActive else { return }
            refreshSmartStarterCache()
        }
        .traiBackground()
        .overlay(alignment: .topLeading) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("traiRootReady")
        }
        .overlay(alignment: .topLeading) {
            Text(chatLatencyProbeLabel)
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chatLatencyProbeLabel)
                .accessibilityIdentifier("traiLatencyProbe")
        }
    }

    private var chatLatencyProbeLabel: String {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return "disabled" }
        return latencyProbeEntries.isEmpty ? "pending" : latencyProbeEntries.joined(separator: " | ")
    }

    private func recordChatLatencyProbe(
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

    private var isInputFocusedBinding: Binding<Bool> {
        Binding(
            get: { isInputFocused },
            set: { isInputFocused = $0 }
        )
    }

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            // Show suggestion rows when chat is empty (not in incognito)
            if currentSessionMessages.isEmpty && !isTemporarySession {
                SuggestionRowsView(
                    context: smartStarterContext,
                    suggestionUsage: suggestionUsage,
                    onSuggestionTapped: sendMessage,
                    onTrackTap: trackSuggestionTap
                )
                .transition(.opacity)
            }

            ChatInputBar(
                selectedImage: $selectedImage,
                selectedPhotoItem: $selectedPhotoItem,
                isLoading: isLoading,
                onSend: { text in sendMessage(text) },
                onStop: stopGenerating,
                onTakePhoto: { showingCamera = true },
                onImageTapped: { image in enlargedImage = image },
                isFocused: $isInputFocused
            )
        }
        .animation(.easeInOut(duration: 0.25), value: isTemporarySession)
    }

    private var chatContentAnyView: AnyView {
        AnyView(chatContentList)
    }

    private var chatInputBarAnyView: AnyView {
        AnyView(chatInputBar)
    }

    private func rebuildMessageCaches(
        force: Bool = false,
        sourceMessages explicitSourceMessages: [ChatMessage]? = nil
    ) {
        let startedAt = LatencyProbe.timerStart()
        let sourceMessages = explicitSourceMessages ?? messageCacheSourceMessages(forceFullFetch: force)
        let fingerprint = makeMessageFingerprint(from: sourceMessages)
        if !force, fingerprint == lastMessageCacheFingerprint, !cachedMessagesBySession.isEmpty {
            rebuildSessionMessages()
            recordChatLatencyProbe(
                "rebuildMessageCachesReuse",
                startedAt: startedAt,
                counts: [
                    "allMessages": sourceMessages.count,
                    "sessions": cachedMessagesBySession.count,
                    "currentSessionMessages": cachedSessionMessages.count
                ]
            )
            return
        }
        lastMessageCacheFingerprint = fingerprint

        var sessions: [UUID: (firstMessage: String, date: Date)] = [:]
        var messagesBySession: [UUID: [ChatMessage]] = [:]
        for message in sourceMessages.reversed() {
            guard let sessionId = message.sessionId else { continue }
            messagesBySession[sessionId, default: []].append(message)
            if sessions[sessionId] == nil {
                sessions[sessionId] = (message.content, message.timestamp)
            }
        }

        cachedMessagesBySession = messagesBySession
        cachedChatSessions = sessions
            .map { (id: $0.key, firstMessage: $0.value.firstMessage, date: $0.value.date) }
            .sorted { $0.date > $1.date }
        rebuildSessionMessages()
        recordChatLatencyProbe(
            "rebuildMessageCaches",
            startedAt: startedAt,
            counts: [
                "allMessages": sourceMessages.count,
                "windowMessages": allMessages.count,
                "sessions": cachedMessagesBySession.count,
                "chatSessions": cachedChatSessions.count,
                "currentSessionMessages": cachedSessionMessages.count
            ]
        )
    }

    private func makeMessageFingerprint(from messages: [ChatMessage]) -> MessageCacheFingerprint {
        MessageCacheFingerprint(
            count: messages.count,
            newestMessageId: messages.first?.id,
            newestTimestamp: messages.first?.timestamp,
            oldestMessageId: messages.last?.id,
            oldestTimestamp: messages.last?.timestamp
        )
    }

    private func messageCacheSourceMessages(forceFullFetch: Bool = false) -> [ChatMessage] {
        guard forceFullFetch || hasHydratedFullMessageHistory else {
            return allMessages
        }
        return fetchAllMessagesSortedDescending()
    }

    private func fetchAllMessagesSortedDescending() -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\ChatMessage.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? allMessages
    }

    private func scheduleMessageCacheRebuild(
        immediate: Bool = false,
        delayMilliseconds: Int? = nil
    ) {
        messageCacheRebuildTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let defaultDelay = AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 900 : 220
        let requestedDelay = immediate ? 0 : (delayMilliseconds ?? defaultDelay)
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: requestedDelay
        )
        messageCacheRebuildTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isChatTabActive else { return }
                rebuildMessageCaches(force: immediate)
            }
        }
    }

    func rebuildSessionMessages(
        previewLimit: Int? = nil,
        preferLiveQueryData: Bool = false
    ) {
        let startedAt = LatencyProbe.timerStart()
        if isTemporarySession {
            cachedSessionMessages = temporaryMessages.sorted { $0.timestamp < $1.timestamp }
        } else {
            if !preferLiveQueryData, let cached = cachedMessagesBySession[currentSessionId] {
                if let previewLimit, previewLimit > 0 {
                    cachedSessionMessages = Array(cached.suffix(previewLimit))
                } else {
                    cachedSessionMessages = cached
                }
            } else {
                if let previewLimit, previewLimit > 0 {
                    cachedSessionMessages = recentMessagesForCurrentSession(limit: previewLimit)
                } else {
                    cachedSessionMessages = allMessages
                        .filter { $0.sessionId == currentSessionId }
                        .sorted { $0.timestamp < $1.timestamp }
                }
            }
        }
        recordChatLatencyProbe(
            "rebuildSessionMessages",
            startedAt: startedAt,
            counts: [
                "previewLimit": previewLimit ?? 0,
                "allMessages": allMessages.count,
                "cachedSessions": cachedMessagesBySession.count,
                "sessionMessages": cachedSessionMessages.count,
                "preferLive": preferLiveQueryData ? 1 : 0,
                "temporary": isTemporarySession ? 1 : 0
            ]
        )
    }

    private func recentMessagesForCurrentSession(limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }

        let sessionId = currentSessionId
        var result: [ChatMessage] = []
        result.reserveCapacity(limit)

        for message in allMessages {
            guard message.sessionId == sessionId else { continue }
            result.append(message)
            if result.count >= limit {
                break
            }
        }

        return Array(result.reversed())
    }

    private func scheduleDeferredPlanRecommendationIfNeeded() {
        deferredRecommendationTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let requestedDelay = AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 900 : 320
        let delayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(requested: requestedDelay)
        deferredRecommendationTask = Task(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isChatTabActive else { return }
                guard activationWorkPolicy.shouldRunRecommendationCheck() else { return }
                activationWorkPolicy.markRecommendationCheckRun()
                checkForPlanRecommendation()
            }
        }
    }

    private func scheduleStartupHydration() {
        startupHydrationTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let delayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: Self.startupSmartStarterDelayMilliseconds
        )
        startupHydrationTask = Task(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isChatTabActive else { return }
                refreshSmartStarterCache()
                suppressAutomaticMessageCacheRebuild = false
                scheduleMessageCacheRebuild(
                    delayMilliseconds: Self.startupMessageCacheDelayMilliseconds
                )
            }
        }
    }

    private func handleChatTabAppear() {
        let startedAt = LatencyProbe.timerStart()
        if tabActivationPolicy.activeSince == nil {
            tabActivationPolicy = TabActivationPolicy(
                minimumDwellMilliseconds: Self.chatHeavyRefreshMinimumDwellMilliseconds
            )
        }
        suppressAutomaticMessageCacheRebuild = false
        tabActivationPolicy.activate()
        isChatTabVisible = true
        refreshSessionForActivation(previewLimit: Self.initialSessionPreviewMessageLimit)
        scheduleFullMessageHistoryHydrationIfNeeded()

        let shouldScheduleActivationWork = shouldRunFullActivationWork
        if shouldScheduleActivationWork {
            scheduleDeferredFullActivationWork()
        }
        recordChatLatencyProbe(
            "handleChatTabAppear",
            startedAt: startedAt,
            counts: [
                "allMessages": allMessages.count,
                "sessionMessages": currentSessionMessages.count,
                "hasPendingStartup": hasPendingStartupActions ? 1 : 0,
                "scheduledActivation": shouldScheduleActivationWork ? 1 : 0
            ]
        )
    }

    private func handleChatTabDeactivation() {
        guard isChatTabVisible || tabActivationPolicy.activeSince != nil else { return }
        isChatTabVisible = false
        tabActivationPolicy.deactivate()
        messageCacheRebuildTask?.cancel()
        fullHistoryHydrationTask?.cancel()
        deferredRecommendationTask?.cancel()
        startupHydrationTask?.cancel()
        deferredActivationWorkTask?.cancel()
        suppressAutomaticMessageCacheRebuild = false
    }

    private func refreshSessionForActivation(previewLimit: Int? = nil) {
        checkSessionTimeout()
        rebuildSessionMessages(previewLimit: previewLimit)
    }

    private func scheduleFullMessageHistoryHydrationIfNeeded() {
        guard !hasHydratedFullMessageHistory else { return }
        fullHistoryHydrationTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let delayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: Self.startupFullHistoryHydrationDelayMilliseconds
        )
        fullHistoryHydrationTask = Task(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isChatTabActive else { return }
                let startedAt = LatencyProbe.timerStart()
                let fullMessages = fetchAllMessagesSortedDescending()
                hasHydratedFullMessageHistory = true
                rebuildMessageCaches(force: true, sourceMessages: fullMessages)
                recordChatLatencyProbe(
                    "hydrateFullMessageHistory",
                    startedAt: startedAt,
                    counts: [
                        "fullMessages": fullMessages.count,
                        "windowMessages": allMessages.count
                    ]
                )
            }
        }
    }

    private var shouldRunFullActivationWork: Bool {
        activationWorkPolicy.shouldRunFullActivation(
            hasPendingStartupActions: hasPendingStartupActions
        )
    }

    private func scheduleDeferredFullActivationWork() {
        deferredActivationWorkTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let delayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: Self.chatActivationWorkDelayMilliseconds
        )
        deferredActivationWorkTask = Task(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let startedAt = LatencyProbe.timerStart()
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isChatTabActive else { return }
                guard shouldRunFullActivationWork else { return }

                let hadPendingStartupActions = hasPendingStartupActions
                suppressAutomaticMessageCacheRebuild = true
                checkSessionTimeout()
                checkForPendingPlanReview()
                if !hadPendingStartupActions {
                    scheduleDeferredPlanRecommendationIfNeeded()
                }
                scheduleStartupHydration()
                activationWorkPolicy.markFullActivationRun()
                recordChatLatencyProbe(
                    "fullActivationWork",
                    startedAt: startedAt,
                    counts: [
                        "allMessages": allMessages.count,
                        "sessionMessages": currentSessionMessages.count,
                        "hadPendingStartup": hadPendingStartupActions ? 1 : 0
                    ]
                )
            }
        }
    }

    private func refreshSmartStarterCache() {
        let interval = PerformanceTrace.begin("chat_smart_starter_cache_refresh", category: .dataLoad)
        let startedAt = LatencyProbe.timerStart()
        defer { PerformanceTrace.end("chat_smart_starter_cache_refresh", interval, category: .dataLoad) }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayEntries = allFoodEntries.filter { $0.loggedAt >= startOfDay }
        smartStarterTodayFoodCount = todayEntries.count
        smartStarterTodayCalories = todayEntries.reduce(0) { $0 + $1.calories }
        smartStarterTodayProtein = todayEntries.reduce(0) { $0 + Int($1.proteinGrams) }
        smartStarterLastWorkoutDate = liveWorkouts.first?.startedAt ?? recentWorkouts.first?.loggedAt
        recordChatLatencyProbe(
            "refreshSmartStarterCache",
            startedAt: startedAt,
            counts: [
                "allFood": allFoodEntries.count,
                "todayFood": smartStarterTodayFoodCount,
                "recentWorkouts": recentWorkouts.count,
                "liveWorkouts": liveWorkouts.count
            ]
        )
    }

    private func handleSelectedPhotoItem(_ newValue: PhotosPickerItem?) {
        Task {
            if let data = try? await newValue?.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                selectedImage = uiImage
            }
        }
    }
}

private struct ChatScrollContainer: View {
    let content: AnyView
    let inputBar: AnyView
    @Binding var isInputFocused: Bool
    let messageCount: Int
    let lastMessageId: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: messageCount) { _, _ in
                if let lastMessageId {
                    withAnimation {
                        proxy.scrollTo(lastMessageId, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
        }
    }
}

private struct ChatRootView: View {
    let content: AnyView
    let inputBar: AnyView
    @Binding var isInputFocused: Bool
    let messageCount: Int
    let lastMessageId: UUID?
    let selectedPhotoItem: PhotosPickerItem?
    let onPhotoSelected: (PhotosPickerItem?) -> Void
    let onAppear: () -> Void
    let onSessionIdChange: () -> Void
    let onTemporaryChange: () -> Void
    let onTemporaryMessagesChange: () -> Void
    let onAllMessagesChange: () -> Void
    let currentSessionIdString: String
    let isTemporarySession: Bool
    let temporaryMessagesCount: Int
    let allMessagesFingerprint: String
    let chatSessions: [(id: UUID, firstMessage: String, date: Date)]
    let onToggleTemporaryMode: () -> Void
    let onSelectSession: (UUID) -> Void
    let onClearHistory: () -> Void
    let onNewChat: () -> Void
    @Binding var showingCamera: Bool
    let onCameraImage: (UIImage) -> Void
    @Binding var enlargedImage: UIImage?
    @Binding var editingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)?
    let enabledMacrosValue: Set<MacroType>
    let onAcceptMeal: (SuggestedFoodEntry, ChatMessage) -> Void
    @Binding var editingPlanSuggestion: (message: ChatMessage, plan: PlanUpdateSuggestionEntry)?
    let currentCalories: Int
    let currentProtein: Int
    let currentCarbs: Int
    let currentFat: Int
    let onAcceptPlan: (PlanUpdateSuggestionEntry, ChatMessage) -> Void
    let viewingFoodEntry: FoodEntry?
    @Binding var viewingLoggedMealId: UUID?
    @Binding var viewingAppliedPlan: PlanUpdateSuggestionEntry?

    var body: some View {
        ChatScrollContainer(
            content: content,
            inputBar: inputBar,
            isInputFocused: $isInputFocused,
            messageCount: messageCount,
            lastMessageId: lastMessageId
        )
        .navigationTitle("Trai")
        .onChange(of: selectedPhotoItem) { _, newValue in
            onPhotoSelected(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onToggleTemporaryMode()
                } label: {
                    Image(systemName: isTemporarySession ? "text.bubble.badge.clock.fill" : "text.bubble.badge.clock")
                        .foregroundStyle(isTemporarySession ? .orange : .secondary)
                }
                .help(isTemporarySession ? "Exit incognito mode" : "Start incognito chat")
            }
            ToolbarItem(placement: .primaryAction) {
                ChatHistoryMenu(
                    sessions: chatSessions,
                    onSelectSession: onSelectSession,
                    onClearHistory: onClearHistory,
                    onNewChat: { onNewChat() }
                )
            }
        }
        .onAppear(perform: onAppear)
        .onChange(of: currentSessionIdString) { _, _ in
            onSessionIdChange()
        }
        .onChange(of: isTemporarySession) { _, _ in
            onTemporaryChange()
        }
        .onChange(of: temporaryMessagesCount) { _, _ in
            onTemporaryMessagesChange()
        }
        .onChange(of: allMessagesFingerprint) { _, _ in
            onAllMessagesChange()
        }
        .chatCameraSheet(showingCamera: $showingCamera) { image in
            onCameraImage(image)
        }
        .chatImagePreviewSheet(enlargedImage: $enlargedImage)
        .chatEditMealSheet(
            editingMeal: $editingMealSuggestion,
            enabledMacros: enabledMacrosValue
        ) { meal, message in
            onAcceptMeal(meal, message)
        }
        .chatEditPlanSheet(
            editingPlan: $editingPlanSuggestion,
            currentCalories: currentCalories,
            currentProtein: currentProtein,
            currentCarbs: currentCarbs,
            currentFat: currentFat,
            enabledMacros: enabledMacrosValue
        ) { plan, message in
            onAcceptPlan(plan, message)
        }
        .chatViewFoodEntrySheet(viewingEntry: viewingFoodEntry, viewingLoggedMealId: $viewingLoggedMealId)
        .sheet(item: $viewingAppliedPlan) { plan in
            PlanUpdateDetailSheet(plan: plan)
        }
    }
}

private struct ChatContentSection: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let isStreamingResponse: Bool
    let isTemporarySession: Bool
    let smartStarterContext: SmartStarterContext
    let currentActivity: String?
    let currentCalories: Int?
    let currentProtein: Int?
    let currentCarbs: Int?
    let currentFat: Int?
    let enabledMacros: Set<MacroType>
    let planRecommendation: PlanRecommendation?
    let planRecommendationMessage: String?
    let onAcceptMeal: (SuggestedFoodEntry, ChatMessage) -> Void
    let isMealLogging: (SuggestedFoodEntry, ChatMessage) -> Bool
    let onEditMeal: (ChatMessage, SuggestedFoodEntry) -> Void
    let onDismissMeal: (SuggestedFoodEntry, ChatMessage) -> Void
    let onViewLoggedMeal: (UUID) -> Void
    let onAcceptPlan: (PlanUpdateSuggestionEntry, ChatMessage) -> Void
    let onEditPlan: (ChatMessage, PlanUpdateSuggestionEntry) -> Void
    let onDismissPlan: (ChatMessage) -> Void
    let onAcceptFoodEdit: (SuggestedFoodEdit, ChatMessage) -> Void
    let onDismissFoodEdit: (ChatMessage) -> Void
    let onAcceptWorkout: (SuggestedWorkoutEntry, ChatMessage) -> Void
    let onDismissWorkout: (ChatMessage) -> Void
    let onAcceptWorkoutLog: (SuggestedWorkoutLog, ChatMessage) -> Void
    let onDismissWorkoutLog: (ChatMessage) -> Void
    let onAcceptReminder: (SuggestedReminder, ChatMessage) -> Void
    let onEditReminder: (SuggestedReminder, ChatMessage) -> Void
    let onDismissReminder: (ChatMessage) -> Void
    let useExerciseWeightLbs: Bool
    let onRetry: (ChatMessage) -> Void
    let onImageTapped: (UIImage) -> Void
    let onViewAppliedPlan: (PlanUpdateSuggestionEntry) -> Void
    let onReviewPlan: () -> Void
    let onDismissPlanRecommendation: () -> Void

    var body: some View {
        ChatContentList(
            messages: messages,
            isLoading: isLoading,
            isStreamingResponse: isStreamingResponse,
            isTemporarySession: isTemporarySession,
            smartStarterContext: smartStarterContext,
            currentActivity: currentActivity,
            currentCalories: currentCalories,
            currentProtein: currentProtein,
            currentCarbs: currentCarbs,
            currentFat: currentFat,
            enabledMacros: enabledMacros,
            planRecommendation: planRecommendation,
            planRecommendationMessage: planRecommendationMessage,
            onAcceptMeal: { meal, message in
                onAcceptMeal(meal, message)
            },
            isMealLogging: { meal, message in
                isMealLogging(meal, message)
            },
            onEditMeal: { message, meal in
                onEditMeal(message, meal)
            },
            onDismissMeal: { meal, message in
                onDismissMeal(meal, message)
            },
            onViewLoggedMeal: { entryId in
                onViewLoggedMeal(entryId)
            },
            onAcceptPlan: { plan, message in
                onAcceptPlan(plan, message)
            },
            onEditPlan: { message, plan in
                onEditPlan(message, plan)
            },
            onDismissPlan: {
                onDismissPlan($0)
            },
            onAcceptFoodEdit: { edit, message in
                onAcceptFoodEdit(edit, message)
            },
            onDismissFoodEdit: {
                onDismissFoodEdit($0)
            },
            onAcceptWorkout: { workout, message in
                onAcceptWorkout(workout, message)
            },
            onDismissWorkout: {
                onDismissWorkout($0)
            },
            onAcceptWorkoutLog: { workoutLog, message in
                onAcceptWorkoutLog(workoutLog, message)
            },
            onDismissWorkoutLog: {
                onDismissWorkoutLog($0)
            },
            onAcceptReminder: { reminder, message in
                onAcceptReminder(reminder, message)
            },
            onEditReminder: { reminder, message in
                onEditReminder(reminder, message)
            },
            onDismissReminder: {
                onDismissReminder($0)
            },
            useExerciseWeightLbs: useExerciseWeightLbs,
            onRetry: {
                onRetry($0)
            },
            onImageTapped: {
                onImageTapped($0)
            },
            onViewAppliedPlan: {
                onViewAppliedPlan($0)
            },
            onReviewPlan: {
                onReviewPlan()
            },
            onDismissPlanRecommendation: {
                onDismissPlanRecommendation()
            }
        )
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [ChatMessage.self, UserProfile.self, FoodEntry.self, WorkoutSession.self], inMemory: true)
}
