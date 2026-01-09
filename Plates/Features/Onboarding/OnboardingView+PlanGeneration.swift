//
//  OnboardingView+PlanGeneration.swift
//  Plates
//
//  Plan generation logic for onboarding (nutrition + workout)
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

        Task {
            do {
                let plan = try await geminiService.generateNutritionPlan(request: request)
                generatedPlan = plan
                populateAdjustedValues(from: plan)
            } catch {
                // Fall back to calculated plan
                let fallbackPlan = NutritionPlan.createDefault(from: request)
                generatedPlan = fallbackPlan
                populateAdjustedValues(from: fallbackPlan)
            }
            isGeneratingPlan = false
        }
    }

    func populateAdjustedValues(from plan: NutritionPlan) {
        adjustedCalories = String(plan.dailyTargets.calories)
        adjustedProtein = String(plan.dailyTargets.protein)
        adjustedCarbs = String(plan.dailyTargets.carbs)
        adjustedFat = String(plan.dailyTargets.fat)
    }

    // MARK: - Workout Plan Generation

    func generateWorkoutPlan() {
        guard let age = calculateAge() else { return }

        // Parse focus areas from notes (simple extraction)
        let trimmedNotes = workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusAreas = parseFocusAreas(from: trimmedNotes)
        let injuryNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let request = WorkoutPlanGenerationRequest(
            name: userName.trimmingCharacters(in: .whitespaces),
            age: age,
            gender: gender ?? .notSpecified,
            goal: selectedGoal ?? .health,
            activityLevel: activityLevel ?? .moderate,
            workoutType: .strength,
            selectedWorkoutTypes: nil,
            experienceLevel: workoutExperienceLevel,
            equipmentAccess: workoutEquipmentAccess,
            availableDays: workoutDaysPerWeek,
            timePerWorkout: workoutTimePerSession,
            preferredSplit: nil,
            cardioTypes: nil,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: focusAreas.isEmpty ? nil : focusAreas,
            weakPoints: nil,
            injuries: injuryNotes,
            preferences: nil
        )

        isGeneratingWorkoutPlan = true

        Task {
            do {
                let plan = try await geminiService.generateWorkoutPlan(request: request)
                generatedWorkoutPlan = plan
            } catch {
                // Fall back to default plan
                let fallbackPlan = WorkoutPlan.createDefault(from: request)
                generatedWorkoutPlan = fallbackPlan
            }
            isGeneratingWorkoutPlan = false
        }
    }

    func parseFocusAreas(from notes: String) -> [String] {
        let lowercased = notes.lowercased()
        var areas: [String] = []

        // Simple keyword matching for common focus areas
        let focusKeywords = [
            ("chest", ["chest", "pecs"]),
            ("back", ["back", "lats"]),
            ("shoulders", ["shoulders", "delts"]),
            ("arms", ["arms", "biceps", "triceps"]),
            ("legs", ["legs", "quads", "hamstrings", "glutes"]),
            ("core", ["core", "abs", "abdominals"]),
            ("upper body", ["upper body", "upper-body"]),
            ("lower body", ["lower body", "lower-body"])
        ]

        for (area, keywords) in focusKeywords {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    areas.append(area)
                    break
                }
            }
        }

        return areas
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
