//
//  WorkoutPlanDetailView.swift
//  Trai
//
//  Detailed view of the user's workout plan
//

import SwiftUI

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    var usesMetricExerciseWeight: Bool = true
    var onEditPlan: (() -> Void)?

    private var flexibleSessionCount: Int {
        plan.templates.filter { !$0.sessionType.prefersStructuredEntries }.count
    }

    private var hasStructuredStrengthSessions: Bool {
        plan.templates.contains { $0.sessionType.prefersStructuredEntries }
    }

    private var weightIncrementDisplay: String {
        let kg = plan.progressionStrategy.weightIncrementKg
        if usesMetricExerciseWeight {
            return String(format: "%.1f kg", kg)
        } else {
            return String(format: "%.1f lbs", kg * 2.20462)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewCard
                templatesSection
                guidelinesCard
                warningsCard
                progressionCard
            }
            .padding()
        }
        .navigationTitle("Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let editAction = onEditPlan {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", action: editAction)
                }
            }
        }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: plan.splitType.iconName)
                    .font(.title2)
                    .foregroundStyle(.accent)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.splitType.displayName)
                        .font(.headline)

                    Text(planSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !plan.rationale.isEmpty {
                Text(plan.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(plan.templates.sorted { $0.order < $1.order }) { template in
                templateCard(template)
            }
        }
    }

    private func templateCard(_ template: WorkoutPlan.WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(template.displayAccentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(template.sessionType.displayName, systemImage: template.sessionType.iconName)
                        .font(.caption)
                        .foregroundStyle(template.displayAccentColor)

                    if !template.displaySubtitle.isEmpty {
                        Text(template.displaySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Label("\(template.estimatedDurationMinutes) min", systemImage: "clock")
                    if template.sessionType.prefersStructuredEntries {
                        Label("\(template.exerciseCount) exercises", systemImage: "dumbbell")
                    } else {
                        Label("Flexible session", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Progression Card

    @ViewBuilder
    private var progressionCard: some View {
        if hasStructuredStrengthSessions {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    Text("Auto Progression")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(plan.progressionStrategy.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if let repsTrigger = plan.progressionStrategy.repsTrigger {
                        Label("\(repsTrigger) rep target", systemImage: "number")
                    }

                    if plan.progressionStrategy.weightIncrementKg > 0 {
                        Label(weightIncrementDisplay, systemImage: "plus")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var planSubtitle: String {
        let base = "\(plan.daysPerWeek) days per week"
        guard flexibleSessionCount > 0 else { return base }
        let suffix = flexibleSessionCount == 1 ? "1 flexible session" : "\(flexibleSessionCount) flexible sessions"
        return "\(base) • \(suffix)"
    }

    // MARK: - Guidelines Card

    @ViewBuilder
    private var guidelinesCard: some View {
        if !plan.guidelines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)

                    Text("Guidelines")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.guidelines.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)

                            Text(plan.guidelines[index])
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
    }

    // MARK: - Warnings Card

    @ViewBuilder
    private var warningsCard: some View {
        if let warnings = plan.warnings, !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    Text("Important Notes")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.orange)

                            Text(warnings[index])
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(.rect(cornerRadius: 16))
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutPlanDetailView(plan: .previewPlan)
    }
}

extension WorkoutPlan {
    static let previewPlan = WorkoutPlan(
        splitType: .pushPullLegs,
        daysPerWeek: 3,
        templates: [
            WorkoutTemplate(
                name: "Push Day",
                targetMuscleGroups: ["chest", "shoulders", "triceps"],
                exercises: [],
                estimatedDurationMinutes: 45,
                order: 0
            ),
            WorkoutTemplate(
                name: "Pull Day",
                targetMuscleGroups: ["back", "biceps"],
                exercises: [],
                estimatedDurationMinutes: 45,
                order: 1
            ),
            WorkoutTemplate(
                name: "Leg Day",
                targetMuscleGroups: ["quads", "hamstrings", "glutes"],
                exercises: [],
                estimatedDurationMinutes: 50,
                order: 2
            )
        ],
        rationale: "A Push/Pull/Legs split is ideal for your goals, allowing you to train each muscle group with optimal frequency while maintaining good recovery.",
        guidelines: [
            "Focus on progressive overload",
            "Rest 48 hours between similar muscle groups",
            "Prioritize compound movements"
        ],
        progressionStrategy: .defaultStrategy,
        warnings: ["Start lighter if you're new to these exercises"]
    )
}
