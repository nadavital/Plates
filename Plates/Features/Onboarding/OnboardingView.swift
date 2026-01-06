//
//  OnboardingView.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var currentStep = 0
    @State private var navigationDirection: NavigationDirection = .forward

    // Step 0: Welcome
    @State private var userName = ""

    // Step 1: Biometrics
    // Default: August 4, 2002
    @State private var dateOfBirth = Calendar.current.date(from: DateComponents(year: 2002, month: 8, day: 4)) ?? Date()
    @State private var gender: UserProfile.Gender?
    @State private var heightValue = ""
    @State private var weightValue = ""
    @State private var targetWeightValue = ""
    @State private var usesMetricHeight = true
    @State private var usesMetricWeight = true

    // Step 2: Activity Level
    @State private var activityLevel: UserProfile.ActivityLevel?
    @State private var activityNotes = ""

    // Step 3: Goals
    @State private var selectedGoal: UserProfile.GoalType?
    @State private var additionalGoalNotes = ""

    // Step 4: Macro Preferences
    @State private var enabledMacros: Set<MacroType> = MacroType.defaultEnabled

    private enum NavigationDirection {
        case forward, backward
    }

    // Step 5: Summary (review before AI)
    // Step 6: Plan Review
    @State private var generatedPlan: NutritionPlan?
    @State private var isGeneratingPlan = false
    @State private var planError: String?
    @State private var adjustedCalories = ""
    @State private var adjustedProtein = ""
    @State private var adjustedCarbs = ""
    @State private var adjustedFat = ""

    @State private var geminiService = GeminiService()

    private let totalSteps = 7

    var body: some View {
        ZStack {
            // Full-screen animated gradient background
            AnimatedGradientBackground()

            // Content
            VStack(spacing: 0) {
                // Top navigation bar
                topNavigationBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Progress indicator
                progressIndicator
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Step content with smooth transitions
                ZStack {
                    stepContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Floating navigation button at bottom
            VStack {
                Spacer()
                floatingNavigationSection
            }
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            if currentStep > 0 && !isGeneratingPlan {
                Button {
                    HapticManager.lightTap()
                    navigationDirection = .backward
                    withAnimation(.smooth(duration: 0.4)) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(height: 32)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                WelcomeStepView(userName: $userName)
            case 1:
                BiometricsStepView(
                    dateOfBirth: $dateOfBirth,
                    gender: $gender,
                    heightValue: $heightValue,
                    weightValue: $weightValue,
                    targetWeightValue: $targetWeightValue,
                    usesMetricHeight: $usesMetricHeight,
                    usesMetricWeight: $usesMetricWeight
                )
            case 2:
                ActivityLevelStepView(
                    activityLevel: $activityLevel,
                    activityNotes: $activityNotes
                )
            case 3:
                GoalsStepView(
                    selectedGoal: $selectedGoal,
                    additionalNotes: $additionalGoalNotes
                )
            case 4:
                MacroPreferencesStepView(enabledMacros: $enabledMacros)
            case 5:
                SummaryStepView(
                    userName: userName,
                    dateOfBirth: dateOfBirth,
                    gender: gender,
                    heightValue: heightValue,
                    weightValue: weightValue,
                    targetWeightValue: targetWeightValue,
                    usesMetricHeight: usesMetricHeight,
                    usesMetricWeight: usesMetricWeight,
                    activityLevel: activityLevel,
                    activityNotes: activityNotes,
                    selectedGoal: selectedGoal,
                    additionalNotes: additionalGoalNotes
                )
            case 6:
                PlanReviewStepView(
                    plan: $generatedPlan,
                    planRequest: buildPlanRequest(),
                    isLoading: isGeneratingPlan,
                    error: planError,
                    adjustedCalories: $adjustedCalories,
                    adjustedProtein: $adjustedProtein,
                    adjustedCarbs: $adjustedCarbs,
                    adjustedFat: $adjustedFat,
                    onRetry: generatePlan
                )
            default:
                EmptyView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: navigationDirection == .forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigationDirection == .forward ? .leading : .trailing).combined(with: .opacity)
        ))
        .animation(.smooth(duration: 0.4), value: currentStep)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                if step == currentStep {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 6)
                } else if step < currentStep {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 14, height: 6)
                } else {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 14, height: 6)
                }
            }
        }
        .animation(.spring(response: 0.4), value: currentStep)
    }

    // MARK: - Floating Navigation Section

    private var floatingNavigationSection: some View {
        Button {
            if currentStep < totalSteps - 1 {
                advanceToNextStep()
            } else {
                completeOnboarding()
            }
        } label: {
            HStack(spacing: 8) {
                Text(primaryButtonText)
                    .fontWeight(.semibold)

                if currentStep < totalSteps - 1 && currentStep != 5 {
                    Image(systemName: "arrow.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(canProceed ? .accentColor : .gray)
        .disabled(!canProceed)
        .animation(.easeInOut(duration: 0.2), value: canProceed)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var primaryButtonText: String {
        switch currentStep {
        case 0: return "Let's Go"
        case 5: return "Generate My Plan"
        case totalSteps - 1: return isGeneratingPlan ? "Creating Plan..." : "Start Your Journey"
        default: return "Continue"
        }
    }

    // MARK: - Validation

    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return !userName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1:
            return !weightValue.isEmpty && !heightValue.isEmpty
        case 2:
            return activityLevel != nil
        case 3:
            return selectedGoal != nil
        case 4:
            return true // Macro preferences step (always valid)
        case 5:
            return true // Summary step
        case 6:
            return canComplete
        default:
            return true
        }
    }

    private var canComplete: Bool {
        guard generatedPlan != nil && !isGeneratingPlan else { return false }
        guard let calories = Int(adjustedCalories), calories > 0 else { return false }
        return true
    }

    // MARK: - Navigation

    private func advanceToNextStep() {
        HapticManager.stepCompleted()
        navigationDirection = .forward

        withAnimation(.smooth(duration: 0.4)) {
            currentStep += 1
        }

        // Trigger plan generation when entering the plan review step
        if currentStep == 6 {
            generatePlan()
        }
    }

    // MARK: - Plan Generation

    private func generatePlan() {
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

    private func populateAdjustedValues(from plan: NutritionPlan) {
        adjustedCalories = String(plan.dailyTargets.calories)
        adjustedProtein = String(plan.dailyTargets.protein)
        adjustedCarbs = String(plan.dailyTargets.carbs)
        adjustedFat = String(plan.dailyTargets.fat)
    }

    // MARK: - Parsing Helpers

    private func calculateAge() -> Int? {
        let components = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date())
        return components.year
    }

    private func parseHeight() -> Double? {
        guard let value = Double(heightValue) else { return nil }
        return usesMetricHeight ? value : value * 2.54
    }

    private func parseWeight(_ value: String) -> Double? {
        guard !value.isEmpty, let parsed = Double(value) else { return nil }
        return usesMetricWeight ? parsed : parsed * 0.453592
    }

    private func buildPlanRequest() -> PlanGenerationRequest? {
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

    // MARK: - Complete Onboarding

    private func completeOnboarding() {
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

        profile.hasCompletedOnboarding = true
        modelContext.insert(profile)

        // Create memories from user notes
        createMemoriesFromNotes()
    }

    // MARK: - Memory Creation

    private func createMemoriesFromNotes() {
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

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
