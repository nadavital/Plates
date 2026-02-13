//
//  ChatViewActions.swift
//  Trai
//
//  Chat view action handlers for suggestions
//

import SwiftUI
import SwiftData

// MARK: - Suggestion Tracking

extension ChatView {
    /// Track when a user taps a suggestion to personalize future ordering
    func trackSuggestionTap(_ suggestionType: String) {
        // Find existing usage record or create new one
        if let existing = suggestionUsage.first(where: { $0.suggestionType == suggestionType }) {
            existing.recordTap()
        } else {
            let newUsage = SuggestionUsage(suggestionType: suggestionType)
            newUsage.recordTap()
            modelContext.insert(newUsage)
        }

        // Save immediately to persist the tap
        try? modelContext.save()
    }
}

// MARK: - Meal Suggestion Actions

extension ChatView {
    func acceptMealSuggestion(_ meal: SuggestedFoodEntry, for message: ChatMessage) {
        let mealKey = mealSuggestionKey(for: meal, in: message)
        guard !processingMealSuggestionKeys.contains(mealKey) else {
            return
        }
        processingMealSuggestionKeys.insert(mealKey)

        let messageIndex = currentSessionMessages.firstIndex(where: { $0.id == message.id }) ?? 0
        let userMessage = messageIndex > 0 ? currentSessionMessages[messageIndex - 1] : nil
        // Only use image from user message if this is the first/only meal suggestion
        let imageData = message.suggestedMeals.count <= 1 ? userMessage?.imageData : nil

        let entry = FoodEntry()
        entry.name = meal.name
        entry.calories = meal.calories
        entry.proteinGrams = meal.proteinGrams
        entry.carbsGrams = meal.carbsGrams
        entry.fatGrams = meal.fatGrams
        entry.fiberGrams = meal.fiberGrams
        entry.servingSize = meal.servingSize
        entry.emoji = meal.emoji
        entry.imageData = imageData
        entry.inputMethod = "chat"

        let logDate: Date
        if let loggedAt = meal.loggedAtDate {
            entry.loggedAt = loggedAt
            logDate = loggedAt
        } else {
            logDate = entry.loggedAt
        }

        modelContext.insert(entry)

        // Sync to Apple Health if enabled
        if profile?.syncFoodToHealthKit == true {
            Task {
                do {
                    guard let healthKitService else { return }
                    try await healthKitService.saveDietaryEnergyAuthorized(Double(meal.calories), date: logDate)
                    print("HealthKit: Saved \(meal.calories) calories for \(meal.name)")
                } catch {
                    print("HealthKit: Failed to save dietary energy - \(error.localizedDescription)")
                }
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.markMealLogged(mealId: meal.id, entryId: entry.id)
        }

        HapticManager.success()
    }

    func dismissMealSuggestion(_ meal: SuggestedFoodEntry, for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.markMealDismissed(mealId: meal.id)
        }
        HapticManager.lightTap()
    }
}

// MARK: - Plan Suggestion Actions

extension ChatView {
    func acceptPlanSuggestion(_ plan: PlanUpdateSuggestionEntry, for message: ChatMessage) {
        guard let profile else { return }

        let currentWeight = weightEntries.first?.weightKg

        // Archive current plan before updating
        archiveCurrentPlan(profile: profile, reason: .chatAdjustment, userWeightKg: currentWeight)

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
        if let goalString = plan.goal {
            // Convert goal string to GoalType (handles various formats)
            let normalizedGoal = goalString.lowercased().replacing("_", with: "")
            if let goalType = UserProfile.GoalType.allCases.first(where: {
                $0.rawValue.lowercased() == normalizedGoal
            }) {
                profile.goal = goalType
            }
        }

        // Update assessment state - marks plan as reviewed with current weight as new baseline
        planAssessmentService.markPlanReviewed(profile: profile, currentWeightKg: currentWeight)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.planUpdateApplied = true
        }

        HapticManager.success()
    }

    /// Archive the current nutrition plan to history before making changes
    private func archiveCurrentPlan(profile: UserProfile, reason: PlanChangeReason, userWeightKg: Double?) {
        // Create a NutritionPlan from current profile values
        let currentPlan = NutritionPlan(
            dailyTargets: NutritionPlan.DailyTargets(
                calories: profile.dailyCalorieGoal,
                protein: profile.dailyProteinGoal,
                carbs: profile.dailyCarbsGoal,
                fat: profile.dailyFatGoal,
                fiber: profile.dailyFiberGoal,
                sugar: profile.dailySugarGoal
            ),
            rationale: profile.aiPlanRationale,
            macroSplit: NutritionPlan.MacroSplit(
                proteinPercent: 0, // Will be calculated
                carbsPercent: 0,
                fatPercent: 0
            ),
            nutritionGuidelines: [],
            mealTimingSuggestion: "",
            weeklyAdjustments: nil,
            warnings: nil,
            progressInsights: nil
        )

        // Create and insert version record
        let version = NutritionPlanVersion(
            plan: currentPlan,
            reason: reason,
            userWeightKg: userWeightKg,
            userGoal: profile.goal.rawValue
        )

        modelContext.insert(version)
    }

    func dismissPlanSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedPlanDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Workout Log Suggestion Actions

