//
//  GoalCardComponents.swift
//  Trai
//
//  Goal selection card components
//

import SwiftUI

// MARK: - Goal Card

struct GoalCard: View {
    let goal: UserProfile.GoalType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(colorForGoal.opacity(0.3))
                            .frame(width: 54, height: 54)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(
                            colorForGoal.opacity(isSelected ? 0.95 : 0.78)
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: goal.iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(isSelected ? 1.1 : 1)
                }

                VStack(spacing: 3) {
                    Text(goal.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(shortHint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 8)
            .onboardingTintedGlass(
                tint: colorForGoal,
                isSelected: isSelected,
                cornerRadius: 18,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var colorForGoal: Color {
        switch goal {
        case .loseWeight: TraiColors.ember
        case .loseFat: TraiColors.flame
        case .buildMuscle: .accentColor
        case .recomposition: TraiColors.coral
        case .maintenance: Color(.systemGray3)
        case .performance: TraiColors.blaze
        case .health: .accentColor
        }
    }

    private var shortHint: String {
        switch goal {
        case .loseWeight: "overall weight"
        case .loseFat: "keep muscle"
        case .buildMuscle: "strength + size"
        case .recomposition: "body recomp"
        case .maintenance: "steady weight"
        case .performance: "fuel workouts"
        case .health: "daily wellness"
        }
    }
}

// MARK: - Goal Card With Description

struct GoalCardWithDescription: View {
    let goal: UserProfile.GoalType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(colorForGoal.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(
                            colorForGoal.opacity(isSelected ? 0.95 : 0.78)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: goal.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(isSelected ? 1.1 : 1)
                }

                VStack(spacing: 4) {
                    Text(goal.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(shortDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .onboardingTintedGlass(
                tint: colorForGoal,
                isSelected: isSelected,
                cornerRadius: 18,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var shortDescription: String {
        switch goal {
        case .loseWeight: "Reduce overall weight"
        case .loseFat: "Preserve muscle mass"
        case .buildMuscle: "Gain size in a surplus"
        case .recomposition: "Lean out near maintenance"
        case .maintenance: "Keep current weight"
        case .performance: "Optimize for athletics"
        case .health: "Balanced nutrition"
        }
    }

    private var colorForGoal: Color {
        switch goal {
        case .loseWeight: TraiColors.ember
        case .loseFat: TraiColors.flame
        case .buildMuscle: .accentColor
        case .recomposition: TraiColors.coral
        case .maintenance: Color(.systemGray3)
        case .performance: TraiColors.blaze
        case .health: .accentColor
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}
