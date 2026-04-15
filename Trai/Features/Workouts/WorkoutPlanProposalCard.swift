//
//  WorkoutPlanProposalCard.swift
//  Trai
//
//  Inline card showing a generated workout plan with accept/customize options
//

import SwiftUI

/// Card displayed inline in chat showing the generated workout plan
struct WorkoutPlanProposalCard: View {
    let plan: WorkoutPlan
    let message: String
    let onAccept: (() -> Void)?
    let acceptTitle: String
    let onCustomize: (() -> Void)?
    let customizeTitle: String

    private struct PlanSummaryMetric {
        let value: String
        let label: String
        let footnote: String?
    }

    private var structuredSessionCount: Int {
        plan.templates.filter { $0.sessionType.prefersStructuredEntries }.count
    }

    private var flexibleSessionCount: Int {
        plan.templates.count - structuredSessionCount
    }

    private var totalExercises: Int {
        plan.templates.reduce(0) { $0 + $1.exerciseCount }
    }

    private var summaryMetric: PlanSummaryMetric {
        if flexibleSessionCount > 0 {
            return PlanSummaryMetric(
                value: "\(plan.templates.count)",
                label: "sessions",
                footnote: flexibleSessionCount == 1 ? "1 flexible day" : "\(flexibleSessionCount) flexible days"
            )
        }

        return PlanSummaryMetric(
            value: "\(totalExercises)",
            label: "exercises",
            footnote: nil
        )
    }

    init(
        plan: WorkoutPlan,
        message: String,
        onAccept: (() -> Void)?,
        acceptTitle: String = "Use This Plan",
        onCustomize: (() -> Void)?,
        customizeTitle: String = "Adjust"
    ) {
        self.plan = plan
        self.message = message
        self.onAccept = onAccept
        self.acceptTitle = acceptTitle
        self.onCustomize = onCustomize
        self.customizeTitle = customizeTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Trai's message (only show if not empty)
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Plan summary card
            VStack(alignment: .leading, spacing: 12) {
                // Header
                planHeader

                Divider()

                // Templates preview
                templatesPreview

                if onAccept != nil || onCustomize != nil {
                    // Action buttons
                    actionButtons
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            }
        }
    }

    // MARK: - Plan Header

    private var planHeader: some View {
        HStack {
            Image(systemName: plan.splitType.iconName)
                .font(.title3)
                .foregroundStyle(.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.splitType.displayName)
                    .font(.subheadline)
                    .bold()

                Text("\(plan.daysPerWeek) days/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Session summary
            VStack(alignment: .trailing, spacing: 2) {
                Text(summaryMetric.value)
                    .font(.subheadline)
                    .bold()

                Text(summaryMetric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let footnote = summaryMetric.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Templates Preview

    private var templatesPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.templates) { template in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: template.sessionType.iconName)
                        .font(.caption)
                        .foregroundStyle(template.displayAccentColor)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        Text(template.displaySubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if template.sessionType.prefersStructuredEntries {
                        Text("\(template.exerciseCount) exercises")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(template.focusAreas.isEmpty ? "Flexible session" : template.focusAreasDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("\(template.estimatedDurationMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Accept button
            if let accept = onAccept {
                Button(action: accept) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(acceptTitle)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.traiPrimary(color: .accentColor))
            }

            // Customize button (optional)
            if let customize = onCustomize {
                Button(action: customize) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                        Text(customizeTitle)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.traiTertiary())
            }
        }
    }
}

// MARK: - Plan Accepted Badge

/// Shows a confirmation badge when plan is accepted
struct WorkoutPlanAcceptedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)

            Text("Plan saved!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Plan Updated Badge

/// Shows when a plan was updated after refinement
struct WorkoutPlanUpdatedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundStyle(.accent)

            Text("Plan updated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            WorkoutPlanProposalCard(
                plan: WorkoutPlan(
                    splitType: .pushPullLegs,
                    daysPerWeek: 4,
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
                            name: "Legs Day",
                            targetMuscleGroups: ["quads", "hamstrings", "calves"],
                            exercises: [],
                            estimatedDurationMinutes: 50,
                            order: 2
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Cardio",
                            targetMuscleGroups: ["cardio"],
                            exercises: [],
                            estimatedDurationMinutes: 30,
                            order: 3
                        )
                    ],
                    rationale: "A classic Push/Pull/Legs split is perfect for your schedule and goals. This gives each muscle group adequate rest while maintaining workout frequency.",
                    guidelines: ["Rest 2-3 minutes between heavy sets"],
                    progressionStrategy: .defaultStrategy,
                    warnings: nil
                ),
                message: "Here's what I put together for you!",
                onAccept: {},
                onCustomize: {}
            )

            WorkoutPlanProposalCard(
                plan: WorkoutPlan(
                    splitType: .custom,
                    daysPerWeek: 4,
                    templates: [
                        WorkoutPlan.WorkoutTemplate(
                            name: "Bouldering Session",
                            sessionType: .climbing,
                            focusAreas: ["Technique", "Endurance"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 75,
                            order: 0
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Upper Strength",
                            sessionType: .strength,
                            focusAreas: ["Upper", "Push"],
                            targetMuscleGroups: ["chest", "shoulders", "triceps"],
                            exercises: [],
                            estimatedDurationMinutes: 55,
                            order: 1
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Mobility Flow",
                            sessionType: .mobility,
                            focusAreas: ["Hips", "Shoulders"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 25,
                            order: 2
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Trail Run",
                            sessionType: .cardio,
                            focusAreas: ["Zone 2"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 40,
                            order: 3
                        )
                    ],
                    rationale: "A mixed plan that keeps climbing skill work, dedicated strength, and aerobic training all in the same week.",
                    guidelines: [],
                    progressionStrategy: .defaultStrategy,
                    warnings: nil
                ),
                message: "This one mixes structured and flexible sessions cleanly.",
                onAccept: {},
                onCustomize: {}
            )

            WorkoutPlanAcceptedBadge()

            WorkoutPlanUpdatedBadge()
        }
        .padding()
    }
}
