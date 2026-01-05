//
//  PlanService.swift
//  Plates
//

import Foundation
import SwiftData

/// Service for managing nutrition plans - retrieval, storage, and recalculation logic
@MainActor @Observable
final class PlanService {

    // MARK: - Plan Retrieval

    /// Get the current saved nutrition plan for a profile
    func getCurrentPlan(for profile: UserProfile) -> NutritionPlan? {
        guard let json = profile.savedPlanJSON else { return nil }
        return NutritionPlan.fromJSON(json)
    }

    /// Check if profile has a saved plan
    func hasSavedPlan(for profile: UserProfile) -> Bool {
        profile.savedPlanJSON != nil
    }

    // MARK: - Plan Storage

    /// Save a nutrition plan to the user profile
    func savePlan(_ plan: NutritionPlan, to profile: UserProfile, currentWeight: Double? = nil) {
        // Store the plan as JSON
        profile.savedPlanJSON = plan.toJSON()
        profile.aiPlanGeneratedAt = Date()
        profile.aiPlanRationale = plan.rationale

        // Update daily goals from the plan
        profile.dailyCalorieGoal = plan.dailyTargets.calories
        profile.dailyProteinGoal = plan.dailyTargets.protein
        profile.dailyCarbsGoal = plan.dailyTargets.carbs
        profile.dailyFatGoal = plan.dailyTargets.fat
        profile.dailyFiberGoal = plan.dailyTargets.fiber

        // Store training/rest day calories if available
        if let weeklyAdj = plan.weeklyAdjustments {
            profile.trainingDayCalories = weeklyAdj.trainingDayCalories
            profile.restDayCalories = weeklyAdj.restDayCalories
        }

        // Store the weight at which plan was created (for recalc detection)
        if let weight = currentWeight {
            profile.lastWeightForPlanKg = weight
        } else if let currentWeight = profile.currentWeightKg {
            profile.lastWeightForPlanKg = currentWeight
        }
    }

    // MARK: - Effective Calories

    /// Get the effective calorie goal for today (considering training/rest day)
    func getEffectiveCalories(for profile: UserProfile) -> Int {
        return profile.effectiveCalorieGoal
    }

    /// Get detailed calorie info for display
    func getCalorieInfo(for profile: UserProfile) -> CalorieInfo {
        let base = profile.dailyCalorieGoal
        let effective = profile.effectiveCalorieGoal
        let isTraining = profile.isTrainingDay

        var adjustment: Int? = nil
        var adjustmentLabel: String? = nil

        if isTraining, let trainingCals = profile.trainingDayCalories, trainingCals != base {
            adjustment = trainingCals - base
            adjustmentLabel = "Training Day"
        } else if !isTraining, let restCals = profile.restDayCalories, restCals != base {
            adjustment = restCals - base
            adjustmentLabel = "Rest Day"
        }

        return CalorieInfo(
            baseCalories: base,
            effectiveCalories: effective,
            isTrainingDay: isTraining,
            adjustment: adjustment,
            adjustmentLabel: adjustmentLabel
        )
    }

    struct CalorieInfo {
        let baseCalories: Int
        let effectiveCalories: Int
        let isTrainingDay: Bool
        let adjustment: Int?
        let adjustmentLabel: String?

        var hasAdjustment: Bool {
            adjustment != nil && adjustment != 0
        }

        var formattedAdjustment: String? {
            guard let adj = adjustment else { return nil }
            if adj > 0 {
                return "+\(adj)"
            } else {
                return "\(adj)"
            }
        }
    }

    // MARK: - Recalculation Detection

    /// Check if the plan should be recalculated based on weight change
    func shouldPromptForRecalculation(profile: UserProfile, currentWeight: Double) -> Bool {
        return profile.shouldPromptForRecalculation(currentWeight: currentWeight)
    }

    /// Get the weight difference since plan was created
    func getWeightDifference(profile: UserProfile, currentWeight: Double) -> Double? {
        guard let lastWeight = profile.lastWeightForPlanKg else { return nil }
        return currentWeight - lastWeight
    }

    // MARK: - Training Day Detection

    /// Check if today is a training day based on logged workouts
    func isTrainingDay(workouts: [WorkoutSession]) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return workouts.contains { $0.loggedAt >= startOfDay }
    }

    /// Check if today is a training day based on live workouts
    func isTrainingDay(liveWorkouts: [LiveWorkout]) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return liveWorkouts.contains { $0.startedAt >= startOfDay }
    }

    /// Get effective calories considering auto-detected training day
    func getEffectiveCalories(for profile: UserProfile, hasWorkoutToday: Bool) -> Int {
        if hasWorkoutToday, let trainingCals = profile.trainingDayCalories {
            return trainingCals
        } else if !hasWorkoutToday, let restCals = profile.restDayCalories {
            return restCals
        }
        return profile.dailyCalorieGoal
    }

    // MARK: - Plan Comparison

    /// Compare two plans and describe the differences
    func comparePlans(_ old: NutritionPlan, _ new: NutritionPlan) -> PlanComparison {
        PlanComparison(
            calorieChange: new.dailyTargets.calories - old.dailyTargets.calories,
            proteinChange: new.dailyTargets.protein - old.dailyTargets.protein,
            carbsChange: new.dailyTargets.carbs - old.dailyTargets.carbs,
            fatChange: new.dailyTargets.fat - old.dailyTargets.fat
        )
    }

    struct PlanComparison {
        let calorieChange: Int
        let proteinChange: Int
        let carbsChange: Int
        let fatChange: Int

        var hasSignificantChange: Bool {
            abs(calorieChange) >= 50 || abs(proteinChange) >= 10 ||
            abs(carbsChange) >= 20 || abs(fatChange) >= 5
        }

        var summary: String {
            var changes: [String] = []

            if calorieChange != 0 {
                let sign = calorieChange > 0 ? "+" : ""
                changes.append("\(sign)\(calorieChange) calories")
            }
            if proteinChange != 0 {
                let sign = proteinChange > 0 ? "+" : ""
                changes.append("\(sign)\(proteinChange)g protein")
            }

            return changes.isEmpty ? "No changes" : changes.joined(separator: ", ")
        }
    }
}
