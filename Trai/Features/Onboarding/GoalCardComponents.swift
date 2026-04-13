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
            VStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(colorForGoal.opacity(0.3))
                            .frame(width: 58, height: 58)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [colorForGoal, colorForGoal.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [colorForGoal.opacity(0.15), colorForGoal.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: goal.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? .white : colorForGoal)
                        .scaleEffect(isSelected ? 1.1 : 1)
                }

                Text(goal.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .traiCard(cornerRadius: 18, contentPadding: 0)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? colorForGoal.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? colorForGoal.opacity(0.3) : Color.black.opacity(0.03),
                radius: isSelected ? 10 : 4,
                y: isSelected ? 5 : 2
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
                            isSelected
                                ? LinearGradient(
                                    colors: [colorForGoal, colorForGoal.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [colorForGoal.opacity(0.15), colorForGoal.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: goal.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? .white : colorForGoal)
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
            .traiCard(cornerRadius: 18, contentPadding: 0)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? colorForGoal.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? colorForGoal.opacity(0.3) : Color.black.opacity(0.03),
                radius: isSelected ? 10 : 4,
                y: isSelected ? 5 : 2
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
