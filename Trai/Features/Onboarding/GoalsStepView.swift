//
//  GoalsStepView.swift
//  Trai
//

import SwiftUI

struct GoalsStepView: View {
    @Binding var selectedGoal: UserProfile.GoalType?
    @Binding var additionalNotes: String

    /// Filtered goals (6 instead of 7 - removed "health" as too generic)
    private var availableGoals: [UserProfile.GoalType] {
        [.loseWeight, .loseFat, .buildMuscle, .recomposition, .maintenance, .performance]
    }

    @State private var headerVisible = false
    @State private var goalsVisible = false
    @State private var notesVisible = false
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 16)

                    goalsSection
                        .offset(y: goalsVisible ? 0 : 30)
                        .opacity(goalsVisible ? 1 : 0)

                    notesSection
                        .id("notesSection")
                        .offset(y: notesVisible ? 0 : 30)
                        .opacity(notesVisible ? 1 : 0)
                        .padding(.bottom, 140) // Space for floating button
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isNotesFocused, initial: false) { _, focused in
                if focused {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("notesSection", anchor: .center)
                    }
                }
            }
        }
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.3)) {
            notesVisible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            TraiLensView(size: 54, state: .idle, palette: .energy)
                .scaleEffect(headerVisible ? 1 : 0.8)

            Text("Your Goals")
                .font(.traiBold(28))

            Text("What would you like to achieve?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Choose `Build Muscle` if you want to intentionally gain scale weight. Choose `Recomposition` if you want to stay closer to the same weight while getting leaner and stronger.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(availableGoals) { goal in
                GoalCardWithDescription(
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

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Anything else?", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.accent)

                    Spacer()

                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.capsule)
                }

                Text("Dietary preferences, medical conditions, injuries, or specific needs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $additionalNotes)
                .font(.body)
                .frame(minHeight: 80)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isNotesFocused ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
                .focused($isNotesFocused)
                .onChange(of: isNotesFocused, initial: false) { _, focused in
                    if focused {
                        HapticManager.lightTap()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if additionalNotes.isEmpty && !isNotesFocused {
                        Text("e.g., I'm vegetarian, have PCOS, training for a marathon...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .traiCard(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isNotesFocused ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: isNotesFocused ? Color.accentColor.opacity(0.1) : Color.clear,
            radius: 12,
            y: 4
        )
        .animation(.spring(response: 0.3), value: isNotesFocused)
    }
}

#Preview {
    GoalsStepView(
        selectedGoal: .constant(.loseWeight),
        additionalNotes: .constant("")
    )
}
