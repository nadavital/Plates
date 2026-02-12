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

    /// Optional workout context for mid-workout chat
    var workoutContext: GeminiService.WorkoutContext?

    @Query(sort: \ChatMessage.timestamp, order: .forward)
    var allMessages: [ChatMessage]

    @Query var profiles: [UserProfile]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    var allFoodEntries: [FoodEntry]
    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    var recentWorkouts: [WorkoutSession]
    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    var liveWorkouts: [LiveWorkout]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    var weightEntries: [WeightEntry]
    @Query(filter: #Predicate<CoachMemory> { $0.isActive }, sort: \CoachMemory.importance, order: .reverse)
    var activeMemories: [CoachMemory]
    @Query(filter: #Predicate<CoachSignal> { !$0.isResolved }, sort: \CoachSignal.createdAt, order: .reverse)
    var activeSignals: [CoachSignal]
    @Query var suggestionUsage: [SuggestionUsage]

    @Environment(\.modelContext) var modelContext
    @Environment(HealthKitService.self) var healthKitService: HealthKitService?
    @State var geminiService = GeminiService()
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
    @AppStorage("pendingPulseSeedPrompt") var pendingPulseSeedPrompt: String = ""
    @AppStorage(TraiCoachTone.storageKey) var coachToneRaw: String = TraiCoachTone.encouraging.rawValue
    @State var pulseHandoffContext: String = ""
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
            if message.hasPendingMealSuggestion, let meal = message.suggestedMeal {
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
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let todayEntries = allFoodEntries.filter { $0.loggedAt >= startOfDay }
        let todayCalories = todayEntries.reduce(0) { $0 + $1.calories }
        let todayProtein = todayEntries.reduce(0) { $0 + Int($1.proteinGrams) }
        let lastWorkout = liveWorkouts.first?.startedAt ?? recentWorkouts.first?.loggedAt

        return SmartStarterContext(
            userName: profile?.name ?? "",
            todayFoodCount: todayEntries.count,
            todayCalories: todayCalories,
            calorieGoal: profile?.dailyCalorieGoal ?? 2000,
            todayProtein: todayProtein,
            proteinGoal: profile?.dailyProteinGoal ?? 150,
            lastWorkoutDate: lastWorkout,
            hasActiveWorkout: workoutContext != nil,
            goalType: profile?.goal.rawValue ?? "maintenance"
        )
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
                    rebuildMessageCaches()
                    checkSessionTimeout()
                    checkForPlanRecommendation()
                    checkForPendingPlanReview()
                    checkForPendingPulsePrompt()
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
                    rebuildMessageCaches()
                },
                currentSessionIdString: currentSessionIdString,
                isTemporarySession: isTemporarySession,
                temporaryMessagesCount: temporaryMessages.count,
                allMessagesCount: allMessages.count,
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

    private func rebuildMessageCaches() {
        rebuildSessionMessages()

        var sessions: [UUID: (firstMessage: String, date: Date)] = [:]
        for message in allMessages {
            guard let sessionId = message.sessionId else { continue }
            if sessions[sessionId] == nil {
                sessions[sessionId] = (message.content, message.timestamp)
            }
        }

        cachedChatSessions = sessions
            .map { (id: $0.key, firstMessage: $0.value.firstMessage, date: $0.value.date) }
            .sorted { $0.date > $1.date }
    }

    private func rebuildSessionMessages() {
        if isTemporarySession {
            cachedSessionMessages = temporaryMessages.sorted { $0.timestamp < $1.timestamp }
        } else {
            cachedSessionMessages = allMessages.filter { $0.sessionId == currentSessionId }
        }
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
    let allMessagesCount: Int
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
        .onChange(of: allMessagesCount) { _, _ in
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
