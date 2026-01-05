//
//  ActivityLevelStepView.swift
//  Plates
//

import SwiftUI

struct ActivityLevelStepView: View {
    @Binding var activityLevel: UserProfile.ActivityLevel?
    @Binding var activityNotes: String

    @State private var headerVisible = false
    @State private var cardsVisible: [Bool] = Array(repeating: false, count: 5)
    @State private var notesVisible = false
    @State private var iconBounce = false
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 16)

                    activitySelector

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
        // Header
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerVisible = true
        }

        // Icon bounce
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.3)) {
            iconBounce = true
        }

        // Staggered activity cards
        for index in 0..<5 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15 + Double(index) * 0.08)) {
                cardsVisible[index] = true
            }
        }

        // Notes section
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6)) {
            notesVisible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Animated rings
                Circle()
                    .stroke(Color.orange.opacity(0.15), lineWidth: 2)
                    .frame(width: 95, height: 95)
                    .scaleEffect(headerVisible ? 1 : 0.5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.15), Color.yellow.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "figure.run")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .offset(x: iconBounce ? 2 : 0)
            }
            .scaleEffect(headerVisible ? 1 : 0.8)

            Text("Activity Level")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("How active are you in a typical week?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    // MARK: - Activity Selector

    private var activitySelector: some View {
        VStack(spacing: 12) {
            ForEach(Array(UserProfile.ActivityLevel.allCases.enumerated()), id: \.element.id) { index, level in
                ActivityLevelRow(
                    level: level,
                    isSelected: activityLevel == level,
                    index: index
                ) {
                    HapticManager.cardSelected()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        activityLevel = level
                    }
                }
                .offset(y: cardsVisible.indices.contains(index) && cardsVisible[index] ? 0 : 30)
                .opacity(cardsVisible.indices.contains(index) && cardsVisible[index] ? 1 : 0)
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Tell us more", systemImage: "text.bubble.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)

                    Spacer()

                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.capsule)
                }

                Text("Help Trai understand your routine better")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $activityNotes)
                .font(.body)
                .frame(minHeight: 85)
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
                    if activityNotes.isEmpty && !isNotesFocused {
                        Text("e.g., I lift weights 4x/week and play soccer on weekends...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
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

// MARK: - Activity Level Row

struct ActivityLevelRow: View {
    let level: UserProfile.ActivityLevel
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Activity indicator bar
                activityIndicator

                // Icon
                Circle()
                    .fill(
                        isSelected
                            ? colorForLevel
                            : Color(.tertiarySystemBackground)
                    )
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: iconForLevel)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? colorForLevel.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var activityIndicator: some View {
        VStack(spacing: 3) {
            ForEach(0..<5) { barIndex in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        barIndex <= index
                            ? colorForLevel
                            : Color(.tertiarySystemBackground)
                    )
                    .frame(width: 5, height: 7)
                    .opacity(barIndex <= index ? 1 : 0.5)
            }
        }
        .rotationEffect(.degrees(180))
        .animation(.spring(response: 0.3).delay(Double(index) * 0.05), value: isSelected)
    }

    private var iconForLevel: String {
        switch level {
        case .sedentary: "figure.seated.seatbelt"
        case .light: "figure.walk"
        case .moderate: "figure.run"
        case .active: "figure.highintensity.intervaltraining"
        case .veryActive: "figure.strengthtraining.traditional"
        }
    }

    private var colorForLevel: Color {
        switch level {
        case .sedentary: .gray
        case .light: .blue
        case .moderate: .green
        case .active: .orange
        case .veryActive: .red
        }
    }
}

#Preview {
    ActivityLevelStepView(
        activityLevel: .constant(.moderate),
        activityNotes: .constant("")
    )
}
