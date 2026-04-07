//
//  OnboardingView+PlanGeneration.swift
//  Trai
//
//  Plan generation logic for onboarding (nutrition plan)
//

import Foundation

extension OnboardingView {
    // MARK: - Plan Generation

    func generatePlan() {
        guard let age = calculateAge(),
              let heightCm = parseHeight(),
              let weightKg = parseWeight(weightValue) else {
            planError = "Please check your profile information and try again."
            return
        }

        let targetWeightKg = parseWeight(targetWeightValue)

        let request = PlanGenerationRequest(
            name: userName.trimmingCharacters(in: .whitespaces),
            age: age,
            gender: gender ?? .notSpecified,
            heightCm: heightCm,
            weightKg: weightKg,
            targetWeightKg: targetWeightKg,
            activityLevel: activityLevel ?? .moderate,
            activityNotes: activityNotes,
            goal: selectedGoal ?? .health,
            additionalNotes: additionalGoalNotes
        )

        isGeneratingPlan = true
        planError = nil

        Task { @MainActor in
            if !(monetizationService?.canAccessAIFeatures ?? true) {
                let fallbackPlan = NutritionPlan.createDefault(from: request)
                self.generatedPlan = fallbackPlan
                self.populateAdjustedValues(from: fallbackPlan)
                self.isGeneratingPlan = false
                return
            }

            do {
                let plan = try await geminiService.generateNutritionPlan(request: request)
                self.generatedPlan = plan
                self.populateAdjustedValues(from: plan)
            } catch {
                // Fall back to calculated plan
                print("⚠️ Plan generation failed, using fallback: \(error.localizedDescription)")
                let fallbackPlan = NutritionPlan.createDefault(from: request)
                self.generatedPlan = fallbackPlan
                self.populateAdjustedValues(from: fallbackPlan)
            }

            // Safety check: if plan is still nil after everything, set error
            if self.generatedPlan == nil {
                self.planError = "Failed to generate plan. Please try again."
            }

            self.isGeneratingPlan = false
        }
    }

    func populateAdjustedValues(from plan: NutritionPlan) {
        adjustedCalories = String(plan.dailyTargets.calories)
        adjustedProtein = String(plan.dailyTargets.protein)
        adjustedCarbs = String(plan.dailyTargets.carbs)
        adjustedFat = String(plan.dailyTargets.fat)
    }

    // MARK: - Parsing Helpers

    func calculateAge() -> Int? {
        let components = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date())
        return components.year
    }

    func parseHeight() -> Double? {
        guard let value = Double(heightValue) else { return nil }
        return usesMetricHeight ? value : value * 2.54
    }

    func parseWeight(_ value: String) -> Double? {
        guard !value.isEmpty, let parsed = Double(value) else { return nil }
        return usesMetricWeight ? parsed : parsed * 0.453592
    }

    func buildPlanRequest() -> PlanGenerationRequest? {
        guard let age = calculateAge(),
              let heightCm = parseHeight(),
              let weightKg = parseWeight(weightValue) else {
            return nil
        }

        return PlanGenerationRequest(
            name: userName.trimmingCharacters(in: .whitespaces),
            age: age,
            gender: gender ?? .notSpecified,
            heightCm: heightCm,
            weightKg: weightKg,
            targetWeightKg: parseWeight(targetWeightValue),
            activityLevel: activityLevel ?? .moderate,
            activityNotes: activityNotes,
            goal: selectedGoal ?? .health,
            additionalNotes: additionalGoalNotes
        )
    }
}
