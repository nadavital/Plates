//
//  WorkoutPlanOverviewCard.swift
//  Plates
//
//  Shows workout plan summary or prompts to create one
//

import SwiftUI

struct WorkoutPlanOverviewCard: View {
    let workoutPlan: WorkoutPlan?
    let onCreatePlan: () -> Void
    let onEditPlan: () -> Void

    var body: some View {
        if let plan = workoutPlan {
            planOverviewView(plan)
        } else {
            createPlanPrompt
        }
    }

    // MARK: - Plan Overview

    private func planOverviewView(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Plan")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(plan.splitType.displayName)
                        .font(.headline)
                }

                Spacer()

                Button(action: onEditPlan) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Stats row
            HStack(spacing: 16) {
                PlanStatChip(
                    icon: "calendar",
                    value: "\(plan.daysPerWeek)",
                    label: "days/week"
                )

                PlanStatChip(
                    icon: "clock",
                    value: "\(plan.templates.first?.estimatedDurationMinutes ?? 45)",
                    label: "min"
                )

                PlanStatChip(
                    icon: "dumbbell",
                    value: "\(plan.templates.count)",
                    label: "workouts"
                )
            }

            // Template chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(plan.templates) { template in
                        TemplateChip(template: template)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Create Plan Prompt

    private var createPlanPrompt: some View {
        Button(action: onCreatePlan) {
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(.accent)
                }

                // Text
                VStack(spacing: 4) {
                    Text("Create Your Workout Plan")
                        .font(.headline)

                    Text("Let Trai design a personalized training program for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Button indicator
                HStack {
                    Text("Get Started")
                        .font(.subheadline)
                        .bold()

                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [8, 4]))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Stat Chip

struct PlanStatChip: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Template Chip

struct TemplateChip: View {
    let template: WorkoutPlan.WorkoutTemplate

    private var primaryColor: Color {
        // Color based on primary muscle group
        guard let firstMuscle = template.targetMuscleGroups.first else {
            return .gray
        }

        switch firstMuscle {
        case "chest", "shoulders", "triceps":
            return .orange
        case "back", "biceps":
            return .blue
        case "quads", "hamstrings", "glutes", "calves":
            return .green
        case "core":
            return .purple
        default:
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(primaryColor)
                .frame(width: 8, height: 8)

            Text(template.name)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(primaryColor.opacity(0.15))
        .clipShape(.capsule)
    }
}

// MARK: - Preview

#Preview("With Plan") {
    WorkoutPlanOverviewCard(
        workoutPlan: WorkoutPlan(
            splitType: .pushPullLegs,
            daysPerWeek: 3,
            templates: [
                WorkoutPlan.WorkoutTemplate(
                    name: "Push Day",
                    targetMuscleGroups: ["chest", "shoulders", "triceps"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 0
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Pull Day",
                    targetMuscleGroups: ["back", "biceps"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 1
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Leg Day",
                    targetMuscleGroups: ["quads", "hamstrings", "glutes"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 2
                )
            ],
            rationale: "A classic PPL split",
            guidelines: [],
            progressionStrategy: .defaultStrategy,
            warnings: nil
        ),
        onCreatePlan: {},
        onEditPlan: {}
    )
    .padding()
}

#Preview("No Plan") {
    WorkoutPlanOverviewCard(
        workoutPlan: nil,
        onCreatePlan: {},
        onEditPlan: {}
    )
    .padding()
}
