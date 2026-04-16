//
//  OnboardingView+DraftPersistence.swift
//  Trai
//
//  Persists in-progress onboarding state so users can resume later.
//

import Foundation

extension OnboardingView {
    struct OnboardingDraft: Codable, Equatable {
        var currentStep: Int
        var userName: String
        var dateOfBirth: Date
        var genderRawValue: String?
        var heightValue: String
        var weightValue: String
        var targetWeightValue: String
        var usesMetricHeight: Bool
        var usesMetricWeight: Bool
        var activityLevelRawValue: String?
        var activityNotes: String
        var selectedGoalRawValue: String?
        var additionalGoalNotes: String
        var enabledMacros: Set<MacroType>
        var syncFoodToHealthKit: Bool
        var syncWeightToHealthKit: Bool
        var healthSyncError: String?
        var generatedPlan: NutritionPlan?
        var adjustedCalories: String
        var adjustedProtein: String
        var adjustedCarbs: String
        var adjustedFat: String
        var lastGeneratedPlanInputSignature: String?
        var generatedWorkoutPlan: WorkoutPlan?
    }

    private static let onboardingDraftStorageKey = "onboardingDraft"

    var onboardingDraftSnapshot: OnboardingDraft {
        OnboardingDraft(
            currentStep: currentStep,
            userName: userName,
            dateOfBirth: dateOfBirth,
            genderRawValue: gender?.rawValue,
            heightValue: heightValue,
            weightValue: weightValue,
            targetWeightValue: targetWeightValue,
            usesMetricHeight: usesMetricHeight,
            usesMetricWeight: usesMetricWeight,
            activityLevelRawValue: activityLevel?.rawValue,
            activityNotes: activityNotes,
            selectedGoalRawValue: selectedGoal?.rawValue,
            additionalGoalNotes: additionalGoalNotes,
            enabledMacros: enabledMacros,
            syncFoodToHealthKit: syncFoodToHealthKit,
            syncWeightToHealthKit: syncWeightToHealthKit,
            healthSyncError: healthSyncError,
            generatedPlan: generatedPlan,
            adjustedCalories: adjustedCalories,
            adjustedProtein: adjustedProtein,
            adjustedCarbs: adjustedCarbs,
            adjustedFat: adjustedFat,
            lastGeneratedPlanInputSignature: lastGeneratedPlanInputSignature,
            generatedWorkoutPlan: generatedWorkoutPlan
        )
    }

    var hasDraftProgress: Bool {
        currentStep > 0 ||
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !heightValue.isEmpty ||
        !weightValue.isEmpty ||
        !targetWeightValue.isEmpty ||
        gender != nil ||
        activityLevel != nil ||
        selectedGoal != nil ||
        !activityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !additionalGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        generatedPlan != nil ||
        generatedWorkoutPlan != nil
    }

    func restoreDraftIfNeeded() {
        guard !hasRestoredDraft else { return }
        hasRestoredDraft = true

        guard let data = UserDefaults.standard.data(forKey: Self.onboardingDraftStorageKey),
              let draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data) else {
            return
        }

        userName = draft.userName
        dateOfBirth = draft.dateOfBirth
        gender = draft.genderRawValue.flatMap(UserProfile.Gender.init(rawValue:))
        heightValue = draft.heightValue
        weightValue = draft.weightValue
        targetWeightValue = draft.targetWeightValue
        usesMetricHeight = draft.usesMetricHeight
        usesMetricWeight = draft.usesMetricWeight
        activityLevel = draft.activityLevelRawValue.flatMap(UserProfile.ActivityLevel.init(rawValue:))
        activityNotes = draft.activityNotes
        selectedGoal = draft.selectedGoalRawValue.flatMap(UserProfile.GoalType.init(rawValue:))
        additionalGoalNotes = draft.additionalGoalNotes
        enabledMacros = draft.enabledMacros
        syncFoodToHealthKit = draft.syncFoodToHealthKit
        syncWeightToHealthKit = draft.syncWeightToHealthKit
        healthSyncError = draft.healthSyncError
        generatedPlan = draft.generatedPlan
        adjustedCalories = draft.adjustedCalories
        adjustedProtein = draft.adjustedProtein
        adjustedCarbs = draft.adjustedCarbs
        adjustedFat = draft.adjustedFat
        lastGeneratedPlanInputSignature = draft.lastGeneratedPlanInputSignature
        generatedWorkoutPlan = draft.generatedWorkoutPlan

        if let generatedPlan, adjustedCalories.isEmpty {
            populateAdjustedValues(from: generatedPlan)
        }
        if generatedPlan == nil && draft.currentStep >= 8 {
            currentStep = 7
        } else {
            currentStep = min(draft.currentStep, totalSteps - 1)
        }
    }

    func persistOnboardingDraft() {
        guard hasRestoredDraft else { return }

        if !hasDraftProgress {
            clearOnboardingDraft()
            return
        }

        guard let data = try? JSONEncoder().encode(onboardingDraftSnapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.onboardingDraftStorageKey)
    }

    func clearOnboardingDraft() {
        UserDefaults.standard.removeObject(forKey: Self.onboardingDraftStorageKey)
    }
}
