//
//  ActivityLevelStepView.swift
//  Trai
//

import SwiftUI

struct ActivityLevelStepView: View {
    @Binding var activityLevel: UserProfile.ActivityLevel?
    @Binding var activityNotes: String

    private var choices: [ActivityLevelChoice] {
        ActivityLevelChoice.all
    }

    @State private var headerVisible = false
    @State private var activityVisible = false
    @State private var selectedChoiceID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerSection
                    .padding(.top, 12)

                activitySelector
                    .offset(y: activityVisible ? 0 : 24)
                    .opacity(activityVisible ? 1 : 0)

                if activityLevel != nil {
                    selectedActivityResponse
                        .opacity(activityVisible ? 1 : 0)
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
            activityVisible = true
        }
    }

    private var headerSection: some View {
        OnboardingTraiHeader(
            title: "Choose your activity level.",
            lensSize: 52
        )
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    private var activitySelector: some View {
        GlassEffectContainer(spacing: 12) {
            activityGrid
        }
    }

    private var activityGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                ActivityLevelRow(
                    choice: choice,
                    isSelected: isSelected(choice),
                    index: index
                ) {
                    HapticManager.cardSelected()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedChoiceID = choice.id
                        activityLevel = choice.level
                    }
                }
            }
        }
    }

    private var selectedActivityResponse: some View {
        HStack(alignment: .top) {
            Text(selectedActivityChoice.map(responseText) ?? activityLevel.map(responseText) ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .onboardingTraiResponseCard()
        .animation(.smooth(duration: 0.3), value: activityLevel)
    }

    private var selectedActivityChoice: ActivityLevelChoice? {
        guard let selectedChoiceID else { return nil }
        return choices.first { $0.id == selectedChoiceID }
    }

    private func isSelected(_ choice: ActivityLevelChoice) -> Bool {
        if let selectedChoiceID {
            return selectedChoiceID == choice.id
        }
        return choice.id == choice.level.id && activityLevel == choice.level
    }

    private func responseText(for choice: ActivityLevelChoice) -> String {
        if choice.isUnsure {
            return "No problem. I’ll start with a moderate estimate and adjust as you log."
        }
        return responseText(for: choice.level)
    }

    private func responseText(for level: UserProfile.ActivityLevel) -> String {
        switch level {
        case .sedentary:
            return "I’ll start with lower activity assumptions and adjust as you log movement."
        case .light:
            return "I’ll account for light weekly movement without overestimating burn."
        case .moderate:
            return "I’ll build around regular movement and a balanced daily calorie target."
        case .active:
            return "I’ll give you more fuel for frequent training and recovery."
        case .veryActive:
            return "I’ll assume high output and keep targets high enough to support it."
        }
    }

}

struct ActivityLevelChoice: Identifiable {
    let id: String
    let title: String
    let hint: String
    let iconName: String
    let level: UserProfile.ActivityLevel
    let color: Color
    var isUnsure = false

    static let all: [ActivityLevelChoice] = [
        ActivityLevelChoice(
            id: UserProfile.ActivityLevel.sedentary.id,
            title: UserProfile.ActivityLevel.sedentary.displayName,
            hint: "little exercise",
            iconName: "figure.seated.seatbelt",
            level: .sedentary,
            color: Color(.systemGray3)
        ),
        ActivityLevelChoice(
            id: UserProfile.ActivityLevel.light.id,
            title: UserProfile.ActivityLevel.light.displayName,
            hint: "1-3 days/week",
            iconName: "figure.walk",
            level: .light,
            color: TraiColors.coral
        ),
        ActivityLevelChoice(
            id: UserProfile.ActivityLevel.moderate.id,
            title: UserProfile.ActivityLevel.moderate.displayName,
            hint: "3-5 days/week",
            iconName: "figure.run",
            level: .moderate,
            color: .accentColor
        ),
        ActivityLevelChoice(
            id: UserProfile.ActivityLevel.active.id,
            title: UserProfile.ActivityLevel.active.displayName,
            hint: "most days",
            iconName: "figure.highintensity.intervaltraining",
            level: .active,
            color: TraiColors.flame
        ),
        ActivityLevelChoice(
            id: UserProfile.ActivityLevel.veryActive.id,
            title: UserProfile.ActivityLevel.veryActive.displayName,
            hint: "athlete or physical job",
            iconName: "figure.strengthtraining.traditional",
            level: .veryActive,
            color: TraiColors.blaze
        ),
        ActivityLevelChoice(
            id: "not_sure",
            title: "Not sure",
            hint: "start balanced",
            iconName: "questionmark",
            level: .moderate,
            color: TraiColors.brandAccent,
            isUnsure: true
        )
    ]
}

struct ActivityLevelRow: View {
    let choice: ActivityLevelChoice
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(choice.color.opacity(isSelected ? 0.95 : 0.78))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: choice.iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }

                VStack(spacing: 3) {
                    Text(choice.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(choice.hint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .onboardingTintedGlass(
                tint: choice.color,
                isSelected: isSelected,
                cornerRadius: 16,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ActivityLevelStepView(
        activityLevel: .constant(.moderate),
        activityNotes: .constant("")
    )
}
