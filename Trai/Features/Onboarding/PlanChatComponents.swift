//
//  PlanChatComponents.swift
//  Trai
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
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if message.role == .user {
                    TraiUserTextBubble(text: message.content)
                } else {
                    TraiAssistantTextMessage(text: message.content)
                }

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

            if message.role == .assistant { Spacer() }
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
                    color: MacroType.protein.color,
                    icon: "p.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.carbs,
                    label: "Carbs",
                    color: MacroType.carbs.color,
                    icon: "c.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.fat,
                    label: "Fat",
                    color: MacroType.fat.color,
                    icon: "f.circle.fill"
                )
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MacroType.protein.color)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.proteinPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(MacroType.carbs.color)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.carbsPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(MacroType.fat.color)
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
            .buttonStyle(.traiPrimary(color: .green))
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
