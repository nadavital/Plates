//
//  ChatViewMessaging.swift
//  Plates
//
//  Chat view messaging and session management
//

import SwiftUI
import SwiftData

// MARK: - Session Management

extension ChatView {
    func checkSessionTimeout() {
        if !ChatView.hasStartedFreshSession {
            ChatView.hasStartedFreshSession = true
            startNewSession(silent: true)
            return
        }

        let lastActivity = Date(timeIntervalSince1970: lastActivityTimestamp)
        let hoursSinceLastActivity = Date().timeIntervalSince(lastActivity) / 3600

        if hoursSinceLastActivity > sessionTimeoutHours {
            startNewSession(silent: true)
        }
    }

    func startNewSession(silent: Bool = false) {
        let newId = UUID()
        currentSessionIdString = newId.uuidString
        lastActivityTimestamp = Date().timeIntervalSince1970
        isTemporarySession = false
        temporaryMessages = []
        if !silent {
            HapticManager.lightTap()
        }
    }

    func toggleTemporaryMode() {
        if isTemporarySession {
            temporaryMessages = []
            isTemporarySession = false
        } else {
            temporaryMessages = []
            isTemporarySession = true
        }
    }

    func switchToSession(_ sessionId: UUID) {
        currentSessionIdString = sessionId.uuidString
        isTemporarySession = false
        temporaryMessages = []
        HapticManager.lightTap()
    }

    func updateLastActivity() {
        lastActivityTimestamp = Date().timeIntervalSince1970
    }

    func clearAllChats() {
        for message in allMessages {
            modelContext.delete(message)
        }
        startNewSession()
    }
}

// MARK: - Messaging

extension ChatView {
    func friendlyFunctionName(_ name: String) -> String {
        switch name {
        case "suggest_food_log":
            return "Analyzing food..."
        case "edit_food_entry":
            return "Preparing edit..."
        case "get_food_log", "get_todays_food_log":
            return "Getting food log..."
        case "get_user_plan":
            return "Checking your plan..."
        case "update_user_plan":
            return "Updating plan..."
        case "get_recent_workouts":
            return "Getting workouts..."
        case "log_workout":
            return "Logging workout..."
        case "get_muscle_recovery_status":
            return "Checking muscle recovery..."
        case "suggest_workout":
            return "Planning workout..."
        case "start_live_workout":
            return "Starting workout..."
        case "get_weight_history":
            return "Getting weight history..."
        case "save_memory":
            return "Remembering..."
        case "delete_memory":
            return "Updating memory..."
        default:
            return "Working..."
        }
    }

    func sendMessage(_ text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let hasImage = selectedImage != nil

        guard hasText || hasImage else { return }

        updateLastActivity()

        let previousMessages = Array(currentSessionMessages.suffix(10))
        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)

        let userMessage = ChatMessage(
            content: text,
            isFromUser: true,
            sessionId: currentSessionId,
            imageData: imageData
        )

        let aiMessage = ChatMessage(content: "", isFromUser: false, sessionId: currentSessionId)
        let baseContext = buildFitnessContext()
        aiMessage.contextSummary = "Goal: \(baseContext.userGoal), Calories: \(baseContext.todaysCalories)/\(baseContext.dailyCalorieGoal)"

        if isTemporarySession {
            temporaryMessages.append(userMessage)
            temporaryMessages.append(aiMessage)
        } else {
            modelContext.insert(userMessage)
            modelContext.insert(aiMessage)
        }

        messageText = ""
        let capturedImage = selectedImage
        selectedImage = nil
        selectedPhotoItem = nil

        Task {
            await performSendMessage(
                text: text,
                capturedImage: capturedImage,
                previousMessages: previousMessages,
                aiMessage: aiMessage
            )
        }
    }

    func performSendMessage(
        text: String,
        capturedImage: UIImage?,
        previousMessages: [ChatMessage],
        aiMessage: ChatMessage
    ) async {
        isLoading = true

        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
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
                memoriesContext: memoriesContext,
                pendingSuggestion: pendingMealSuggestion?.meal,
                isIncognitoMode: isTemporarySession,
                activeWorkout: workoutContext
            )

            let result = try await geminiService.chatWithFunctions(
                message: text,
                imageData: capturedImage?.jpegData(compressionQuality: 0.8),
                context: functionContext,
                conversationHistory: previousMessages,
                modelContext: modelContext,
                onTextChunk: { chunk in
                    aiMessage.content = chunk
                },
                onFunctionCall: { functionName in
                    currentActivity = friendlyFunctionName(functionName)
                }
            )

            handleChatResult(result, aiMessage: aiMessage)
        } catch {
            aiMessage.content = ""
            aiMessage.errorMessage = error.localizedDescription
        }

        isLoading = false
        currentActivity = nil
    }

    func handleChatResult(_ result: GeminiService.ChatFunctionResult, aiMessage: ChatMessage) {
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

        if let editData = result.suggestedFoodEdit {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedFoodEdit(editData)
            }
            HapticManager.lightTap()
        }

        if let workoutData = result.suggestedWorkout {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedWorkout(workoutData)
            }
            HapticManager.lightTap()
        }

        if let workoutLogData = result.suggestedWorkoutLog {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedWorkoutLog(workoutLogData)
            }
            HapticManager.lightTap()
        }

        for memory in result.savedMemories {
            aiMessage.addSavedMemory(memory)
        }

        if !result.message.isEmpty {
            aiMessage.content = result.message
        }
    }

    func buildFitnessContext() -> FitnessContext {
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

    func retryMessage(_ aiMessage: ChatMessage) {
        guard let messageIndex = currentSessionMessages.firstIndex(where: { $0.id == aiMessage.id }),
              messageIndex > 0 else { return }

        let userMessage = currentSessionMessages[messageIndex - 1]
        guard userMessage.isFromUser else { return }

        aiMessage.errorMessage = nil
        aiMessage.content = ""

        let capturedImage = userMessage.imageData.flatMap { UIImage(data: $0) }
        let text = userMessage.content
        let previousMessages = Array(currentSessionMessages.prefix(messageIndex - 1).suffix(10))

        Task {
            await performSendMessage(
                text: text,
                capturedImage: capturedImage,
                previousMessages: previousMessages,
                aiMessage: aiMessage
            )
        }
    }
}
