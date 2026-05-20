//
//  PlanReviewStepView.swift
//  Trai
//

import SwiftUI

struct PlanReviewStepView: View {
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @Binding var plan: NutritionPlan?
    let planRequest: PlanGenerationRequest?
    let isLoading: Bool
    let error: String?

    @Binding var adjustedCalories: String
    @Binding var adjustedProtein: String
    @Binding var adjustedCarbs: String
    @Binding var adjustedFat: String

    let onRetry: () -> Void

    @State private var showConfetti = false
    @State private var showChat = false
    @State private var headerVisible = false
    @State private var card1Visible = false
    @State private var card2Visible = false
    @State private var card3Visible = false
    @State private var card4Visible = false
    @State private var card5Visible = false
    @State private var presentedAccountSetupContext: AccountSetupContext?
    @State private var showingNutritionUpsell = false

    private var planBinding: Binding<NutritionPlan> {
        Binding(
            get: { plan ?? NutritionPlan.placeholder },
            set: { plan = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if isLoading {
                    loadingSection
                } else if let error {
                    errorSection(error)
                } else if let plan {
                    successHeader
                        .offset(y: headerVisible ? 0 : -20)
                        .opacity(headerVisible ? 1 : 0)

                    planContent(plan)
                        .padding(.bottom, 140)
                } else {
                    errorSection("Something went wrong generating your plan. Please try again.")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .overlay {
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if plan != nil && !isLoading {
                triggerCelebration()
            }
        }
        .onChange(of: isLoading, initial: false) { _, loading in
            if loading {
                resetCelebrationState()
            }
        }
        .onChange(of: plan != nil, initial: false) { _, hasPlan in
            if hasPlan && !isLoading {
                triggerCelebration()
            }
        }
        .sheet(isPresented: $showChat) {
            if let request = planRequest {
                PlanChatView(
                    currentPlan: planBinding,
                    request: request,
                    onPlanUpdated: { newPlan in
                        adjustedCalories = String(newPlan.dailyTargets.calories)
                        adjustedProtein = String(newPlan.dailyTargets.protein)
                        adjustedCarbs = String(newPlan.dailyTargets.carbs)
                        adjustedFat = String(newPlan.dailyTargets.fat)
                    }
                )
                .traiSheetBranding()
            }
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
        .fullScreenCover(isPresented: $showingNutritionUpsell) {
            ProUpsellView(source: .nutritionPlan)
                .traiSheetBranding()
        }
    }

    // MARK: - Celebration

    private func triggerCelebration() {
        HapticManager.planReady()

        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
            card1Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.25)) {
            card2Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.35)) {
            card3Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.45)) {
            card4Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.55)) {
            card5Visible = true
        }

        withAnimation(.spring(response: 0.6).delay(0.5)) {
            showConfetti = true
        }

        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                showConfetti = false
            }
        }
    }

    private func resetCelebrationState() {
        headerVisible = false
        card1Visible = false
        card2Visible = false
        card3Visible = false
        card4Visible = false
        card5Visible = false
        showConfetti = false
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 50)

            TraiLensView(size: 70, state: .answering, palette: .energy)

            VStack(spacing: 10) {
                Text((monetizationService?.canAccessAIFeatures ?? true) ? "Building Your Plan" : "Setting Up Your Plan")
                    .font(.traiBold(26))

                Text((monetizationService?.canAccessAIFeatures ?? true)
                     ? "Trai is turning your answers into daily targets."
                     : "Trai is preparing a standard nutrition starting point.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                LoadingStep(text: "Reviewing your profile", stepIndex: 0)
                LoadingStep(text: "Calculating daily targets", stepIndex: 1)
                LoadingStep(text: "Preparing your first plan", stepIndex: 2)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer()
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Couldn't Generate Plan")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiPrimary(fullWidth: true))
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Success Header

    private var successHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Your Plan is Ready")
                    .font(.traiBold(26))

                Text("Start logging. Trai will learn from what you do next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 14)
    }

    // MARK: - Floating Ask Button

    private var floatingAskButton: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.lightTap()
                if monetizationService?.canAccessAIFeatures ?? true {
                    showChat = true
                } else if accountSessionService?.isAuthenticated != true {
                    presentedAccountSetupContext = .billing
                } else {
                    showingNutritionUpsell = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: (monetizationService?.canAccessAIFeatures ?? true) ? "bubble.left.and.sparkles.fill" : "sparkles")
                        .font(.subheadline.weight(.semibold))

                    Text((monetizationService?.canAccessAIFeatures ?? true) ? "Ask Trai About Your Plan" : "Unlock Trai Plan Coaching")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.traiPrimary(color: .accentColor, fullWidth: true))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Plan Content

    private func planContent(_ plan: NutritionPlan) -> some View {
        VStack(spacing: 14) {
            DailyTargetsCard(
                adjustedCalories: $adjustedCalories,
                adjustedProtein: $adjustedProtein,
                adjustedCarbs: $adjustedCarbs,
                adjustedFat: $adjustedFat
            )
            .offset(y: card1Visible ? 0 : 30)
            .opacity(card1Visible ? 1 : 0)

            planReadyNudge(plan)
                .offset(y: card4Visible ? 0 : 30)
                .opacity(card4Visible ? 1 : 0)
        }
    }

    private func planReadyNudge(_ plan: NutritionPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(.accent)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text(plan.progressInsights?.shortTermMilestone ?? "Your first goal is simple: log your next meal and let Trai calibrate from there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    @Previewable @State var samplePlan: NutritionPlan? = NutritionPlan(
        dailyTargets: .init(calories: 2100, protein: 165, carbs: 210, fat: 70, fiber: 30),
        rationale: "Based on your goal of building muscle while maintaining a moderate activity level.",
        macroSplit: .init(proteinPercent: 30, carbsPercent: 40, fatPercent: 30),
        nutritionGuidelines: ["Aim for 30-40g protein per meal", "Time carbs around workouts"],
        mealTimingSuggestion: "4 meals, evenly spaced",
        weeklyAdjustments: nil,
        warnings: ["Monitor weight weekly"],
        progressInsights: .init(
            estimatedWeeklyChange: "+0.2 kg",
            estimatedTimeToGoal: nil,
            calorieDeficitOrSurplus: 300,
            shortTermMilestone: "Focus on progressive overload",
            longTermOutlook: "Gradual strength and muscle gains"
        )
    )

    let sampleRequest = PlanGenerationRequest(
        name: "John",
        age: 25,
        gender: .male,
        heightCm: 180,
        weightKg: 80,
        targetWeightKg: 75,
        activityLevel: .moderate,
        activityNotes: "",
        goal: .buildMuscle,
        additionalNotes: "",
        enabledMacros: MacroType.defaultEnabled
    )

    PlanReviewStepView(
        plan: $samplePlan,
        planRequest: sampleRequest,
        isLoading: false,
        error: nil,
        adjustedCalories: .constant("2100"),
        adjustedProtein: .constant("165"),
        adjustedCarbs: .constant("210"),
        adjustedFat: .constant("70"),
        onRetry: {}
    )
}
