//
//  GoalsStepView.swift
//  Trai
//

import SwiftUI

struct GoalsStepView: View {
    @Binding var selectedGoal: UserProfile.GoalType?
    @Binding var additionalNotes: String

    private var availableGoals: [UserProfile.GoalType] {
        [.loseWeight, .loseFat, .buildMuscle, .recomposition, .maintenance, .performance]
    }

    @State private var headerVisible = false
    @State private var goalsVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerSection
                    .padding(.top, 12)

                goalsSection
                    .offset(y: goalsVisible ? 0 : 24)
                    .opacity(goalsVisible ? 1 : 0)

                if selectedGoal != nil {
                    selectedGoalResponse
                        .opacity(goalsVisible ? 1 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startEntranceAnimations()
        }
    }

    private func startEntranceAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
            goalsVisible = true
        }
    }

    private var headerSection: some View {
        OnboardingTraiHeader(
            title: "Choose your goal.",
            lensSize: 52
        )
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    private var goalsSection: some View {
        GlassEffectContainer(spacing: 12) {
            goalGrid
        }
    }

    private var goalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(availableGoals) { goal in
                GoalCard(
                    goal: goal,
                    isSelected: selectedGoal == goal
                ) {
                    HapticManager.cardSelected()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedGoal = goal
                    }
                }
            }
        }
    }

    private var selectedGoalResponse: some View {
        HStack(alignment: .top) {
            Text(selectedGoal.map(responseText) ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .onboardingTraiResponseCard()
        .animation(.smooth(duration: 0.3), value: selectedGoal)
    }

    private func responseText(for goal: UserProfile.GoalType) -> String {
        switch goal {
        case .loseWeight:
            return "I’ll start with a steady deficit so weight trends down without making the target feel extreme."
        case .loseFat:
            return "I’ll keep protein higher and create a gradual deficit, so the focus is fat loss while protecting muscle."
        case .buildMuscle:
            return "I’ll bias your plan toward muscle growth, which usually means intentionally gaining some scale weight. If you want to stay closer to your current weight, recomposition may fit better."
        case .recomposition:
            return "I’ll keep you closer to maintenance while prioritizing strength and protein, so the focus is getting leaner and stronger without chasing scale gain."
        case .maintenance:
            return "I’ll aim for consistency and steady energy without pushing your weight up or down."
        case .performance:
            return "I’ll prioritize enough fuel for training, recovery, and better output instead of a strict weight-change target."
        case .health:
            return "I’ll build a balanced starting point for everyday nutrition."
        }
    }

}

#Preview {
    GoalsStepView(
        selectedGoal: .constant(.loseWeight),
        additionalNotes: .constant("")
    )
}
