//
//  WorkoutTemplateCard.swift
//  Trai
//
//  Displays a workout template with recovery status and start action
//

import SwiftUI

struct WorkoutTemplateCard: View {
    let template: WorkoutPlan.WorkoutTemplate
    let recoveryScore: Double
    let recoveryReason: String
    let isRecommended: Bool
    let onStart: () -> Void

    private var recoveryStatus: RecoveryDisplayStatus {
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
                HStack(spacing: 4) {
                    Image(systemName: recoveryStatus.icon)
                        .font(.caption2)
                    Text(recoveryStatus.label)
                        .font(.caption)
                }
                .foregroundStyle(recoveryStatus.color)
            }

            // Template name
            Text(template.name)
                .font(.title3)
                .bold()

            // Target muscles
            Text(template.muscleGroupsDisplay)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Stats row
            HStack(spacing: 16) {
                Label("\(template.exerciseCount) exercises", systemImage: "dumbbell")
                Label("~\(template.estimatedDurationMinutes) min", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Recovery reason (if not fully ready)
            if recoveryScore < 0.9 {
                Text(recoveryReason)
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
                    Text("Start Workout")
                }
                .font(.subheadline)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            if isRecommended {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 2)
            }
        }
    }
}

// MARK: - Compact Template Card (for horizontal scroll)

struct CompactTemplateCard: View {
    let template: WorkoutPlan.WorkoutTemplate
    let recoveryScore: Double
    let isRecommended: Bool
    let onTap: () -> Void

    private var statusColor: Color {
        if recoveryScore >= 0.9 { return .green }
        else if recoveryScore >= 0.5 { return .orange }
        else { return .red }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

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

                // Muscles
                Text(template.targetMuscleGroups.prefix(2).joined(separator: ", ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isRecommended {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Templates Section

struct WorkoutTemplatesSection: View {
    let templates: [WorkoutPlan.WorkoutTemplate]
    let recoveryScores: [UUID: (score: Double, reason: String)]
    let recommendedTemplateId: UUID?
    let onStartTemplate: (WorkoutPlan.WorkoutTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Workouts")
                .font(.headline)

            if templates.isEmpty {
                emptyState
            } else {
                // Show recommended template first (full card)
                if let recommendedId = recommendedTemplateId,
                   let recommended = templates.first(where: { $0.id == recommendedId }) {
                    let recovery = recoveryScores[recommended.id] ?? (1.0, "Ready to train")
                    WorkoutTemplateCard(
                        template: recommended,
                        recoveryScore: recovery.score,
                        recoveryReason: recovery.reason,
                        isRecommended: true,
                        onStart: { onStartTemplate(recommended) }
                    )
                }

                // Other templates in horizontal scroll
                let otherTemplates = templates.filter { $0.id != recommendedTemplateId }
                if !otherTemplates.isEmpty {
                    Text("Other options")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(otherTemplates) { template in
                                let recovery = recoveryScores[template.id] ?? (1.0, "Ready")
                                CompactTemplateCard(
                                    template: template,
                                    recoveryScore: recovery.score,
                                    isRecommended: false,
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
            Image(systemName: "dumbbell")
                .foregroundStyle(.secondary)
            Text("Create a workout plan to see suggestions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 12))
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
                recoveryScore: 1.0,
                recoveryReason: "All muscles recovered",
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
                recoveryScore: 0.6,
                recoveryReason: "Back needs 8 more hours",
                isRecommended: false,
                onStart: {}
            )
        }
        .padding()
    }
}
