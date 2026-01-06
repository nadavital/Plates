//
//  PlanChatComponents.swift
//  Plates
//
//  Chat components for plan refinement
//

import SwiftUI

// MARK: - Chat Message Model

struct PlanChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var proposedPlan: NutritionPlan?
    var updatedPlan: NutritionPlan?
    var isProposal: Bool { proposedPlan != nil }

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Plan Chat Bubble

struct PlanChatBubble: View {
    let message: PlanChatMessage
    var onAcceptProposal: ((NutritionPlan) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tint)
                    }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? Color.accentColor
                            : Color(.secondarySystemBackground)
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(.rect(cornerRadius: 18))

                if let proposed = message.proposedPlan {
                    ProposedPlanCard(plan: proposed) {
                        onAcceptProposal?(proposed)
                    }
                }

                if message.updatedPlan != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text("Plan updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
    }
}

// MARK: - Proposed Plan Card

struct ProposedPlanCard: View {
    let plan: NutritionPlan
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Suggested Plan", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Spacer()
            }

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(plan.dailyTargets.calories)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))

                    Text("kcal")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text("Daily Calories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                MacroDisplay(
                    value: plan.dailyTargets.protein,
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.carbs,
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.fat,
                    label: "Fat",
                    color: .yellow,
                    icon: "f.circle.fill"
                )
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.proteinPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.carbsPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.fatPercent) / 100)
                }
            }
            .frame(height: 10)
            .clipShape(.rect(cornerRadius: 5))

            Button {
                onAccept()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)

                    Text("Accept This Plan")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
        )
    }
}

// MARK: - Macro Display

struct MacroDisplay: View {
    let value: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}
