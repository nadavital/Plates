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
    var onSelectSuggestedResponse: ((CheckInResponseOption, ChatMessage) -> Void)?

    var body: some View {
        LazyVStack(spacing: 12) {
            if messages.isEmpty {
                EmptyChatView(onSuggestionTapped: onSuggestionTapped, isLoading: isLoading)
            } else {
                ForEach(messages) { message in
                    if !message.content.isEmpty || message.isFromUser || message.errorMessage != nil || message.hasPendingMealSuggestion || message.loggedFoodEntryId != nil || message.hasPendingPlanSuggestion || message.planUpdateApplied {
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
                                }
                            )

                            // Suggested responses for check-in messages
                            if message.hasPendingSuggestedResponses,
                               let responses = message.suggestedResponses,
                               let onSelect = onSelectSuggestedResponse {
                                SuggestedResponsesView(responses: responses) { response in
                                    onSelect(response, message)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .id(message.id)
                    }
                }
            }

            if isLoading && !isStreamingResponse {
                ThinkingIndicator()
            }
        }
        .padding()
    }
}
