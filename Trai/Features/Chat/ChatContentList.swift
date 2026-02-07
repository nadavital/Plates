//
//  ChatContentList.swift
//  Trai
//
//  Chat message list with loading indicator
//

import SwiftUI

struct ChatContentList: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let isStreamingResponse: Bool
    let isTemporarySession: Bool
    var smartStarterContext: SmartStarterContext = SmartStarterContext()
    let currentActivity: String?
    let currentCalories: Int?
    let currentProtein: Int?
    let currentCarbs: Int?
    let currentFat: Int?
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    var planRecommendation: PlanRecommendation?
    var planRecommendationMessage: String?
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
    var useExerciseWeightLbs: Bool = false
    let onRetry: (ChatMessage) -> Void
    var onImageTapped: ((UIImage) -> Void)?
    var onViewAppliedPlan: ((PlanUpdateSuggestionEntry) -> Void)?
    var onReviewPlan: (() -> Void)?
    var onDismissPlanRecommendation: (() -> Void)?

    var body: some View {
        LazyVStack(spacing: 12) {
            // Plan review recommendation card (if triggered)
            if let recommendation = planRecommendation,
               let message = planRecommendationMessage,
               let onReview = onReviewPlan,
               let onDismiss = onDismissPlanRecommendation {
                PlanReviewRecommendationCard(
                    recommendation: recommendation,
                    message: message,
                    onReviewPlan: onReview,
                    onDismiss: onDismiss
                )
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }

            if messages.isEmpty {
                EmptyChatView(
                    isLoading: isLoading,
                    isTemporary: isTemporarySession,
                    context: smartStarterContext
                )
            } else {
                ForEach(messages) { message in
                    if !message.content.isEmpty || message.isFromUser || message.errorMessage != nil || message.hasPendingMealSuggestion || message.loggedFoodEntryId != nil || message.hasPendingPlanSuggestion || message.planUpdateApplied || message.hasPendingFoodEdit || message.hasAppliedFoodEdit || message.hasPendingWorkoutSuggestion || message.hasStartedWorkout || message.hasPendingWorkoutLogSuggestion || message.hasSavedWorkoutLog || message.hasPendingReminderSuggestion || message.hasCreatedReminder || message.hasSavedMemories {
                        VStack(spacing: 0) {
                            ChatBubble(
                                message: message,
                                currentCalories: currentCalories,
                                currentProtein: currentProtein,
                                currentCarbs: currentCarbs,
                                currentFat: currentFat,
                                enabledMacros: enabledMacros,
                                onAcceptMeal: { meal in
                                    onAcceptMeal(meal, message)
                                },
                                isMealLogging: { meal in
                                    isMealLogging(meal, message)
                                },
                                onEditMeal: { meal in
                                    onEditMeal(message, meal)
                                },
                                onDismissMeal: { meal in
                                    onDismissMeal(meal, message)
                                },
                                onViewLoggedMeal: { entryId in
                                    onViewLoggedMeal(entryId)
                                },
                                onAcceptPlan: { plan in
                                    onAcceptPlan(plan, message)
                                },
                                onEditPlan: { plan in
                                    onEditPlan(message, plan)
                                },
                                onDismissPlan: {
                                    onDismissPlan(message)
                                },
                                onAcceptFoodEdit: { edit in
                                    onAcceptFoodEdit(edit, message)
                                },
                                onDismissFoodEdit: {
                                    onDismissFoodEdit(message)
                                },
                                onAcceptWorkout: { workout in
                                    onAcceptWorkout(workout, message)
                                },
                                onDismissWorkout: {
                                    onDismissWorkout(message)
                                },
                                onAcceptWorkoutLog: { workoutLog in
                                    onAcceptWorkoutLog(workoutLog, message)
                                },
                                onDismissWorkoutLog: {
                                    onDismissWorkoutLog(message)
                                },
                                onAcceptReminder: { reminder in
                                    onAcceptReminder(reminder, message)
                                },
                                onEditReminder: { reminder in
                                    onEditReminder(reminder, message)
                                },
                                onDismissReminder: {
                                    onDismissReminder(message)
                                },
                                useExerciseWeightLbs: useExerciseWeightLbs,
                                onRetry: {
                                    onRetry(message)
                                },
                                onImageTapped: onImageTapped,
                                onViewAppliedPlan: onViewAppliedPlan
                            )
                        }
                        .padding(.horizontal)
                        .id(message.id)
                    }
                }
            }

            if isLoading && !isStreamingResponse {
                ThinkingIndicator(activity: currentActivity)
                    .padding(.horizontal)
            }
        }
    }
}
