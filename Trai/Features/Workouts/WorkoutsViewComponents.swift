//
//  WorkoutsViewComponents.swift
//  Trai
//
//  Supporting card components for WorkoutsView
//

import SwiftUI

// MARK: - Start Workout Section

struct StartWorkoutSection: View {
    let templates: [WorkoutPlan.WorkoutTemplate]
    let recoveryScores: [UUID: (score: Double, reason: String)]
    let recommendedTemplateId: UUID?
    let onStartTemplate: (WorkoutPlan.WorkoutTemplate) -> Void
    let onStartCustomWorkout: () -> Void
    let onOpenCustomExercises: () -> Void
    var onCreatePlan: (() -> Void)?
    var onEditPlan: (() -> Void)?

    private var featuredTemplateId: UUID? {
        recommendedTemplateId ?? templates.first?.id
    }

    private var featuredTemplate: WorkoutPlan.WorkoutTemplate? {
        guard let featuredTemplateId else { return nil }
        return templates.first(where: { $0.id == featuredTemplateId })
    }

    private var supportingTemplates: [WorkoutPlan.WorkoutTemplate] {
        guard let featuredTemplateId else { return templates }
        return templates.filter { $0.id != featuredTemplateId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TraiSectionHeader("Start Workout", icon: "figure.mixed.cardio")

            if let featuredTemplate {
                FeaturedStartWorkoutCard(
                    template: featuredTemplate,
                    recoveryInsight: recoveryScores[featuredTemplate.id],
                    isRecommended: recommendedTemplateId == featuredTemplate.id,
                    onStart: { onStartTemplate(featuredTemplate) }
                )
                MoreSessionsCard(
                    templates: Array(supportingTemplates.prefix(6)),
                    recoveryScores: recoveryScores,
                    onStartTemplate: onStartTemplate,
                    onStartCustomWorkout: onStartCustomWorkout,
                    onOpenCustomExercises: onOpenCustomExercises,
                    onEditPlan: onEditPlan
                )
            } else if let onCreatePlan {
                StartWorkoutCreatePlanCard(
                    onCreatePlan: onCreatePlan,
                    onStartCustomWorkout: onStartCustomWorkout
                )
            } else {
                StartWorkoutEmptyState()
            }
        }
    }
}

private struct FeaturedStartWorkoutCard: View {
    let template: WorkoutPlan.WorkoutTemplate
    let recoveryInsight: (score: Double, reason: String)?
    let isRecommended: Bool
    let onStart: () -> Void

    private var recoveryLabel: String? {
        guard let score = recoveryInsight?.score else { return nil }
        if score >= 0.9 { return "Ready" }
        if score >= 0.5 { return "Recovering" }
        return "Rest"
    }

