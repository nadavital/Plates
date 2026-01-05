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
                            .padding(.bottom, 160) // Space for floating buttons
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            // Floating ask button
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
                        // Update the adjusted values to match new plan
                        adjustedCalories = String(newPlan.dailyTargets.calories)
                        adjustedProtein = String(newPlan.dailyTargets.protein)
                        adjustedCarbs = String(newPlan.dailyTargets.carbs)
                        adjustedFat = String(newPlan.dailyTargets.fat)
                    }
                )
            }
        }
    }

    private func triggerCelebration() {
        HapticManager.planReady()

        // Staggered content reveal
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

        // Hide confetti after animation
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

            // Enhanced animated loading indicator
            ZStack {
                // Outer pulsing ring
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .modifier(PulsingModifier())

                // Middle ring
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                // Rotating gradient ring
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

                // Inner glow
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

                // Dumbbell icon with bounce
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

            // Enhanced loading steps
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
        .padding(.bottom, 70) // Above the main floating button
    }

    // MARK: - Plan Content

    private func planContent(_ plan: NutritionPlan) -> some View {
        VStack(spacing: 18) {
            // Main targets card
            dailyTargetsCard(plan)
                .offset(y: card1Visible ? 0 : 30)
                .opacity(card1Visible ? 1 : 0)

            // Rationale
            rationaleCard(plan.rationale)
                .offset(y: card2Visible ? 0 : 30)
                .opacity(card2Visible ? 1 : 0)

            // Progress insights
            if let insights = plan.progressInsights {
                progressInsightsCard(insights)
                    .offset(y: card3Visible ? 0 : 30)
                    .opacity(card3Visible ? 1 : 0)
            }

            // Macro visualization
            macroVisualization(plan.macroSplit)
                .offset(y: card4Visible ? 0 : 30)
                .opacity(card4Visible ? 1 : 0)

            // Guidelines
            if !plan.nutritionGuidelines.isEmpty {
                guidelinesCard(plan.nutritionGuidelines)
                    .offset(y: card5Visible ? 0 : 30)
                    .opacity(card5Visible ? 1 : 0)
            }

            // Warnings
            if let warnings = plan.warnings, !warnings.isEmpty {
                warningsCard(warnings)
                    .offset(y: card5Visible ? 0 : 30)
                    .opacity(card5Visible ? 1 : 0)
            }
        }
    }

    // MARK: - Progress Insights Card

    private func progressInsightsCard(_ insights: NutritionPlan.ProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Progress Timeline", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

            // Weekly change highlight
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Change")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(insights.estimatedWeeklyChange)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(weeklyChangeColor(insights.calorieDeficitOrSurplus))
                }

                Spacer()

                if let timeToGoal = insights.estimatedTimeToGoal {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Time to Goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(timeToGoal)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))

            // Deficit/Surplus indicator
            HStack(spacing: 8) {
                Image(systemName: insights.calorieDeficitOrSurplus < 0 ? "arrow.down.circle.fill" : insights.calorieDeficitOrSurplus > 0 ? "arrow.up.circle.fill" : "equal.circle.fill")
                    .foregroundStyle(weeklyChangeColor(insights.calorieDeficitOrSurplus))

                Text(deficitSurplusText(insights.calorieDeficitOrSurplus))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Milestones
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("First Month")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Text(insights.shortTermMilestone)
                            .font(.subheadline)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long-Term Outlook")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Text(insights.longTermOutlook)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func weeklyChangeColor(_ deficitOrSurplus: Int) -> Color {
        if deficitOrSurplus < -100 {
            return .green // Losing weight
        } else if deficitOrSurplus > 100 {
            return .blue // Gaining (muscle building)
        } else {
            return .primary // Maintenance
        }
    }

    private func deficitSurplusText(_ value: Int) -> String {
        if value < 0 {
            return "\(abs(value)) calorie deficit per day"
        } else if value > 0 {
            return "\(value) calorie surplus per day"
        } else {
            return "Maintenance calories"
        }
    }

    // MARK: - Daily Targets Card

    private func dailyTargetsCard(_ plan: NutritionPlan) -> some View {
        VStack(spacing: 20) {
            HStack {
                Label("Daily Targets", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Text("Tap to edit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Calories - big and prominent
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("", text: $adjustedCalories)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 160)

                    Text("kcal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Daily Calories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            Divider()

            // Macros
            HStack(spacing: 16) {
                MacroEditField(
                    value: $adjustedProtein,
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )

                MacroEditField(
                    value: $adjustedCarbs,
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )

                MacroEditField(
                    value: $adjustedFat,
                    label: "Fat",
                    color: .yellow,
                    icon: "f.circle.fill"
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 20))
    }

    // MARK: - Rationale Card

    private func rationaleCard(_ rationale: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Why This Plan", systemImage: "lightbulb.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)

            Text(rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Macro Visualization

    private func macroVisualization(_ split: NutritionPlan.MacroSplit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Macro Split", systemImage: "chart.pie.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)

            // Visual bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(split.proteinPercent) / 100)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(split.carbsPercent) / 100)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(split.fatPercent) / 100)
                }
            }
            .frame(height: 12)
            .clipShape(.rect(cornerRadius: 6))

            // Legend
            HStack(spacing: 20) {
                MacroLegend(label: "Protein", percent: split.proteinPercent, color: .blue)
                MacroLegend(label: "Carbs", percent: split.carbsPercent, color: .green)
                MacroLegend(label: "Fat", percent: split.fatPercent, color: .yellow)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Guidelines Card

    private func guidelinesCard(_ guidelines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tips for Success", systemImage: "star.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.mint)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(guidelines, id: \.self) { guideline in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text(guideline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Warnings Card

    private func warningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep in Mind", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Supporting Views

struct MacroEditField: View {
    @Binding var value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            HStack(spacing: 2) {
                TextField("", text: $value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)

                Text("g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct MacroLegend: View {
    let label: String
    let percent: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text("\(label) \(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LoadingStep: View {
    let text: String
    let stepIndex: Int

    @State private var dotCount = 0
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 28, height: 28)

                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(text + String(repeating: ".", count: dotCount))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -20)
        .onAppear {
            // Staggered appearance
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(stepIndex) * 0.15)) {
                isVisible = true
            }

            // Animate dots
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

struct RotatingModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct PulsingModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(2 - scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    scale = 1.3
                }
            }
    }
}

struct SparkleModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.1
                }
            }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                createParticles(in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func createParticles(in size: CGSize) {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

        for _ in 0..<50 {
            let startX = CGFloat.random(in: 0...size.width)
            let particle = ConfettiParticle(
                position: CGPoint(x: startX, y: -20),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 6...12)
            )
            particles.append(particle)
        }

        // Animate particles falling
        for index in particles.indices {
            let delay = Double.random(in: 0...0.5)
            let duration = Double.random(in: 1.5...2.5)

            withAnimation(.easeIn(duration: duration).delay(delay)) {
                particles[index].position.y = size.height + 50
                particles[index].position.x += CGFloat.random(in: -100...100)
            }

            withAnimation(.easeIn(duration: duration * 0.8).delay(delay + duration * 0.5)) {
                particles[index].opacity = 0
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double = 1
}

#Preview {
    @Previewable @State var samplePlan: NutritionPlan? = NutritionPlan(
        dailyTargets: .init(calories: 2100, protein: 165, carbs: 210, fat: 70, fiber: 30),
        rationale: "Based on your goal of building muscle while maintaining a moderate activity level, we've set you at a slight caloric surplus with high protein to support muscle growth.",
        macroSplit: .init(proteinPercent: 30, carbsPercent: 40, fatPercent: 30),
        nutritionGuidelines: [
            "Aim for 30-40g protein per meal",
            "Time carbs around workouts",
            "Include healthy fats from whole foods"
        ],
        mealTimingSuggestion: "4 meals, evenly spaced throughout the day",
        weeklyAdjustments: nil,
        warnings: ["Monitor weight weekly and adjust if needed"],
        progressInsights: .init(
            estimatedWeeklyChange: "+0.2 kg",
            estimatedTimeToGoal: nil,
            calorieDeficitOrSurplus: 300,
            shortTermMilestone: "Focus on progressive overload in your first 4 weeks",
            longTermOutlook: "Gradual strength and muscle gains with minimal fat gain"
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
        dietaryRestrictions: [],
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
