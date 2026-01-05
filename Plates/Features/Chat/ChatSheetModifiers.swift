//
//  ChatSheetModifiers.swift
//  Plates
//
//  Sheet and fullscreen cover modifiers for ChatView
//

import SwiftUI

extension View {
    func chatCameraSheet(
        showingCamera: Binding<Bool>,
        onCapture: @escaping (UIImage) -> Void
    ) -> some View {
        self.fullScreenCover(isPresented: showingCamera) {
            ChatCameraView(onCapture: onCapture)
        }
    }

    func chatImagePreviewSheet(
        enlargedImage: Binding<UIImage?>
    ) -> some View {
        self.fullScreenCover(isPresented: Binding(
            get: { enlargedImage.wrappedValue != nil },
            set: { if !$0 { enlargedImage.wrappedValue = nil } }
        )) {
            if let image = enlargedImage.wrappedValue {
                ImagePreviewView(image: image) {
                    enlargedImage.wrappedValue = nil
                }
            }
        }
    }

    func chatEditMealSheet(
        editingMeal: Binding<(message: ChatMessage, meal: SuggestedFoodEntry)?>,
        onSave: @escaping (SuggestedFoodEntry, ChatMessage) -> Void
    ) -> some View {
        self.sheet(isPresented: Binding(
            get: { editingMeal.wrappedValue != nil },
            set: { if !$0 { editingMeal.wrappedValue = nil } }
        )) {
            if let editing = editingMeal.wrappedValue {
                EditMealSuggestionSheet(meal: editing.meal) { updatedMeal in
                    onSave(updatedMeal, editing.message)
                    editingMeal.wrappedValue = nil
                }
            }
        }
    }

    func chatViewFoodEntrySheet(
        viewingEntry: FoodEntry?,
        viewingLoggedMealId: Binding<UUID?>
    ) -> some View {
        self.sheet(isPresented: Binding(
            get: { viewingEntry != nil },
            set: { if !$0 { viewingLoggedMealId.wrappedValue = nil } }
        )) {
            if let entry = viewingEntry {
                EditFoodEntrySheet(entry: entry)
            }
        }
    }

    func chatEditPlanSheet(
        editingPlan: Binding<(message: ChatMessage, plan: PlanUpdateSuggestionEntry)?>,
        currentCalories: Int,
        currentProtein: Int,
        currentCarbs: Int,
        currentFat: Int,
        onSave: @escaping (PlanUpdateSuggestionEntry, ChatMessage) -> Void
    ) -> some View {
        self.sheet(isPresented: Binding(
            get: { editingPlan.wrappedValue != nil },
            set: { if !$0 { editingPlan.wrappedValue = nil } }
        )) {
            if let editing = editingPlan.wrappedValue {
                EditPlanSuggestionSheet(
                    suggestion: editing.plan,
                    currentCalories: currentCalories,
                    currentProtein: currentProtein,
                    currentCarbs: currentCarbs,
                    currentFat: currentFat
                ) { updatedPlan in
                    onSave(updatedPlan, editing.message)
                    editingPlan.wrappedValue = nil
                }
            }
        }
    }
}
