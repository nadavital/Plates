//
//  OnboardingView+Completion.swift
//  Trai
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
        profile.syncFoodToHealthKit = syncFoodToHealthKit
        profile.syncWeightToHealthKit = syncWeightToHealthKit

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

        // Workout plan (if user created one)
        if let workoutPlan = generatedWorkoutPlan {
            profile.workoutPlan = workoutPlan
        }

        profile.hasCompletedOnboarding = true
        modelContext.insert(profile)

        if let workoutPlan = generatedWorkoutPlan {
            WorkoutPlanHistoryService.archivePlan(
                workoutPlan,
                profile: profile,
                reason: .onboarding,
                modelContext: modelContext
            )
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: AppLaunchArguments.onboardingCompletedCacheKey)
            clearOnboardingDraft()
        } catch {
            print("Failed to persist onboarding profile: \(error)")
        }

        // Parse and create categorized memories from user notes (async)
        Task {
            await parseAndCreateMemories()
        }
    }

    // MARK: - Memory Creation

    /// Parse user notes using AI to create properly categorized memories
    func parseAndCreateMemories() async {
        // Combine all notes with context
        var allNotes: [(notes: String, context: String)] = []

        let trimmedActivityNotes = activityNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedActivityNotes.isEmpty {
            allNotes.append((trimmedActivityNotes, "activity and workout preferences"))
        }

        let trimmedGoalNotes = additionalGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGoalNotes.isEmpty {
            allNotes.append((trimmedGoalNotes, "fitness goals and preferences"))
        }

        // If no notes to parse, return early
        guard !allNotes.isEmpty else { return }

        guard monetizationService?.canAccessAIFeatures ?? true else {
            for (notes, context) in allNotes {
                createSimpleMemory(content: notes, context: context)
            }
            return
        }

        let aiService = AIService()

        // Parse each set of notes
        for (notes, context) in allNotes {
            do {
                let parsedMemories = try await aiService.parseNotesIntoMemories(
                    notes: notes,
                    context: context
                )

                // Insert each parsed memory
                for parsed in parsedMemories {
                    let memory = parsed.toCoachMemory(source: "onboarding")
                    modelContext.insert(memory)
                }
                do {
                    try modelContext.save()
                    NotificationCenter.default.post(name: .coachMemoriesChanged, object: nil)
                } catch {
                    modelContext.rollback()
                    print("Failed to persist onboarding memories: \(error)")
                }
            } catch {
                // Fall back to simple memory creation if AI parsing fails
                print("Failed to parse notes with AI, using fallback: \(error)")
                createSimpleMemory(content: notes, context: context)
            }
        }
    }

    /// Fallback: Create a single memory if AI parsing fails
    private func createSimpleMemory(content: String, context: String) {
        let topic: MemoryTopic = context.contains("workout") ? .workout : .general
        let memory = CoachMemory(
            content: content,
            category: .context,
            topic: topic,
            source: "onboarding",
            importance: 4
        )
        modelContext.insert(memory)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .coachMemoriesChanged, object: nil)
        } catch {
            modelContext.rollback()
            print("Failed to persist fallback onboarding memory: \(error)")
        }
    }
}
