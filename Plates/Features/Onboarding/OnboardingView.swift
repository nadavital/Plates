//
//  OnboardingView.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) var modelContext
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

    // Step 7: Workout Plan (optional)
    @State var wantsWorkoutPlan: Bool?
    @State var generatedWorkoutPlan: WorkoutPlan?
    @State var isGeneratingWorkoutPlan = false
    @State var workoutDaysPerWeek: Int = 3
    @State var workoutExperienceLevel: WorkoutPlanGenerationRequest.ExperienceLevel = .beginner
    @State var workoutEquipmentAccess: WorkoutPlanGenerationRequest.EquipmentAccess = .fullGym
    @State var workoutTimePerSession: Int = 45
    @State var workoutNotes: String = ""

    @State var geminiService = GeminiService()

    let totalSteps = 8

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
            case 7:
                WorkoutPlanOnboardingStepView(
                    wantsWorkoutPlan: $wantsWorkoutPlan,
                    workoutPlan: $generatedWorkoutPlan,
                    daysPerWeek: $workoutDaysPerWeek,
                    experienceLevel: $workoutExperienceLevel,
                    equipmentAccess: $workoutEquipmentAccess,
                    timePerSession: $workoutTimePerSession,
                    workoutNotes: $workoutNotes,
                    userProfile: buildPlanRequest(),
                    isGenerating: isGeneratingWorkoutPlan,
                    onGenerate: generateWorkoutPlan
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
        case 6: return "Continue"
        case 7:
            if wantsWorkoutPlan == false {
                return "Start Your Journey"
            } else if wantsWorkoutPlan == true && generatedWorkoutPlan != nil {
                return "Start Your Journey"
            } else {
                return "Continue"
            }
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
            return canCompleteWorkoutStep
        default:
            return true
        }
    }

    private var canCompleteNutritionPlan: Bool {
        guard generatedPlan != nil && !isGeneratingPlan else { return false }
        guard let calories = Int(adjustedCalories), calories > 0 else { return false }
        return true
    }

    private var canCompleteWorkoutStep: Bool {
        // User hasn't decided yet
        if wantsWorkoutPlan == nil {
            return false
        }
        // User skipped workout plan
        if wantsWorkoutPlan == false {
            return true
        }
        // User wants workout plan - must have generated one
        return generatedWorkoutPlan != nil && !isGeneratingWorkoutPlan
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

}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
