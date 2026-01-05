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
    private static var hasStartedFreshSession = false

    @Query(sort: \ChatMessage.timestamp, order: .forward)
    private var allMessages: [ChatMessage]

    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    private var allFoodEntries: [FoodEntry]
    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    private var recentWorkouts: [WorkoutSession]
    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    private var liveWorkouts: [LiveWorkout]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var weightEntries: [WeightEntry]
    @Query(filter: #Predicate<CoachMemory> { $0.isActive }, sort: \CoachMemory.importance, order: .reverse)
    private var activeMemories: [CoachMemory]

    @Environment(\.modelContext) private var modelContext
    @State private var geminiService = GeminiService()
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var enlargedImage: UIImage?
    @State private var editingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)?
    @State private var editingPlanSuggestion: (message: ChatMessage, plan: PlanUpdateSuggestionEntry)?
    @State private var viewingLoggedMealId: UUID?
    @FocusState private var isInputFocused: Bool
    @AppStorage("currentChatSessionId") private var currentSessionIdString: String = ""
    @AppStorage("lastChatActivityDate") private var lastActivityTimestamp: Double = 0

    private let sessionTimeoutHours: Double = 1.5

    private var profile: UserProfile? { profiles.first }

    private var currentSessionId: UUID {
        if let uuid = UUID(uuidString: currentSessionIdString) {
            return uuid
        }
        let newId = UUID()
        currentSessionIdString = newId.uuidString
        return newId
    }

    private var currentSessionMessages: [ChatMessage] {
        allMessages.filter { $0.sessionId == currentSessionId }
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
        // Only consider it "streaming" if the AI message already has content
        return !lastMessage.isFromUser && isLoading && !lastMessage.content.isEmpty
    }

    private var todaysFoodEntries: [FoodEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allFoodEntries.filter { $0.loggedAt >= startOfDay }
    }

    private var pendingMealSuggestion: (message: ChatMessage, meal: SuggestedFoodEntry)? {
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

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    ChatContentList(
                        messages: currentSessionMessages,
                        isLoading: isLoading,
                        isStreamingResponse: isStreamingResponse,
                        currentCalories: profile?.dailyCalorieGoal,
                        currentProtein: profile?.dailyProteinGoal,
                        currentCarbs: profile?.dailyCarbsGoal,
                        currentFat: profile?.dailyFatGoal,
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
                        onDismissPlan: dismissPlanSuggestion
                    )
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
            .chatEditMealSheet(editingMeal: $editingMealSuggestion) { meal, message in
                acceptMealSuggestion(meal, for: message)
            }
            .chatEditPlanSheet(
                editingPlan: $editingPlanSuggestion,
                currentCalories: profile?.dailyCalorieGoal ?? 2000,
                currentProtein: profile?.dailyProteinGoal ?? 150,
                currentCarbs: profile?.dailyCarbsGoal ?? 200,
                currentFat: profile?.dailyFatGoal ?? 65
            ) { plan, message in
                acceptPlanSuggestion(plan, for: message)
            }
            .chatViewFoodEntrySheet(viewingEntry: viewingFoodEntry, viewingLoggedMealId: $viewingLoggedMealId)
        }
    }
}

// MARK: - Session Management

extension ChatView {
    private func checkSessionTimeout() {
        // Start fresh chat on every app launch
        if !ChatView.hasStartedFreshSession {
            ChatView.hasStartedFreshSession = true
            startNewSession(silent: true)
            return
        }

        // Also start new session if timed out
        let lastActivity = Date(timeIntervalSince1970: lastActivityTimestamp)
        let hoursSinceLastActivity = Date().timeIntervalSince(lastActivity) / 3600

        if hoursSinceLastActivity > sessionTimeoutHours {
            startNewSession(silent: true)
        }
    }

    private func startNewSession(silent: Bool = false) {
        let newId = UUID()
        currentSessionIdString = newId.uuidString
        lastActivityTimestamp = Date().timeIntervalSince1970
        if !silent {
            HapticManager.lightTap()
        }
    }

    private func switchToSession(_ sessionId: UUID) {
        currentSessionIdString = sessionId.uuidString
        HapticManager.lightTap()
    }

    private func updateLastActivity() {
        lastActivityTimestamp = Date().timeIntervalSince1970
    }

    private func clearAllChats() {
        for message in allMessages {
            modelContext.delete(message)
        }
        startNewSession()
    }
}

// MARK: - Messaging

