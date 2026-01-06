//
//  ChatViewActions.swift
//  Plates
//
//  Chat view action handlers for suggestions
//

import SwiftUI
import SwiftData

// MARK: - Meal Suggestion Actions

extension ChatView {
    func acceptMealSuggestion(_ meal: SuggestedFoodEntry, for message: ChatMessage) {
        let messageIndex = currentSessionMessages.firstIndex(where: { $0.id == message.id }) ?? 0
        let userMessage = messageIndex > 0 ? currentSessionMessages[messageIndex - 1] : nil
        let imageData = userMessage?.imageData

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

        if let loggedAt = meal.loggedAtDate {
            entry.loggedAt = loggedAt
        }

        modelContext.insert(entry)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            message.loggedFoodEntryId = entry.id
        }

        HapticManager.success()
    }

    func dismissMealSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedMealDismissed = true
        }
        HapticManager.lightTap()
    }
}

// MARK: - Plan Suggestion Actions

extension ChatView {
    func acceptPlanSuggestion(_ plan: PlanUpdateSuggestionEntry, for message: ChatMessage) {
        guard let profile else { return }

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

    func dismissPlanSuggestion(for message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.2)) {
            message.suggestedPlanDismissed = true
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
                entry.calories = Int(change.newNumericValue)
            case "proteinGrams":
                entry.proteinGrams = change.newNumericValue
            case "carbsGrams":
                entry.carbsGrams = change.newNumericValue
            case "fatGrams":
                entry.fatGrams = change.newNumericValue
            case "fiberGrams":
                entry.fiberGrams = change.newNumericValue
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
