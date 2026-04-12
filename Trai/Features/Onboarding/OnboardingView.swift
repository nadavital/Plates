//
//  OnboardingView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(MonetizationService.self) var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @State var currentStep = 0
    @State var navigationDirection: NavigationDirection = .forward

    // Step 0: Welcome
    @State var userName = ""

    // Step 1: Biometrics
    // Default: August 4, 2002
    @State var dateOfBirth = Calendar.current.date(from: DateComponents(year: 2002, month: 8, day: 4)) ?? Date()
    @State var gender: UserProfile.Gender?
    @State var heightValue = ""
    @State var weightValue = ""
    @State var targetWeightValue = ""
    @State var usesMetricHeight = true
    @State var usesMetricWeight = true

    // Step 2: Activity Level
    @State var activityLevel: UserProfile.ActivityLevel?
    @State var activityNotes = ""

    // Step 3: Goals
    @State var selectedGoal: UserProfile.GoalType?
    @State var additionalGoalNotes = ""

    // Step 4: Macro Preferences
    @State var enabledMacros: Set<MacroType> = MacroType.defaultEnabled

    enum NavigationDirection {
        case forward, backward
    }

    // Step 5: Summary (review before AI)
    // Step 6: Plan Review
    @State var generatedPlan: NutritionPlan?
    @State var isGeneratingPlan = false
    @State var planError: String?
    @State var adjustedCalories = ""
    @State var adjustedProtein = ""
    @State var adjustedCarbs = ""
    @State var adjustedFat = ""
    @State var lastGeneratedPlanInputSignature: String?
    @State var showingPlanGenerationChoice = false

    // Step 7: Workout Plan (optional)
    @State var generatedWorkoutPlan: WorkoutPlan?
    @State var showingWorkoutSetup = false

    @State var aiService = AIService()

    let totalSteps = 8

    var body: some View {
        ZStack {
            Color.clear

            if showingWorkoutSetup {
                // Embedded workout plan chat flow
                WorkoutPlanChatFlow(
                    isOnboarding: true,
                    embedded: true,
                    onComplete: { plan in
                        generatedWorkoutPlan = plan
                        withAnimation(.smooth(duration: 0.4)) {
                            showingWorkoutSetup = false
                        }
                    },
                    onSkip: {
                        withAnimation(.smooth(duration: 0.4)) {
                            showingWorkoutSetup = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                // Normal onboarding content
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
        .animation(.smooth(duration: 0.4), value: showingWorkoutSetup)
        .onChange(of: currentPlanInputSignature, initial: false) { oldValue, newValue in
            handlePlanInputChange(from: oldValue, to: newValue)
        }
        .onChange(of: monetizationService?.canAccessAIFeatures ?? false, initial: false) { _, hasAccess in
            guard hasAccess, showingPlanGenerationChoice, currentStep == 5 else { return }
            showingPlanGenerationChoice = false
            advanceFromSummaryToPlanReview()
        }
        .sheet(isPresented: $showingPlanGenerationChoice) {
            PlanGenerationChoiceSheet(
                onContinueStandard: {
                    showingPlanGenerationChoice = false
                    advanceFromSummaryToPlanReview()
                }
            )
            .traiSheetBranding()
        }
        .traiBackground()
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
                            .font(.traiLabel(14))
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
            case 7:
                WorkoutPlanDecisionView(
                    hasWorkoutPlan: generatedWorkoutPlan != nil,
                    workoutPlan: generatedWorkoutPlan,
                    onCreatePlan: {
                        guard monetizationService?.canAccessAIFeatures ?? true else {
                            proUpsellCoordinator?.present(source: .workoutPlan, style: .fullScreenCover)
                            return
                        }
                        navigationDirection = .forward
                        withAnimation(.smooth(duration: 0.4)) {
                            showingWorkoutSetup = true
                        }
                    }
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
        .buttonStyle(.traiPrimary(color: canProceed ? .accentColor : .gray, size: .large, fullWidth: true))
        .disabled(!canProceed)
        .animation(.easeInOut(duration: 0.2), value: canProceed)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var primaryButtonText: String {
        switch currentStep {
        case 0: return "Let's Go"
        case 5: return (monetizationService?.canAccessAIFeatures ?? true) ? "Generate My Plan" : "Choose Plan Type"
        case 6: return "Continue"
        case 7: return "Start Your Journey"
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
            return canCompleteNutritionPlan
        case 7:
            return true  // Workout plan is optional
        default:
            return true
        }
    }

    private var canCompleteNutritionPlan: Bool {
        guard generatedPlan != nil && !isGeneratingPlan else { return false }
        guard lastGeneratedPlanInputSignature == currentPlanInputSignature else { return false }
        guard let calories = Int(adjustedCalories), calories > 0 else { return false }
        return true
    }

    // MARK: - Navigation

    private func advanceToNextStep() {
        if currentStep == 5 {
            if monetizationService?.canAccessAIFeatures ?? true {
                advanceFromSummaryToPlanReview()
            } else {
                HapticManager.lightTap()
                showingPlanGenerationChoice = true
            }
            return
        }

        HapticManager.stepCompleted()
        navigationDirection = .forward

        withAnimation(.smooth(duration: 0.4)) {
            currentStep += 1
        }

        // Trigger plan generation when entering the plan review step
        if currentStep == 6 && (generatedPlan == nil || lastGeneratedPlanInputSignature != currentPlanInputSignature) {
            generatePlan()
        }
    }

    private func advanceFromSummaryToPlanReview() {
        HapticManager.stepCompleted()
        navigationDirection = .forward

        withAnimation(.smooth(duration: 0.4)) {
            currentStep = 6
        }

        if generatedPlan == nil || lastGeneratedPlanInputSignature != currentPlanInputSignature {
            generatePlan()
        }
    }

}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