extension ChatView {
    func acceptWorkoutLogSuggestion(_ workoutLog: SuggestedWorkoutLog, for message: ChatMessage) {
        // Create a LiveWorkout with proper exercise details
        let workout = LiveWorkout(
            name: workoutLog.displayName,
            workoutType: workoutLog.isStrength ? .strength : .cardio,
            targetMuscleGroups: []
        )

        // Add exercises as entries
        var entries: [LiveWorkoutEntry] = []
        for (index, exercise) in workoutLog.exercises.enumerated() {
            let entry = LiveWorkoutEntry(exerciseName: exercise.name, orderIndex: index)

            // Add each set with its specific reps/weight
            for setData in exercise.sets {
                let cleanWeight = WeightUtility.cleanWeightFromKg(setData.weightKg ?? 0)
                entry.addSet(LiveWorkoutEntry.SetData(
                    reps: setData.reps,
                    weight: cleanWeight,
                    completed: true,
                    isWarmup: false
                ))
            }

            entries.append(entry)
        }
        workout.entries = entries

        // Set duration by adjusting start time
        if let duration = workoutLog.durationMinutes {
            workout.startedAt = Date().addingTimeInterval(-Double(duration) * 60)
        }

        // Mark as completed
        workout.completedAt = Date()

        if let notes = workoutLog.notes {
            workout.notes = notes
        }

        // Save to database
        modelContext.insert(workout)
        try? modelContext.save()

        // Update message state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.workoutLogSaved = true
        }

        HapticManager.success()
    }

    func dismissWorkoutLogSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedWorkoutLogDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Workout Suggestion Actions

extension ChatView {
    func acceptWorkoutSuggestion(_ workout: SuggestedWorkoutEntry, for message: ChatMessage) {
        // Map workout type string to enum
        let workoutType = LiveWorkout.WorkoutType(rawValue: workout.workoutType) ?? .strength

        // Map target muscle groups
        let targetMuscles = workout.targetMuscleGroups.compactMap {
            LiveWorkout.MuscleGroup(rawValue: $0)
        }

        // Create the LiveWorkout
        let liveWorkout = LiveWorkout(
            name: workout.name,
            workoutType: workoutType,
            targetMuscleGroups: targetMuscles
        )

        // Add suggested exercises as entries
        var entries: [LiveWorkoutEntry] = []
        for (index, exercise) in workout.exercises.enumerated() {
            let entry = LiveWorkoutEntry(exerciseName: exercise.name, orderIndex: index)

            // Pre-populate sets
            let cleanWeight = WeightUtility.cleanWeightFromKg(exercise.weightKg ?? 0)
            for _ in 0..<exercise.sets {
                entry.addSet(LiveWorkoutEntry.SetData(
                    reps: exercise.reps,
                    weight: cleanWeight,
                    completed: false,
                    isWarmup: false
                ))
            }

            entries.append(entry)
        }
        liveWorkout.entries = entries

        // Save to database
        modelContext.insert(liveWorkout)
        try? modelContext.save()

        // Update message state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.workoutStarted = true
            message.startedWorkoutId = liveWorkout.id
        }

        HapticManager.success()
    }

    func dismissWorkoutSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedWorkoutDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Food Edit Suggestion Actions

extension ChatView {
    func acceptFoodEditSuggestion(_ edit: SuggestedFoodEdit, for message: ChatMessage) {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.id == edit.entryId }
        )

        guard let entry = try? modelContext.fetch(descriptor).first else { return }

        for change in edit.changes {
            switch change.fieldKey {
            case "calories":
                if let value = change.newNumericValue {
                    entry.calories = Int(value)
                }
            case "proteinGrams":
                if let value = change.newNumericValue {
                    entry.proteinGrams = value
                }
            case "carbsGrams":
                if let value = change.newNumericValue {
                    entry.carbsGrams = value
                }
            case "fatGrams":
                if let value = change.newNumericValue {
                    entry.fatGrams = value
                }
            case "fiberGrams":
                if let value = change.newNumericValue {
                    entry.fiberGrams = value
                }
            case "name", "title":
                if let value = change.newStringValue {
                    entry.name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "servingSize":
                if let value = change.newStringValue {
                    let servingSize = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    entry.servingSize = servingSize.isEmpty ? nil : servingSize
                }
            case "mealType":
                if let value = change.newStringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_"),
                   FoodEntry.MealType(rawValue: value) != nil {
                    entry.meal = .init(rawValue: value) ?? entry.meal
                }
            case "notes":
                if let value = change.newStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    entry.userDescription = value.isEmpty ? nil : value
                }
            case "loggedAt":
                if let timeString = change.newStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !timeString.isEmpty {
                    let timeFormatter = DateFormatter()
                    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
                    timeFormatter.dateFormat = "HH:mm"

                    guard let timeValue = timeFormatter.date(from: timeString) else { break }
                    let clockComponents = Calendar.current.dateComponents([.hour, .minute], from: timeValue)
                    guard let hour = clockComponents.hour, let minute = clockComponents.minute else { break }

                    var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: entry.loggedAt)
                    dateComponents.hour = hour
                    dateComponents.minute = minute
                    dateComponents.second = 0

                    if let updatedAt = Calendar.current.date(from: dateComponents) {
                        entry.loggedAt = updatedAt
                    }
                }
            default:
                break
            }
        }

        try? modelContext.save()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.foodEditApplied = true
        }

        HapticManager.success()
    }

    func dismissFoodEditSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedFoodEditDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Plan Reassessment Actions

