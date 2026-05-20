//
//  WorkoutPlanDecisionView.swift
//  Trai
//
//  Simple decision view for workout plan in onboarding
//

import SwiftUI

struct WorkoutPlanDecisionView: View {
    let hasWorkoutPlan: Bool
    let workoutPlan: WorkoutPlan?
    let onCreatePlan: () -> Void
    let onSkipPlan: () -> Void

    @State private var headerVisible = false
    @State private var contentVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    TraiLensView(size: 60, state: .idle, palette: .energy)

                    Text(hasWorkoutPlan ? "Your Workout Plan is Ready!" : "Set Up Workouts")
                        .font(.traiBold(28))
                        .multilineTextAlignment(.center)

                    Text(hasWorkoutPlan
                         ? "Review your personalized workout plan below."
                         : "Choose how you want to start training in Trai.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .offset(y: headerVisible ? 0 : -20)
                .opacity(headerVisible ? 1 : 0)

                if hasWorkoutPlan, let plan = workoutPlan {
                    // Show plan summary
                    workoutPlanSummary(plan)
                        .offset(y: contentVisible ? 0 : 20)
                        .opacity(contentVisible ? 1 : 0)

                    // Edit button
                    Button {
                        onCreatePlan()
                    } label: {
                        Label("Customize Plan", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.traiTertiary())
                    .offset(y: contentVisible ? 0 : 20)
                    .opacity(contentVisible ? 1 : 0)
                } else {
                    VStack(spacing: 12) {
                        workoutChoiceCard(
                            icon: "sparkles",
                            title: "Create Workout Plan",
                            subtitle: "Build a personalized weekly plan",
                            tint: .accentColor,
                            action: onCreatePlan
                        )

                        workoutChoiceCard(
                            icon: "figure.strengthtraining.traditional",
                            title: "Track Workouts Only",
                            subtitle: "Log sessions and decide on a plan later",
                            tint: .secondary,
                            action: onSkipPlan
                        )
                    }
                    .offset(y: contentVisible ? 0 : 20)
                    .opacity(contentVisible ? 1 : 0)

                    // Info text
                    Text("You can always create or modify your workout plan later from the Workouts tab.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .offset(y: contentVisible ? 0 : 20)
                        .opacity(contentVisible ? 1 : 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                contentVisible = true
            }
        }
    }

    // MARK: - Workout Plan Summary

    private func workoutPlanSummary(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 16) {
            // Split type
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.accent)
                Text(plan.splitType.displayName)
                    .font(.headline)
                Spacer()
                Text("\(plan.templates.count) workouts/week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .traiCard(cornerRadius: 12)

            // Workout list
            ForEach(plan.templates.prefix(4)) { template in
                HStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text("\(template.order + 1)")
                                .font(.headline)
                                .foregroundStyle(.accent)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(template.primaryBlockSummary.isEmpty ? template.displayWorkloadSummary : template.primaryBlockSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .traiCard(cornerRadius: 12, contentPadding: 0)
            }

            if plan.templates.count > 4 {
                Text("+\(plan.templates.count - 4) more workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workoutChoiceCard(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.lightTap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .traiCard(cornerRadius: 16, contentPadding: 0)
        }
        .buttonStyle(.plain)
    }
}

#Preview("No Plan") {
    WorkoutPlanDecisionView(
        hasWorkoutPlan: false,
        workoutPlan: nil,
        onCreatePlan: {},
        onSkipPlan: {}
    )
}
