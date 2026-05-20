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
    @Environment(AccountSessionService.self) var accountSessionService: AccountSessionService?
    @Environment(HealthKitService.self) var healthKitService: HealthKitService?
    @Environment(MonetizationService.self) var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @State var currentStep = 0
    @State var navigationDirection: NavigationDirection = .forward
    @State var hasRestoredDraft = false

    // Step 0: Splash / account
    @State var userName = ""

    // Goal and body setup
    @State var selectedGoal: UserProfile.GoalType?
    @State var additionalGoalNotes = ""

    // Biometrics
    // Default: August 4, 2002
    @State var dateOfBirth = Calendar.current.date(from: DateComponents(year: 2002, month: 8, day: 4)) ?? Date()
    @State var gender: UserProfile.Gender?
    @State var heightValue = {
        #if DEBUG
        AppLaunchArguments.shouldRunOnboardingFlowUITest ? "170" : ""
        #else
        ""
        #endif
    }()
    @State var weightValue = {
        #if DEBUG
        AppLaunchArguments.shouldRunOnboardingFlowUITest ? "155" : ""
        #else
        ""
        #endif
    }()
    @State var targetWeightValue = ""
    @State var usesMetricHeight = true
    @State var usesMetricWeight = false

    // Activity Level
    @State var activityLevel: UserProfile.ActivityLevel?
    @State var activityNotes = ""

    // Nutrition setup. First-run onboarding always creates a starter target plan.
    @State var enabledMacros: Set<MacroType> = MacroType.defaultEnabled

    // Post-onboarding setup can still opt into Apple Health.
    @State var syncFoodToHealthKit = false
    @State var syncWeightToHealthKit = false
    @State var isRequestingHealthAccess = false
    @State var healthSyncError: String?

    enum NavigationDirection {
        case forward, backward
    }

    // Step 7: Summary (review before AI)
    // Step 8: Plan Review
    @State var generatedPlan: NutritionPlan?
    @State var isGeneratingPlan = false
    @State var planError: String?
    @State var adjustedCalories = ""
    @State var adjustedProtein = ""
    @State var adjustedCarbs = ""
    @State var adjustedFat = ""
    @State var lastGeneratedPlanInputSignature: String?
    @State var showingPlanGenerationChoice = false

    // Step 9: Workout Plan (optional)
    @State var generatedWorkoutPlan: WorkoutPlan?
    @State var generatedWorkoutGoals: [WorkoutGoal] = []
    @State var showingWorkoutSetup = false
    @State var workoutPlanDraft = OnboardingWorkoutPlanDraft()

    @State var aiService = AIService()

    var onboardingSteps: [OnboardingStepID] {
        OnboardingFlowPlanner.steps()
    }

    var totalSteps: Int {
        onboardingSteps.count
    }

    var currentStepID: OnboardingStepID {
        onboardingSteps[min(currentStep, max(totalSteps - 1, 0))]
    }

    var shouldCollectTargetWeight: Bool {
        selectedGoal?.shouldCollectTargetWeight ?? false
    }

    var workoutPlanUserContext: OnboardingWorkoutPlanUserContext {
        OnboardingWorkoutPlanUserContext(
            name: resolvedProfileName,
            age: calculateAge() ?? 30,
            gender: gender ?? .notSpecified,
            goal: selectedGoal ?? .health,
            activityLevel: activityLevel ?? .moderate,
            nutritionContext: workoutPlanNutritionContext
        )
    }

    var workoutPlanNutritionContext: [String] {
        var context = [
            "Nutrition goal: \((selectedGoal ?? .health).displayName)"
        ]

        let calories = Int(adjustedCalories) ?? generatedPlan?.dailyTargets.calories
        let protein = Int(adjustedProtein) ?? generatedPlan?.dailyTargets.protein
        let carbs = Int(adjustedCarbs) ?? generatedPlan?.dailyTargets.carbs
        let fat = Int(adjustedFat) ?? generatedPlan?.dailyTargets.fat
        if let calories, let protein, let carbs, let fat {
            context.append("Daily targets: \(calories) calories, \(protein)g protein, \(carbs)g carbs, \(fat)g fat")
        }

        let trimmedActivityNotes = activityNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedActivityNotes.isEmpty {
            context.append("Activity notes: \(trimmedActivityNotes)")
        }

        let trimmedGoalNotes = additionalGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGoalNotes.isEmpty {
            context.append("Goal notes from onboarding: \(trimmedGoalNotes)")
        }

        if let generatedPlan {
            context.append("Nutrition plan rationale: \(generatedPlan.rationale)")
            if let adjustment = generatedPlan.weeklyAdjustments?.recommendation, !adjustment.isEmpty {
                context.append("Nutrition weekly adjustment: \(adjustment)")
            }
            if let milestone = generatedPlan.progressInsights?.shortTermMilestone, !milestone.isEmpty {
                context.append("Nutrition milestone: \(milestone)")
            }
        }

        return context
    }

    var body: some View {
        ZStack {
            OnboardingAmbientBackground()

            if showingWorkoutSetup {
                OnboardingWorkoutPlanSetupView(
                    draft: $workoutPlanDraft,
                    context: workoutPlanUserContext,
                    aiService: aiService,
                    onComplete: { plan, goals in
                        generatedWorkoutPlan = plan
                        generatedWorkoutGoals = goals
                        withAnimation(.smooth(duration: 0.4)) {
                            showingWorkoutSetup = false
                        }
                    },
                    onBack: {
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
                    if currentStepID != .welcome {
                        // Top navigation bar
                        topNavigationBar
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // Progress indicator
                        progressIndicator
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }

                    // Step content with smooth transitions
                    ZStack {
                        stepContent
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Floating navigation button at bottom
                VStack {
                    Spacer()
                    if currentStepID != .welcome {
                        floatingNavigationSection
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.4), value: showingWorkoutSetup)
        .onAppear {
            restoreDraftIfNeeded()
        }
        .onChange(of: onboardingDraftSnapshot, initial: false) { _, _ in
            persistOnboardingDraft()
        }
        .onChange(of: currentPlanInputSignature, initial: false) { oldValue, newValue in
            handlePlanInputChange(from: oldValue, to: newValue)
        }
        .onChange(of: selectedGoal, initial: false) { _, goal in
            if !(goal?.shouldCollectTargetWeight ?? false) {
                targetWeightValue = ""
            }
        }
        .onChange(of: monetizationService?.canAccessAIFeatures ?? false, initial: false) { _, hasAccess in
            guard hasAccess, showingPlanGenerationChoice, isWaitingToEnterNutritionPlan else { return }
            showingPlanGenerationChoice = false
            advanceToNutritionPlan()
        }
        .sheet(isPresented: $showingPlanGenerationChoice) {
            PlanGenerationChoiceSheet(
                onContinueStandard: {
                    showingPlanGenerationChoice = false
                    advanceToNutritionPlan()
                }
            )
            .traiSheetBranding()
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
            switch currentStepID {
            case .welcome:
                WelcomeStepView(onContinue: advanceToNextStep)
            case .goals:
                GoalsStepView(
                    selectedGoal: $selectedGoal,
                    additionalNotes: $additionalGoalNotes
                )
            case .biometrics:
                BiometricsStepView(
                    dateOfBirth: $dateOfBirth,
                    gender: $gender,
                    heightValue: $heightValue,
                    weightValue: $weightValue,
                    targetWeightValue: $targetWeightValue,
                    usesMetricHeight: $usesMetricHeight,
                    usesMetricWeight: $usesMetricWeight,
                    showsTargetWeight: shouldCollectTargetWeight
                )
            case .activity:
                ActivityLevelStepView(
                    activityLevel: $activityLevel,
                    activityNotes: $activityNotes
                )
            case .summary:
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
            case .nutritionPlan:
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
            case .macroPreferences, .account, .health, .workoutSetup:
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
            ForEach(onboardingSteps.indices, id: \.self) { step in
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

                if currentStep < totalSteps - 1 && currentStepID != .summary {
                    Image(systemName: "arrow.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.traiPrimary(color: canProceed ? .accentColor : .gray, size: .large, fullWidth: true))
        .accessibilityIdentifier("onboardingPrimaryButton")
        .disabled(!canProceed)
        .animation(.easeInOut(duration: 0.2), value: canProceed)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var primaryButtonText: String {
        switch currentStepID {
        case .welcome: return "Continue"
        case .summary:
            return (monetizationService?.canAccessAIFeatures ?? true) ? "Build My Plan" : "See Trai Pro"
        case .activity:
            return "Build My Plan"
        case .nutritionPlan: return "Start Using Trai"
        case .workoutSetup: return "Start Using Trai"
        default: return "Continue"
        }
    }

    // MARK: - Validation

    private var canProceed: Bool {
        switch currentStepID {
        case .welcome:
            #if DEBUG
            if AppLaunchArguments.shouldRunOnboardingFlowUITest {
                return true
            }
            #endif
            return accountSessionService?.isAuthenticated == true
        case .goals:
            return selectedGoal != nil
        case .biometrics:
            return !weightValue.isEmpty && !heightValue.isEmpty
        case .activity:
            return activityLevel != nil
        case .macroPreferences:
            return true
        case .account:
            return true
        case .health:
            return true
        case .summary:
            return true
        case .nutritionPlan:
            return canCompleteNutritionPlan
        case .workoutSetup:
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
        if nextStepID == .nutritionPlan {
            if monetizationService?.canAccessAIFeatures ?? true {
                advanceToNutritionPlan()
            } else {
                HapticManager.lightTap()
                showingPlanGenerationChoice = true
            }
            return
        }

        if currentStepID == .summary {
            if monetizationService?.canAccessAIFeatures ?? true {
                advanceToNutritionPlan()
            } else {
                HapticManager.lightTap()
                showingPlanGenerationChoice = true
            }
            return
        }

        HapticManager.stepCompleted()
        navigationDirection = .forward

        withAnimation(.smooth(duration: 0.4)) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }

        if currentStepID == .nutritionPlan && (generatedPlan == nil || lastGeneratedPlanInputSignature != currentPlanInputSignature) {
            generatePlan()
        }
    }

    private var nextStepID: OnboardingStepID? {
        let nextIndex = currentStep + 1
        guard onboardingSteps.indices.contains(nextIndex) else { return nil }
        return onboardingSteps[nextIndex]
    }

    private var isWaitingToEnterNutritionPlan: Bool {
        nextStepID == .nutritionPlan || currentStepID == .summary
    }

    private func advanceToNutritionPlan() {
        HapticManager.stepCompleted()
        navigationDirection = .forward

        withAnimation(.smooth(duration: 0.4)) {
            currentStep = stepIndex(for: .nutritionPlan) ?? min(currentStep + 1, totalSteps - 1)
        }

        if generatedPlan == nil || lastGeneratedPlanInputSignature != currentPlanInputSignature {
            generatePlan()
        }
    }

    private func stepIndex(for step: OnboardingStepID) -> Int? {
        onboardingSteps.firstIndex(of: step)
    }

    private func clampCurrentStepToAvailableFlow() {
        currentStep = min(currentStep, max(totalSteps - 1, 0))
    }

    private func requestHealthAuthorization() {
        guard !isRequestingHealthAccess else { return }

        healthSyncError = nil

        guard let healthKitService else {
            healthSyncError = "Apple Health is unavailable on this device."
            return
        }

        isRequestingHealthAccess = true

        Task { @MainActor in
            defer { isRequestingHealthAccess = false }

            do {
                try await healthKitService.requestAuthorization()
                healthSyncError = nil
            } catch {
                healthSyncError = healthKitService.authorizationError ?? error.localizedDescription
            }
        }
    }

}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}

enum OnboardingStepID: Equatable {
    case welcome
    case goals
    case biometrics
    case activity
    case macroPreferences
    case account
    case health
    case summary
    case nutritionPlan
    case workoutSetup
}

enum OnboardingFlowPlanner {
    static func steps() -> [OnboardingStepID] {
        [
            .welcome,
            .goals,
            .biometrics,
            .activity,
            .nutritionPlan
        ]
    }
}