extension ChatView {
    /// Check if a plan review should be recommended on chat open
    func checkForPlanRecommendation() {
        // Only check if not in incognito mode and we have a profile
        guard let profile, !isTemporarySession else { return }

        // Don't check if we already have a recommendation showing
        guard pendingPlanRecommendation == nil else { return }

        // Check for recommendation triggers
        if let recommendation = planAssessmentService.checkForRecommendation(
            profile: profile,
            weightEntries: Array(weightEntries),
            foodEntries: Array(allFoodEntries)
        ) {
            pendingPlanRecommendation = recommendation
            planRecommendationMessage = planAssessmentService.getRecommendationMessage(
                recommendation,
                useLbs: !profile.usesMetricWeight
            )
        }
    }

    /// Handle when user taps "Review Plan" on recommendation card
    func handlePlanReviewRequest() {
        guard let recommendation = pendingPlanRecommendation else { return }

        // Clear the card first
        withAnimation {
            pendingPlanRecommendation = nil
            planRecommendationMessage = nil
        }

        // Construct a contextual message based on the trigger
        let prompt: String
        switch recommendation.trigger {
        case .weightChange:
            if let change = recommendation.details.weightChangeKg {
                if change > 0 {
                    prompt = "My weight has increased since my plan was created. Can you analyze my progress and suggest plan adjustments?"
                } else {
                    prompt = "I've lost weight since my plan was created. Can you review my plan and suggest updates for continued progress?"
                }
            } else {
                prompt = "My weight has changed. Can you review my plan?"
            }

        case .weightPlateau:
            prompt = "I've hit a weight plateau. Can you analyze why and suggest plan adjustments to break through?"

        case .planAge:
            prompt = "It's been a while since my plan was reviewed. Can you check my progress and suggest any needed updates?"
        }

        // Send the message through the normal chat flow
        sendMessage(prompt)
    }

    /// Handle when user taps "Later" or dismiss on recommendation card
    func handleDismissPlanRecommendation() {
        guard let recommendation = pendingPlanRecommendation,
              let profile else { return }

        // Record the dismissal
        planAssessmentService.dismissRecommendation(recommendation, profile: profile)

        // Clear the card
        withAnimation {
            pendingPlanRecommendation = nil
            planRecommendationMessage = nil
        }

        HapticManager.lightTap()
    }

    /// Check for pending plan review request from Profile (cross-tab navigation)
    func checkForPendingPlanReview() {
        if pendingPlanReviewRequest {
            pendingPlanReviewRequest = false
            startNewSession(silent: true)
            sendMessage("Can you review my nutrition plan and check if any updates are needed based on my progress?")
            return
        }

        guard pendingWorkoutPlanReviewRequest else { return }
        pendingWorkoutPlanReviewRequest = false
        startNewSession(silent: true)
        sendMessage("Can you review my workout split and suggest any updates based on my recovery and recent workouts?")
    }

    /// Check if Dashboard queued a Pulse context prompt for chat handoff
    func checkForPendingPulsePrompt() {
        let prompt = pendingPulseSeedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        pendingPulseSeedPrompt = ""
        pulseHandoffContext = prompt
    }
}

// MARK: - Reminder Suggestion Actions

extension ChatView {
    func acceptReminderSuggestion(_ suggestion: SuggestedReminder, for message: ChatMessage) {
        // Create the custom reminder
        let reminder = CustomReminder(
            title: suggestion.title,
            body: suggestion.body,
            hour: suggestion.hour,
            minute: suggestion.minute,
            repeatDays: suggestion.repeatDays,
            isEnabled: true
        )

        modelContext.insert(reminder)

        // Schedule the notification
        Task {
            let service = NotificationService()
            await service.updateAuthorizationStatus()
            await service.scheduleCustomReminder(reminder)
        }

        // Update message state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.reminderCreated = true
        }

        HapticManager.success()
    }

    func editReminderSuggestion(_ suggestion: SuggestedReminder, for message: ChatMessage) {
        // Show the edit sheet with the suggestion prefilled
        pendingReminderEdit = suggestion
        showReminderEditSheet = true
    }

    func dismissReminderSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedReminderDismissed = true
        }
        HapticManager.lightTap()
    }
}
