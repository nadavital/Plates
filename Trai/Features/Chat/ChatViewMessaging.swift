//
//  ChatViewMessaging.swift
//  Trai
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
        pulseHandoffContext = ""
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
        pulseHandoffContext = ""
    }

    func switchToSession(_ sessionId: UUID) {
        currentSessionIdString = sessionId.uuidString
        isTemporarySession = false
        temporaryMessages = []
        pulseHandoffContext = ""
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
    func startPulseConversation(from handoffPrompt: String) {
        let trimmedPrompt = handoffPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        updateLastActivity()
        pulseHandoffContext = trimmedPrompt

        let previousMessages = Array(currentSessionMessages.suffix(10))
        let aiMessage = ChatMessage(content: "", isFromUser: false, sessionId: currentSessionId)
        let baseContext = buildFitnessContext()
        aiMessage.contextSummary = "Goal: \(baseContext.userGoal), Calories: \(baseContext.todaysCalories)/\(baseContext.dailyCalorieGoal)"

        if isTemporarySession {
            temporaryMessages.append(aiMessage)
        } else {
            modelContext.insert(aiMessage)
        }

        currentMessageTask = Task {
            await performSendMessage(
                text: "Open with a concise Pulse check-in and clear next step based on the dashboard handoff context.",
                capturedImage: nil,
                previousMessages: previousMessages,
                aiMessage: aiMessage
            )
        }
    }

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
        case "log_weight":
            return "Logging weight..."
        case "get_activity_summary":
            return "Getting activity..."
        case "save_memory":
            return "Remembering..."
        case "delete_memory":
            return "Updating memory..."
        case "save_short_term_context":
            return "Saving context..."
        case "clear_short_term_context":
            return "Clearing context..."
        case "create_reminder":
            return "Creating reminder..."
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

        let capturedImage = selectedImage
        selectedImage = nil
        selectedPhotoItem = nil

        currentMessageTask = Task {
            await performSendMessage(
                text: text,
                capturedImage: capturedImage,
                previousMessages: previousMessages,
                aiMessage: aiMessage
            )
        }
    }

    func stopGenerating() {
        currentMessageTask?.cancel()
        currentMessageTask = nil
        isLoading = false
        currentActivity = nil
        HapticManager.lightTap()
    }

    func performSendMessage(
        text: String,
        capturedImage: UIImage?,
        previousMessages: [ChatMessage],
        aiMessage: ChatMessage
    ) async {
        isLoading = true
        var latestStreamedText = ""
        var lastStreamRenderAt = Date.distantPast

        do {
            let handoffContext = pulseHandoffContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !handoffContext.isEmpty {
                pulseHandoffContext = ""
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            let currentDateTime = dateFormatter.string(from: Date())

            let historyString = previousMessages.suffix(6)
                .map { ($0.isFromUser ? "User" : "Coach") + ": " + $0.content }
                .joined(separator: "\n")

            // Filter memories by relevance to current message (reduces prompt size, improves relevance)
            let relevantMemories = activeMemories.filterForRelevance(message: text, maxCount: 10)
            let memoriesContext = relevantMemories.formatForPrompt()
            var pulseContext = buildCompactPulseContext(now: Date())
            if !handoffContext.isEmpty {
                pulseContext += "\n[Dashboard handoff context]: \(handoffContext)"
            }

            // Fetch activity data from HealthKit
            let activityData = await fetchActivityData()

            let functionContext = GeminiService.ChatFunctionContext(
                profile: profile,
                todaysFoodEntries: todaysFoodEntries,
                currentDateTime: currentDateTime,
                conversationHistory: historyString,
                coachTone: coachTone,
                memoriesContext: memoriesContext,
                pulseContext: pulseContext,
                pendingSuggestion: pendingMealSuggestion?.meal,
                isIncognitoMode: isTemporarySession,
                activeWorkout: workoutContext,
                activityData: activityData
            )

            let result = try await geminiService.chatWithFunctions(
                message: text,
                imageData: capturedImage?.jpegData(compressionQuality: 0.8),
                context: functionContext,
                conversationHistory: previousMessages,
                modelContext: modelContext,
                onTextChunk: { chunk in
                    latestStreamedText = chunk
                    let now = Date()
                    if now.timeIntervalSince(lastStreamRenderAt) >= 0.05 {
                        lastStreamRenderAt = now
                        Task { @MainActor in
                            aiMessage.content = latestStreamedText
                        }
                    }
                },
                onFunctionCall: { functionName in
                    currentActivity = friendlyFunctionName(functionName)
                }
            )

            if !latestStreamedText.isEmpty {
                aiMessage.content = latestStreamedText
            }
            handleChatResult(result, aiMessage: aiMessage)
        } catch is CancellationError {
            // User cancelled - don't show error, keep partial content
            aiMessage.wasManuallyStopped = true
        } catch {
            aiMessage.content = ""
            aiMessage.errorMessage = error.localizedDescription
        }

        isLoading = false
        currentActivity = nil
        currentMessageTask = nil
    }

    func handleChatResult(_ result: GeminiService.ChatFunctionResult, aiMessage: ChatMessage) {
        if !result.suggestedFoods.isEmpty {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedMeals(result.suggestedFoods)
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

        if let reminderData = result.suggestedReminder {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedReminder(reminderData)
            }
            HapticManager.lightTap()
        }

        for memory in result.savedMemories {
            aiMessage.addSavedMemory(memory)
        }

        if !result.message.isEmpty {
            aiMessage.content = result.message
        }

        // Explicit save to ensure SwiftData persists changes after function calls
        try? modelContext.save()
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

    private func buildCompactPulseContext(now: Date) -> String {
        let patternProfile = TraiPulsePatternService.buildProfile(
            now: now,
            foodEntries: allFoodEntries,
            workouts: recentWorkouts,
            liveWorkouts: liveWorkouts,
            suggestionUsage: suggestionUsage,
            profile: profile
        )
        let trend = TraiPulsePatternService.buildTrendSnapshot(
            now: now,
            foodEntries: allFoodEntries,
            workouts: recentWorkouts,
            liveWorkouts: liveWorkouts,
            profile: profile
        )

        let activeSnapshots = activeSignals.activeSnapshots(now: now)
        let hasWorkoutToday = hasWorkoutLoggedToday(now: now)
        let hasActiveWorkout = workoutContext != nil || liveWorkouts.contains(where: { $0.completedAt == nil })

        let calorieGoal = profile?.effectiveCalorieGoal(hasWorkoutToday: hasWorkoutToday || hasActiveWorkout)
            ?? profile?.dailyCalorieGoal
            ?? 2000
        let proteinGoal = profile?.dailyProteinGoal ?? 150
        let readyMuscleCount = MuscleRecoveryService()
            .getRecoveryStatus(modelContext: modelContext)
            .filter { $0.status == .ready }
            .count
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let daysSinceLastWeightLog: Int?
        if let latestWeight = weightEntries.first {
            let latestDay = calendar.startOfDay(for: latestWeight.loggedAt)
            let delta = calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0
            daysSinceLastWeightLog = max(delta, 0)
        } else {
            daysSinceLastWeightLog = nil
        }
        let weightLoggedThisWeek: Bool
        if let weekStart = calendar.date(byAdding: .day, value: -6, to: today) {
            weightLoggedThisWeek = weightEntries.contains { $0.loggedAt >= weekStart }
        } else {
            weightLoggedThisWeek = false
        }
        let todaysExerciseMinutes = recentWorkouts
            .filter { $0.loggedAt >= today && $0.loggedAt < endOfDay }
            .reduce(0) { total, session in
                total + Int(session.durationMinutes ?? 0)
            }
        let lastActiveWorkoutHour: Int? = {
            let candidates = recentWorkouts
                .filter { $0.loggedAt >= today && $0.loggedAt < endOfDay }
                .map(\.loggedAt) + liveWorkouts.compactMap { $0.completedAt ?? $0.startedAt }
                .filter { $0 >= today && $0 < endOfDay }
            guard let latest = candidates.max() else { return nil }
            return calendar.component(.hour, from: latest)
        }()

        let preferredWindow = patternProfile.strongestWorkoutWindow(minScore: 0.38)?.hourRange ?? (9, 21)
        let context = TraiPulseInputContext(
            now: now,
            hasWorkoutToday: hasWorkoutToday,
            hasActiveWorkout: hasActiveWorkout,
            caloriesConsumed: todaysFoodEntries.reduce(0) { $0 + $1.calories },
            calorieGoal: calorieGoal,
            proteinConsumed: Int(todaysFoodEntries.reduce(0.0) { $0 + $1.proteinGrams }.rounded()),
            proteinGoal: proteinGoal,
            readyMuscleCount: readyMuscleCount,
            recommendedWorkoutName: nil,
            workoutWindowStartHour: preferredWindow.0,
            workoutWindowEndHour: preferredWindow.1,
            activeSignals: activeSnapshots,
            tomorrowWorkoutMinutes: 40,
            trend: trend,
            patternProfile: patternProfile,
            reminderCompletionRate: nil,
            recentMissedReminderCount: nil,
            daysSinceLastWeightLog: daysSinceLastWeightLog,
            weightLoggedThisWeek: weightLoggedThisWeek,
            todaysExerciseMinutes: todaysExerciseMinutes,
            lastActiveWorkoutHour: lastActiveWorkoutHour,
            likelyReminderTimes: [],
            contextPacket: nil
        )

        let packet = TraiPulseContextAssembler.assemble(
            patternProfile: patternProfile,
            activeSignals: activeSnapshots,
            context: context,
            tokenBudget: 650
        )
        return packet.promptSummary
    }

    private func hasWorkoutLoggedToday(now: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return false
        }

        let hasLoggedSession = recentWorkouts.contains { workout in
            workout.loggedAt >= startOfDay && workout.loggedAt < endOfDay
        }
        let hasLiveWorkout = liveWorkouts.contains { workout in
            workout.startedAt >= startOfDay && workout.startedAt < endOfDay
        }

        return hasLoggedSession || hasLiveWorkout
    }

    private func fetchActivityData() async -> GeminiService.ActivityData {
        guard let healthKitService else {
            return .empty
        }

        do {
            async let steps = healthKitService.fetchTodayStepCount()
            async let calories = healthKitService.fetchTodayActiveEnergy()
            async let exercise = healthKitService.fetchTodayExerciseMinutes()

            let (fetchedSteps, fetchedCalories, fetchedExercise) = try await (steps, calories, exercise)
            return GeminiService.ActivityData(
                steps: fetchedSteps,
                activeCalories: fetchedCalories,
                exerciseMinutes: fetchedExercise
            )
        } catch {
            // Return empty data if HealthKit fails
            return .empty
        }
    }
}
