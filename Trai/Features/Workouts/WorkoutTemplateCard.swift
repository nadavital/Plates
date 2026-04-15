//
//  WorkoutTemplateCard.swift
//  Trai
//
//  Displays a workout template with recovery status and start action
//

import SwiftUI

struct WorkoutTemplateCard: View {
    let template: WorkoutPlan.WorkoutTemplate
    let recoveryInsight: (score: Double, reason: String)?
    let isRecommended: Bool
    let onStart: () -> Void

    private var recoveryStatus: RecoveryDisplayStatus? {
        guard let recoveryScore = recoveryInsight?.score else { return nil }
        if recoveryScore >= 0.9 {
            return .ready
        } else if recoveryScore >= 0.5 {
            return .partial
        } else {
            return .needsRest
        }
    }

    private enum RecoveryDisplayStatus {
        case ready, partial, needsRest

        var color: Color {
            switch self {
            case .ready: .green
            case .partial: .orange
            case .needsRest: .red
            }
        }

        var icon: String {
            switch self {
            case .ready: "checkmark.circle.fill"
            case .partial: "clock.fill"
            case .needsRest: "moon.zzz.fill"
            }
        }

        var label: String {
            switch self {
            case .ready: "Ready"
            case .partial: "Recovering"
            case .needsRest: "Rest"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with recommended badge
            HStack {
                if isRecommended {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text("Recommended")
                            .font(.caption)
                            .bold()
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(.capsule)
                }

                Spacer()

                // Recovery status badge
                if let recoveryStatus {
                    HStack(spacing: 4) {
                        Image(systemName: recoveryStatus.icon)
                            .font(.caption2)
                        Text(recoveryStatus.label)
                            .font(.caption)
                    }
                    .foregroundStyle(recoveryStatus.color)
                }
            }

            // Template name
            Text(template.name)
                .font(.title3)
                .bold()

            HStack(spacing: 8) {
                Label(template.sessionType.displayName, systemImage: template.sessionType.iconName)
                    .font(.caption)
                    .foregroundStyle(template.displayAccentColor)

                Text(template.displaySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Stats row
            HStack(spacing: 16) {
                if template.sessionType.prefersStructuredEntries {
                    Label("\(template.exerciseCount) exercises", systemImage: "dumbbell")
                } else {
                    Label("Flexible session", systemImage: "list.bullet.rectangle")
                }
                Label("~\(template.estimatedDurationMinutes) min", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Recovery reason (if not fully ready)
            if let recoveryInsight, let recoveryStatus, recoveryInsight.score < 0.9 {
                Text(recoveryInsight.reason)
                    .font(.caption)
                    .foregroundStyle(recoveryStatus.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(recoveryStatus.color.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 6))
            }

            // Start button (always enabled - user can override recovery warnings)
            Button(action: {
                onStart()
                HapticManager.selectionChanged()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(template.sessionType.prefersStructuredEntries ? "Start Workout" : "Start Session")
                }
                .font(.subheadline)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.traiPrimary())
        }
        .traiCard()
    }
}

// MARK: - Compact Template Card (for horizontal scroll)

struct CompactTemplateCard: View {
    let template: WorkoutPlan.WorkoutTemplate
    let recoveryScore: Double?
    let isRecommended: Bool
    let onTap: () -> Void

    private var statusColor: Color? {
        guard let recoveryScore else { return nil }
        if recoveryScore >= 0.9 { return .green }
        else if recoveryScore >= 0.5 { return .orange }
        else { return .red }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Status indicator
                HStack {
                    if let statusColor {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                    }

                    if isRecommended {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Spacer()
                }

                // Name
                Text(template.name)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)

                Label(template.sessionType.displayName, systemImage: template.sessionType.iconName)
                    .font(.caption2)
                    .foregroundStyle(template.displayAccentColor)
                    .lineLimit(1)

                // Duration
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                    Text("\(template.estimatedDurationMinutes)m")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(width: 120)
            .traiCard(cornerRadius: 14)
        }
        .buttonStyle(TraiPressStyle())
    }
}

// MARK: - Templates Section

struct WorkoutTemplatesSection: View {
    let templates: [WorkoutPlan.WorkoutTemplate]
    let recoveryScores: [UUID: (score: Double, reason: String)]
    let recommendedTemplateId: UUID?
    let onStartTemplate: (WorkoutPlan.WorkoutTemplate) -> Void
    var onCreatePlan: (() -> Void)?

    private var featuredTemplateId: UUID? {
        recommendedTemplateId ?? templates.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Workouts")
                .font(.headline)

            if templates.isEmpty {
                // Show create plan option if callback provided
                if let createAction = onCreatePlan {
                    createPlanPrompt(action: createAction)
                } else {
                    emptyState
                }
            } else {
                // Show recommended template first (full card)
                if let featuredTemplateId,
                   let recommended = templates.first(where: { $0.id == featuredTemplateId }) {
                    WorkoutTemplateCard(
                        template: recommended,
                        recoveryInsight: recoveryScores[recommended.id],
                        isRecommended: recommendedTemplateId == recommended.id,
                        onStart: { onStartTemplate(recommended) }
                    )
                }

                // Other templates in horizontal scroll
                let otherTemplates = templates.filter { $0.id != featuredTemplateId }
                if !otherTemplates.isEmpty {
                    Text("More sessions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(otherTemplates) { template in
                                CompactTemplateCard(
                                    template: template,
                                    recoveryScore: recoveryScores[template.id]?.score,
                                    isRecommended: recommendedTemplateId == template.id,
                                    onTap: { onStartTemplate(template) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Text("Create a workout plan to see session suggestions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 12))
    }

    // Subtle create plan prompt (not the big CTA)
    private func createPlanPrompt(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Personalized Workouts")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Let Trai create a weekly plan around your goals and preferred workout styles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            WorkoutTemplateCard(
                template: WorkoutPlan.WorkoutTemplate(
                    name: "Push Day",
                    targetMuscleGroups: ["chest", "shoulders", "triceps"],
                    exercises: [
                        .init(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: 4, defaultReps: 8, order: 0),
                        .init(exerciseName: "Overhead Press", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 10, order: 1),
                        .init(exerciseName: "Incline DB Press", muscleGroup: "chest", defaultSets: 3, defaultReps: 10, order: 2),
                        .init(exerciseName: "Lateral Raises", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 12, order: 3),
                        .init(exerciseName: "Tricep Pushdown", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, order: 4)
                    ],
                    estimatedDurationMinutes: 45,
                    order: 0
                ),
                recoveryInsight: (1.0, "All muscles recovered"),
                isRecommended: true,
                onStart: {}
            )

            WorkoutTemplateCard(
                template: WorkoutPlan.WorkoutTemplate(
                    name: "Pull Day",
                    targetMuscleGroups: ["back", "biceps"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 1
                ),
                recoveryInsight: (0.6, "Back needs 8 more hours"),
                isRecommended: false,
                onStart: {}
            )
        }
        .padding()
    }
}