    private var recoveryColor: Color? {
        guard let score = recoveryInsight?.score else { return nil }
        if score >= 0.9 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [template.displayAccentColor, template.displayAccentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: template.sessionType.iconName)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.traiHeadline(17))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if isRecommended || recoveryLabel != nil {
                        HStack(spacing: 6) {
                            if isRecommended {
                                Label("Recommended", systemImage: "star.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.orange.opacity(0.12), in: Capsule())
                            }
                            if let recoveryLabel, let recoveryColor {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(recoveryColor)
                                        .frame(width: 6, height: 6)
                                    Text(recoveryLabel)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(recoveryColor)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(recoveryColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }

                    Text(template.displaySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            Button("Start Workout", systemImage: "play.fill", action: onStart)
                .buttonStyle(.traiPrimary(fullWidth: true))
        }
        .padding(16)
        .traiCard(glow: .workout, cornerRadius: 20, contentPadding: 0)
    }
}

private struct MoreSessionsCard: View {
    let templates: [WorkoutPlan.WorkoutTemplate]
    let recoveryScores: [UUID: (score: Double, reason: String)]
    let onStartTemplate: (WorkoutPlan.WorkoutTemplate) -> Void
    let onStartCustomWorkout: () -> Void
    let onOpenCustomExercises: () -> Void
    var onEditPlan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TraiSectionHeader("My Plan", icon: "calendar") {
                HStack(spacing: 6) {
                    if let onEditPlan {
                        Button("Edit", systemImage: "pencil", action: onEditPlan)
                            .buttonStyle(.traiTertiary(size: .compact, height: 28))
                    }
                    Button("Exercises", systemImage: "figure.strengthtraining.traditional", action: onOpenCustomExercises)
                        .buttonStyle(.traiTertiary(size: .compact, height: 28))
                    Button("Custom", systemImage: "plus", action: onStartCustomWorkout)
                        .buttonStyle(.traiTertiary(size: .compact, height: 28))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { template in
                        SessionCard(
                            name: template.name,
                            icon: template.sessionType.iconName,
                            accentColor: template.displayAccentColor,
                            recoveryColor: recoveryColor(for: recoveryScores[template.id]?.score),
                            onTap: { onStartTemplate(template) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .traiCard(cornerRadius: 20)
    }

    private func recoveryColor(for score: Double?) -> Color? {
        guard let score else { return nil }
        if score >= 0.9 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }
}

private struct SessionCard: View {
    let name: String
    let icon: String
    let accentColor: Color
    let recoveryColor: Color?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(accentColor)
                    .frame(width: 30, height: 30)
                    .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                Text(name)
                    .font(.traiLabel(13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let recoveryColor {
                    Circle()
                        .fill(recoveryColor)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 158)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(TraiPressStyle())
    }
}

private struct StartWorkoutCreatePlanCard: View {
    let onCreatePlan: () -> Void
    let onStartCustomWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create your workout plan")
                        .font(.traiHeadline(16))
                        .foregroundStyle(.primary)

                    Text("Let Trai build sessions around your goals and preferred workout styles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button("Create Plan", action: onCreatePlan)
                    .buttonStyle(.traiPrimary(size: .compact, fullWidth: true, height: 36))

                Button("Custom") {
                    onStartCustomWorkout()
                }
                .buttonStyle(.traiTertiary(size: .compact, fullWidth: true, height: 36))
            }
        }
        .padding(16)
        .traiCard(cornerRadius: 20, contentPadding: 0)
    }
}

private struct StartWorkoutEmptyState: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.mixed.cardio")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Start any workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Use Custom to log a flexible session without a plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .traiCard(cornerRadius: 20, contentPadding: 0)
    }
}

// MARK: - Quick Actions Row

struct WorkoutsQuickActionsRow: View {
    let onPersonalRecords: () -> Void
    let onHistory: () -> Void
    let onRecovery: () -> Void
    let onCustomExercises: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            WorkoutsQuickActionChip("Records", systemImage: "trophy.fill", color: .yellow, action: onPersonalRecords)
            WorkoutsQuickActionChip("History", systemImage: "clock.fill", color: .blue, action: onHistory)
            WorkoutsQuickActionChip("Recovery", systemImage: "waveform.path.ecg", color: .green, action: onRecovery)
            WorkoutsQuickActionChip("Exercises", systemImage: "figure.strengthtraining.traditional", color: .orange, action: onCustomExercises)
        }
    }
}

private struct WorkoutsQuickActionChip: View {
    let label: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    init(_ label: String, systemImage: String, color: Color, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.traiLabel(13))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(TraiPressStyle())
    }
}

// MARK: - Active Workout Banner

struct ActiveWorkoutBanner: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Pulsing indicator
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.green.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in Progress")
                        .font(.subheadline)
                        .bold()
                    Text(workout.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(workout.formattedDuration)
                    .font(.headline)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .traiCard(tint: .green, cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Todays Workout Summary

struct TodaysWorkoutSummary: View {
    let workouts: [WorkoutSession]
    var liveWorkouts: [LiveWorkout] = []

    private var totalWorkoutCount: Int {
        workouts.count + liveWorkouts.count
    }

    private var totalDuration: Int {
        let sessionDuration = workouts.compactMap { $0.durationMinutes }.reduce(0) { $0 + Int($1) }
        let liveDuration = liveWorkouts.reduce(0) { $0 + Int($1.duration / 60) }
        return sessionDuration + liveDuration
    }

    private var totalCalories: Int {
        let sessionCalories = workouts.compactMap(\.caloriesBurned).reduce(0, +)
        let liveCalories = liveWorkouts.compactMap { $0.healthKitCalories.map { Int($0) } }.reduce(0, +)
        return sessionCalories + liveCalories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Activity", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
            }

            if totalWorkoutCount == 0 {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.secondary)
                    Text("No workouts yet today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 24) {
                    WorkoutStatItem(
                        value: "\(totalWorkoutCount)",
                        label: totalWorkoutCount == 1 ? "workout" : "workouts",
                        icon: "figure.run",
                        color: .orange
                    )

                    if totalDuration > 0 {
                        WorkoutStatItem(
                            value: "\(totalDuration)",
                            label: "minutes",
                            icon: "clock.fill",
                            color: .blue
                        )
                    }

                    if totalCalories > 0 {
                        WorkoutStatItem(
                            value: "\(totalCalories)",
                            label: "kcal",
                            icon: "flame.fill",
                            color: .red
                        )
                    }
                }
            }
        }
        .traiCard(cornerRadius: 16)
    }
}

// MARK: - Workout Stat Item

struct WorkoutStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ActiveWorkoutBanner(
                workout: {
                    let w = LiveWorkout(name: "Push Day", workoutType: .strength, targetMuscleGroups: [.chest, .shoulders, .triceps])
                    return w
                }(),
                onTap: {}
            )

            TodaysWorkoutSummary(workouts: [])
        }
        .padding()
    }
}
