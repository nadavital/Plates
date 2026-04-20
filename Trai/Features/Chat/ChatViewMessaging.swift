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
        rebuildSessionMessages(preferLiveQueryData: true)
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
        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = (try? modelContext.fetch(descriptor)) ?? allMessages
        for message in messages {
            message.imageData = nil
            modelContext.delete(message)
        }
        try? modelContext.save()
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
        case "edit_food_components":
            return "Adjusting meal..."
        case "get_food_log", "get_todays_food_log":
            return "Getting food log..."
        case "get_user_plan":
            return "Checking your plan..."
        case "update_user_plan":
            return "Updating plan..."
        case "get_recent_workouts":
            return "Getting workouts..."
        case "get_workout_goals":
            return "Checking workout goals..."
        case "create_workout_goal":
            return "Creating workout goal..."
        case "update_workout_goal":
            return "Updating workout goal..."
        case "update_workout_notes":
            return "Updating workout notes..."
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
        rebuildSessionMessages(preferLiveQueryData: true)

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

    func sendAppInitiatedPrompt(_ text: String, launchLabel: String? = nil) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        updateLastActivity()
        currentActivity = launchLabel ?? "Reviewing with Trai..."

        let previousMessages = Array(currentSessionMessages.suffix(10))
        let aiMessage = ChatMessage(content: "", isFromUser: false, sessionId: currentSessionId)
        let baseContext = buildFitnessContext()
        aiMessage.contextSummary = "Goal: \(baseContext.userGoal), Calories: \(baseContext.todaysCalories)/\(baseContext.dailyCalorieGoal)"

        if isTemporarySession {
            temporaryMessages.append(aiMessage)
        } else {
            modelContext.insert(aiMessage)
        }
        rebuildSessionMessages(preferLiveQueryData: true)

        currentMessageTask = Task {
            await performSendMessage(
                text: trimmedText,
                capturedImage: nil,
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
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            let currentDateTime = dateFormatter.string(from: Date())

            let historyString = previousMessages.suffix(6)
                .map { ($0.isFromUser ? "User" : "Coach") + ": " + $0.content }
                .joined(separator: "\n")

            // Filter memories by relevance to current message (reduces prompt size, improves relevance)
            let relevantMemories = activeMemories.filterForRelevance(message: text, maxCount: 10)
            let memoriesContext = relevantMemories.formatForPrompt()
            let coachContext = buildCompactCoachContext(now: Date())

            // Fetch activity data from HealthKit
            let activityData = await fetchActivityData()

            let functionContext = AIService.ChatFunctionContext(
                profile: profile,
                todaysFoodEntries: todaysFoodEntries,
                currentDateTime: currentDateTime,
                conversationHistory: historyString,
                coachTone: coachTone,
                memoriesContext: memoriesContext,
                coachContext: coachContext,
                pendingSuggestion: pendingMealSuggestion?.meal,
                pendingWorkoutPlanSuggestion: pendingWorkoutPlanSuggestion?.suggestion,
                isIncognitoMode: isTemporarySession,
                activeWorkout: workoutContext,
                activityData: activityData
            )

            let result = try await aiService.chatWithFunctions(
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
        } catch {
            if error.isUserCancelledRequest {
                // User cancelled - don't show an error bubble, just keep whatever streamed so far.
                aiMessage.wasManuallyStopped = true
                aiMessage.errorMessage = nil
                if !latestStreamedText.isEmpty {
                    aiMessage.content = latestStreamedText
                }
            } else {
                aiMessage.content = ""
                aiMessage.errorMessage = error.aiUserFacingMessage ?? error.localizedDescription
            }
        }

        isLoading = false
        currentActivity = nil
        currentMessageTask = nil
    }

    func handleChatResult(_ result: AIService.ChatFunctionResult, aiMessage: ChatMessage) {
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
                fiberGrams: planData.fiberGrams,
                sugarGrams: planData.sugarGrams,
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

        if let componentEditData = result.suggestedFoodComponentEdit {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedFoodComponentEdit(componentEditData)
            }
            HapticManager.lightTap()
        }

        if let workoutPlanData = result.suggestedWorkoutPlan {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                aiMessage.setSuggestedWorkoutPlan(workoutPlanData)
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

    private func buildCompactCoachContext(now: Date) -> String {
        let patternProfile = TraiCoachPatternService.buildProfile(
            now: now,
            foodEntries: allFoodEntries,
            workouts: recentWorkouts,
            liveWorkouts: liveWorkouts,
            suggestionUsage: suggestionUsage,
            behaviorEvents: behaviorEvents,
            profile: profile
        )
        let trend = TraiCoachPatternService.buildTrendSnapshot(
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
        let readyMuscleCount = recoveryService
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
        let recommendedWorkoutName: String? = {
            guard let plan = profile?.workoutPlan else { return nil }
            if let recommendedTemplateId = recoveryService.getRecommendedTemplateId(
                plan: plan,
                modelContext: modelContext
            ) {
                return plan.templates.first(where: { $0.id == recommendedTemplateId })?.name
                    ?? plan.templates.first?.name
            }
            return plan.templates.first?.name
        }()
        let lastActiveWorkoutHour: Int? = {
            let candidates = recentWorkouts
                .filter { $0.loggedAt >= today && $0.loggedAt < endOfDay }
                .map(\.loggedAt) + liveWorkouts.compactMap { $0.completedAt ?? $0.startedAt }
                .filter { $0 >= today && $0 < endOfDay }
            guard let latest = candidates.max() else { return nil }
            return calendar.component(.hour, from: latest)
        }()

        let preferredWindow = patternProfile.strongestWorkoutWindow(minScore: 0.38)?.hourRange ?? (9, 21)
        let context = TraiCoachInputContext(
            now: now,
            hasWorkoutToday: hasWorkoutToday,
            hasActiveWorkout: hasActiveWorkout,
            caloriesConsumed: todaysFoodEntries.reduce(0) { $0 + $1.calories },
            calorieGoal: calorieGoal,
            proteinConsumed: Int(todaysFoodEntries.reduce(0.0) { $0 + $1.proteinGrams }.rounded()),
            proteinGoal: proteinGoal,
            readyMuscleCount: readyMuscleCount,
            recommendedWorkoutName: recommendedWorkoutName,
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

        let packet = TraiCoachContextAssembler.assemble(
            patternProfile: patternProfile,
            activeSignals: activeSnapshots,
            context: context,
            tokenBudget: 650
        )
        let recentWorkoutNotes = buildRecentWorkoutNotesContext(now: now)
        let activeGoalSummary = buildActiveWorkoutGoalsContext()

        var sections: [String] = [packet.promptSummary]
        if !activeGoalSummary.isEmpty {
            sections.append("Active workout goals:\n" + activeGoalSummary)
        }
        if !recentWorkoutNotes.isEmpty {
            sections.append("Recent workout notes:\n" + recentWorkoutNotes)
        }
        return sections.joined(separator: "\n\n")
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

    private func fetchActivityData() async -> AIService.ActivityData {
        guard let healthKitService else {
            return .empty
        }

        do {
            async let steps = healthKitService.fetchTodayStepCount()
            async let calories = healthKitService.fetchTodayActiveEnergy()
            async let exercise = healthKitService.fetchTodayExerciseMinutes()

            let (fetchedSteps, fetchedCalories, fetchedExercise) = try await (steps, calories, exercise)
            return AIService.ActivityData(
                steps: fetchedSteps,
                activeCalories: fetchedCalories,
                exerciseMinutes: fetchedExercise
            )
        } catch {
            // Return empty data if HealthKit fails
            return .empty
        }
    }

    private func buildRecentWorkoutNotesContext(now: Date) -> String {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: now) else { return "" }

        struct WorkoutNoteSignal {
            let date: Date
            let title: String
            let subtitle: String
            let note: String
        }

        let sessionSignals: [WorkoutNoteSignal] = recentWorkouts
            .filter { $0.loggedAt >= cutoff && $0.hasSignalNote }
            .map { workout in
                let subtitle = [workout.displayTypeName, workout.formattedDuration, workout.formattedDistance]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                return WorkoutNoteSignal(
                    date: workout.loggedAt,
                    title: workout.displayName,
                    subtitle: subtitle,
                    note: workout.trimmedNotes
                )
            }

        let liveSignals: [WorkoutNoteSignal] = liveWorkouts
            .filter { ($0.completedAt ?? $0.startedAt) >= cutoff }
            .compactMap { workout in
                let note = workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !note.isEmpty else { return nil }
                let subtitle = [workout.type.displayName, workout.displayFocusSummary, workout.formattedDuration]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                return WorkoutNoteSignal(
                    date: workout.completedAt ?? workout.startedAt,
                    title: workout.name,
                    subtitle: subtitle,
                    note: note
                )
            }

        return (sessionSignals + liveSignals)
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { signal in
                let prefix = signal.subtitle.isEmpty ? signal.title : "\(signal.title) (\(signal.subtitle))"
                return "- \(prefix): \(signal.note)"
            }
            .joined(separator: "\n")
    }

    private func buildActiveWorkoutGoalsContext() -> String {
        activeWorkoutGoals
            .prefix(6)
            .map { goal in
                let parts = [
                    goal.trimmedTitle,
                    goal.scopeSummary,
                    goal.trackingSummary,
                    goal.horizonSummary
                ].compactMap { $0 }
                return "• " + parts.joined(separator: " • ")
            }
            .joined(separator: "\n")
    }
}
