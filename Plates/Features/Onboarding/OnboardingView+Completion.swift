//
//  OnboardingView+Completion.swift
//  Plates
//
//  Onboarding completion and profile creation logic
//

import Foundation
import SwiftData

extension OnboardingView {
    // MARK: - Complete Onboarding

    func completeOnboarding() {
        HapticManager.success()

        let profile = UserProfile()

        // Basic info
        profile.name = userName.trimmingCharacters(in: .whitespaces)
        profile.dateOfBirth = dateOfBirth
        profile.gender = (gender ?? .notSpecified).rawValue

        // Biometrics (always store in metric)
        profile.heightCm = parseHeight()
        profile.currentWeightKg = parseWeight(weightValue)
        profile.targetWeightKg = parseWeight(targetWeightValue)
        profile.usesMetricHeight = usesMetricHeight
        profile.usesMetricWeight = usesMetricWeight

        // Activity
        profile.activityLevel = (activityLevel ?? .moderate).rawValue
        profile.activityNotes = activityNotes

        // Goals
        profile.goalType = (selectedGoal ?? .health).rawValue
        profile.additionalGoalNotes = additionalGoalNotes

        // Macro tracking preferences
        profile.enabledMacros = enabledMacros

        // Nutrition targets (from adjusted values or plan)
        profile.dailyCalorieGoal = Int(adjustedCalories) ?? 2000
        profile.dailyProteinGoal = Int(adjustedProtein) ?? 150
        profile.dailyCarbsGoal = Int(adjustedCarbs) ?? 200
        profile.dailyFatGoal = Int(adjustedFat) ?? 65

        // AI plan metadata
        if let plan = generatedPlan {
            profile.aiPlanRationale = plan.rationale
            profile.aiPlanGeneratedAt = Date()
            profile.dailyFiberGoal = plan.dailyTargets.fiber
        }

        // Workout plan (if user opted in)
        if wantsWorkoutPlan == true, let workoutPlan = generatedWorkoutPlan {
            profile.workoutPlan = workoutPlan
            profile.preferredWorkoutDays = workoutDaysPerWeek
            profile.workoutExperience = workoutExperienceLevel
            profile.workoutEquipment = workoutEquipmentAccess
            profile.workoutTimePerSession = workoutTimePerSession
        }

        profile.hasCompletedOnboarding = true
        modelContext.insert(profile)

        // Create memories from user notes
        createMemoriesFromNotes()
    }

    // MARK: - Memory Creation

    func createMemoriesFromNotes() {
        // Import activity notes as a memory
        let trimmedActivityNotes = activityNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedActivityNotes.isEmpty {
            let activityMemory = CoachMemory(
                content: trimmedActivityNotes,
                category: .context,
                topic: .workout,
                source: "onboarding",
                importance: 4
            )
            modelContext.insert(activityMemory)
        }

        // Import additional goal notes as a memory
        let trimmedGoalNotes = additionalGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGoalNotes.isEmpty {
            let goalMemory = CoachMemory(
                content: trimmedGoalNotes,
                category: .context,
                topic: .general,
                source: "onboarding",
                importance: 4
            )
            modelContext.insert(goalMemory)
        }
    }
}
