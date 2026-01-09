//
//  ChatView.swift
//  Plates
//
//  Main chat view with AI fitness coach
//  Components: ChatMessageViews.swift, ChatMealComponents.swift,
//              ChatInputBar.swift, ChatCameraComponents.swift
//

import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
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

    @Environment(\.modelContext) var modelContext
    @State var geminiService = GeminiService()
    @State var messageText = ""
    @State var isLoading = false
    @State var currentActivity: String?
    @State var selectedImage: UIImage?
    @State var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var enlargedImage: UIImage?
    @State private var editingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)?
    @State private var editingPlanSuggestion: (message: ChatMessage, plan: PlanUpdateSuggestionEntry)?
    @State private var viewingLoggedMealId: UUID?
    @FocusState private var isInputFocused: Bool
    @AppStorage("currentChatSessionId") var currentSessionIdString: String = ""
    @AppStorage("lastChatActivityDate") var lastActivityTimestamp: Double = 0
    @State var isTemporarySession = false
    @State var temporaryMessages: [ChatMessage] = []

    let sessionTimeoutHours: Double = 1.5

    var profile: UserProfile? { profiles.first }

    var currentSessionId: UUID {
        if let uuid = UUID(uuidString: currentSessionIdString) {
            return uuid
        }
        let newId = UUID()
        currentSessionIdString = newId.uuidString
        return newId
    }

    var currentSessionMessages: [ChatMessage] {
        if isTemporarySession {
            return temporaryMessages.sorted { $0.timestamp < $1.timestamp }
        }
        return allMessages.filter { $0.sessionId == currentSessionId }
    }

    private var chatSessions: [(id: UUID, firstMessage: String, date: Date)] {
        var sessions: [UUID: (firstMessage: String, date: Date)] = [:]

        for message in allMessages {
            guard let sessionId = message.sessionId else { continue }
            if sessions[sessionId] == nil {
                sessions[sessionId] = (message.content, message.timestamp)
            }
        }

        return sessions
            .map { (id: $0.key, firstMessage: $0.value.firstMessage, date: $0.value.date) }
            .sorted { $0.date > $1.date }
    }

    private var isStreamingResponse: Bool {
        guard let lastMessage = currentSessionMessages.last else { return false }
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

    private var chatContentList: some View {
        ChatContentList(
            messages: currentSessionMessages,
            isLoading: isLoading,
            isStreamingResponse: isStreamingResponse,
            isTemporarySession: isTemporarySession,
            currentActivity: currentActivity,
            currentCalories: profile?.dailyCalorieGoal,
            currentProtein: profile?.dailyProteinGoal,
            currentCarbs: profile?.dailyCarbsGoal,
            currentFat: profile?.dailyFatGoal,
            enabledMacros: enabledMacrosValue,
            onSuggestionTapped: sendMessage,
            onAcceptMeal: acceptMealSuggestion,
            onEditMeal: { message, meal in
                editingMealSuggestion = (message, meal)
            },
            onDismissMeal: dismissMealSuggestion,
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
            useExerciseWeightLbs: !(profile?.usesMetricExerciseWeight ?? true),
            onRetry: retryMessage
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    chatContentList
                }
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: currentSessionMessages.count) { _, _ in
                    if let lastMessage = currentSessionMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(
                        text: $messageText,
                        selectedImage: $selectedImage,
                        selectedPhotoItem: $selectedPhotoItem,
                        isLoading: isLoading,
                        onSend: { sendMessage(messageText) },
                        onTakePhoto: { showingCamera = true },
                        onImageTapped: { image in enlargedImage = image },
                        isFocused: $isInputFocused
                    )
                }
            }
            .navigationTitle("Trai")
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            toggleTemporaryMode()
                        }
                        HapticManager.lightTap()
                    } label: {
                        Image(systemName: isTemporarySession ? "text.bubble.badge.clock.fill" : "text.bubble.badge.clock")
                            .foregroundStyle(isTemporarySession ? .orange : .secondary)
                    }
                    .help(isTemporarySession ? "Exit incognito mode" : "Start incognito chat")
                }
                ToolbarItem(placement: .principal) {
                    if isTemporarySession {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble.badge.clock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Incognito")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: .capsule)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ChatHistoryMenu(
                        sessions: chatSessions,
                        onSelectSession: switchToSession,
                        onClearHistory: clearAllChats,
                        onNewChat: { startNewSession() }
                    )
                }
            }
            .onAppear {
                checkSessionTimeout()
            }
            .chatCameraSheet(showingCamera: $showingCamera) { image in
                selectedImage = image
            }
            .chatImagePreviewSheet(enlargedImage: $enlargedImage)
            .chatEditMealSheet(
                editingMeal: $editingMealSuggestion,
                enabledMacros: enabledMacrosValue
            ) { meal, message in
                acceptMealSuggestion(meal, for: message)
            }
            .chatEditPlanSheet(
                editingPlan: $editingPlanSuggestion,
                currentCalories: profile?.dailyCalorieGoal ?? 2000,
                currentProtein: profile?.dailyProteinGoal ?? 150,
                currentCarbs: profile?.dailyCarbsGoal ?? 200,
                currentFat: profile?.dailyFatGoal ?? 65,
                enabledMacros: enabledMacrosValue
            ) { plan, message in
                acceptPlanSuggestion(plan, for: message)
            }
            .chatViewFoodEntrySheet(viewingEntry: viewingFoodEntry, viewingLoggedMealId: $viewingLoggedMealId)
        }
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [ChatMessage.self, UserProfile.self, FoodEntry.self, WorkoutSession.self], inMemory: true)
}
