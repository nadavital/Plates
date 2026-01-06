//
//  ChatContentList.swift
//  Plates
//
//  Chat message list with loading indicator
//

import SwiftUI

struct ChatContentList: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let isStreamingResponse: Bool
    let isTemporarySession: Bool
    let currentActivity: String?
    let currentCalories: Int?
    let currentProtein: Int?
    let currentCarbs: Int?
    let currentFat: Int?
    let onSuggestionTapped: (String) -> Void
    let onAcceptMeal: (SuggestedFoodEntry, ChatMessage) -> Void
    let onEditMeal: (ChatMessage, SuggestedFoodEntry) -> Void
    let onDismissMeal: (ChatMessage) -> Void
    let onViewLoggedMeal: (UUID) -> Void
    let onAcceptPlan: (PlanUpdateSuggestionEntry, ChatMessage) -> Void
    let onEditPlan: (ChatMessage, PlanUpdateSuggestionEntry) -> Void
    let onDismissPlan: (ChatMessage) -> Void
    let onAcceptFoodEdit: (SuggestedFoodEdit, ChatMessage) -> Void
    let onDismissFoodEdit: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            if messages.isEmpty {
                EmptyChatView(
                    onSuggestionTapped: onSuggestionTapped,
                    isLoading: isLoading,
                    isTemporary: isTemporarySession
                )
            } else {
                ForEach(messages) { message in
                    if !message.content.isEmpty || message.isFromUser || message.errorMessage != nil || message.hasPendingMealSuggestion || message.loggedFoodEntryId != nil || message.hasPendingPlanSuggestion || message.planUpdateApplied || message.hasPendingFoodEdit || message.hasAppliedFoodEdit {
                        VStack(spacing: 0) {
                            ChatBubble(
                                message: message,
                                currentCalories: currentCalories,
                                currentProtein: currentProtein,
                                currentCarbs: currentCarbs,
                                currentFat: currentFat,
                                onAcceptMeal: { meal in
                                    onAcceptMeal(meal, message)
                                },
                                onEditMeal: { meal in
                                    onEditMeal(message, meal)
                                },
                                onDismissMeal: {
                                    onDismissMeal(message)
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
                                onRetry: {
                                    onRetry(message)
                                }
                            )
                        }
                        .id(message.id)
                    }
                }
            }

            if isLoading && !isStreamingResponse {
                ThinkingIndicator(activity: currentActivity)
            }
        }
        .padding()
    }
}