extension ChatView {
    private func sendMessage(_ text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let hasImage = selectedImage != nil

        guard hasText || hasImage else { return }

        updateLastActivity()

        // Capture conversation history BEFORE inserting new messages
        let previousMessages = Array(currentSessionMessages.suffix(10))

        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        let userMessage = ChatMessage(
            content: text,
            isFromUser: true,
            sessionId: currentSessionId,
            imageData: imageData
        )
        modelContext.insert(userMessage)
        messageText = ""
        let capturedImage = selectedImage
        selectedImage = nil
        selectedPhotoItem = nil

        let aiMessage = ChatMessage(content: "", isFromUser: false, sessionId: currentSessionId)
        let baseContext = buildFitnessContext()
        aiMessage.contextSummary = "Goal: \(baseContext.userGoal), Calories: \(baseContext.todaysCalories)/\(baseContext.dailyCalorieGoal)"
        modelContext.insert(aiMessage)

        Task {
            isLoading = true

            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
                let currentDateTime = dateFormatter.string(from: Date())

                let historyString = previousMessages.suffix(6)
                    .map { ($0.isFromUser ? "User" : "Coach") + ": " + $0.content }
                    .joined(separator: "\n")

                let memoriesContext = activeMemories.formatForPrompt()

                let functionContext = GeminiService.ChatFunctionContext(
                    profile: profile,
                    todaysFoodEntries: todaysFoodEntries,
                    currentDateTime: currentDateTime,
                    conversationHistory: historyString,
                    memoriesContext: memoriesContext
                )

                let result = try await geminiService.chatWithFunctions(
                    message: text,
                    imageData: capturedImage?.jpegData(compressionQuality: 0.8),
                    context: functionContext,
                    conversationHistory: previousMessages,
                    modelContext: modelContext,
                    onTextChunk: { chunk in
                        aiMessage.content = chunk
                    }
                )

                if let foodData = result.suggestedFood {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        aiMessage.setSuggestedMeal(foodData)
                    }
                    HapticManager.lightTap()
                }

                if let planData = result.planUpdate {
                    let suggestion = PlanUpdateSuggestionEntry(
                        calories: planData.calories,
                        proteinGrams: planData.proteinGrams,
                        carbsGrams: planData.carbsGrams,
                        fatGrams: planData.fatGrams,
                        goal: planData.goal,
                        rationale: planData.rationale
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        aiMessage.setSuggestedPlan(suggestion)
                    }
                    HapticManager.lightTap()
                }

                // Capture saved memories
                for memory in result.savedMemories {
                    aiMessage.addSavedMemory(memory)
                }

                if !result.message.isEmpty {
                    aiMessage.content = result.message
                }
            } catch {
                aiMessage.content = ""
                aiMessage.errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func buildFitnessContext() -> FitnessContext {
        let totalCalories = todaysFoodEntries.reduce(0) { $0 + $1.calories }
        let totalProtein = todaysFoodEntries.reduce(0.0) { $0 + $1.proteinGrams }
        let recentWorkoutNames = Array(recentWorkouts.prefix(5).map { $0.displayName })

        return FitnessContext(
            userGoal: profile?.goal.displayName ?? "Maintenance",
            dailyCalorieGoal: profile?.dailyCalorieGoal ?? 2000,
            dailyProteinGoal: profile?.dailyProteinGoal ?? 150,
            todaysCalories: totalCalories,
            todaysProtein: totalProtein,
            recentWorkouts: recentWorkoutNames,
            currentWeight: profile?.currentWeightKg,
            targetWeight: profile?.targetWeightKg
        )
    }
}

// MARK: - Meal Suggestion Actions

extension ChatView {
    private func acceptMealSuggestion(_ meal: SuggestedFoodEntry, for message: ChatMessage) {
        let messageIndex = currentSessionMessages.firstIndex(where: { $0.id == message.id }) ?? 0
        let userMessage = messageIndex > 0 ? currentSessionMessages[messageIndex - 1] : nil
        let imageData = userMessage?.imageData

        let entry = FoodEntry()
        entry.name = meal.name
        entry.calories = meal.calories
        entry.proteinGrams = meal.proteinGrams
        entry.carbsGrams = meal.carbsGrams
        entry.fatGrams = meal.fatGrams
        entry.servingSize = meal.servingSize
        entry.emoji = meal.emoji
        entry.imageData = imageData
        entry.inputMethod = "chat"

        if let loggedAt = meal.loggedAtDate {
            entry.loggedAt = loggedAt
        }

        modelContext.insert(entry)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.loggedFoodEntryId = entry.id
        }

        HapticManager.success()
    }

    private func dismissMealSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedMealDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Plan Suggestion Actions

extension ChatView {
    private func acceptPlanSuggestion(_ plan: PlanUpdateSuggestionEntry, for message: ChatMessage) {
        guard let profile else { return }

        // Apply changes to profile
        if let calories = plan.calories {
            profile.dailyCalorieGoal = calories
        }
        if let protein = plan.proteinGrams {
            profile.dailyProteinGoal = protein
        }
        if let carbs = plan.carbsGrams {
            profile.dailyCarbsGoal = carbs
        }
        if let fat = plan.fatGrams {
            profile.dailyFatGoal = fat
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.planUpdateApplied = true
        }

        HapticManager.success()
    }

    private func dismissPlanSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedPlanDismissed = true
        }
        HapticManager.lightTap()
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [ChatMessage.self, UserProfile.self, FoodEntry.self, WorkoutSession.self], inMemory: true)
}
