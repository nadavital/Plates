//
//  PlanReviewStepView.swift
//  Plates
//

import SwiftUI

struct PlanReviewStepView: View {
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

    private var planBinding: Binding<NutritionPlan> {
        Binding(
            get: { plan ?? NutritionPlan.placeholder },
            set: { plan = $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        loadingSection
                    } else if let error {
                        errorSection(error)
                    } else if let plan {
                        successHeader
                            .offset(y: headerVisible ? 0 : -20)
                            .opacity(headerVisible ? 1 : 0)

                        planContent(plan)
                            .padding(.bottom, 160)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            if plan != nil && planRequest != nil && !isLoading {
                floatingAskButton
                    .offset(y: headerVisible ? 0 : 50)
                    .opacity(headerVisible ? 1 : 0)
            }
        }
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
            }
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

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 50)

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .modifier(PulsingModifier())

                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        AngularGradient(
                            colors: [.accentColor, .purple, .accentColor.opacity(0.3)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .modifier(RotatingModifier())

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 45
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .modifier(SparkleModifier())
            }

            VStack(spacing: 10) {
                Text("Crafting Your Plan")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Trai is analyzing your profile and\ncreating a personalized nutrition strategy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                LoadingStep(text: "Calculating metabolism", stepIndex: 0)
                LoadingStep(text: "Optimizing macros", stepIndex: 1)
                LoadingStep(text: "Personalizing recommendations", stepIndex: 2)
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
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(.rect(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Success Header

    private var successHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Your Plan is Ready!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Review your personalized targets below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Floating Ask Button

    private var floatingAskButton: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.lightTap()
                showChat = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.subheadline)

                    Text("Ask About Your Plan")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.purple)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 70)
    }

    // MARK: - Plan Content

    private func planContent(_ plan: NutritionPlan) -> some View {
        VStack(spacing: 18) {
            DailyTargetsCard(
                adjustedCalories: $adjustedCalories,
                adjustedProtein: $adjustedProtein,
                adjustedCarbs: $adjustedCarbs,
                adjustedFat: $adjustedFat
            )
            .offset(y: card1Visible ? 0 : 30)
            .opacity(card1Visible ? 1 : 0)

            RationaleCard(rationale: plan.rationale)
                .offset(y: card2Visible ? 0 : 30)
                .opacity(card2Visible ? 1 : 0)

            if let insights = plan.progressInsights {
                ProgressInsightsCard(insights: insights)
                    .offset(y: card3Visible ? 0 : 30)
                    .opacity(card3Visible ? 1 : 0)
            }

            MacroVisualizationCard(split: plan.macroSplit)
                .offset(y: card4Visible ? 0 : 30)
                .opacity(card4Visible ? 1 : 0)

            if !plan.nutritionGuidelines.isEmpty {
                GuidelinesCard(guidelines: plan.nutritionGuidelines)
                    .offset(y: card5Visible ? 0 : 30)
                    .opacity(card5Visible ? 1 : 0)
            }

            if let warnings = plan.warnings, !warnings.isEmpty {
                WarningsCard(warnings: warnings)
                    .offset(y: card5Visible ? 0 : 30)
                    .opacity(card5Visible ? 1 : 0)
            }
        }
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
        additionalNotes: ""
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
