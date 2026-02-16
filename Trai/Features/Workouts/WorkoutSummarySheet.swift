//
//  WorkoutSummarySheet.swift
//  Trai
//
//  Workout completion summary sheet
//

import SwiftUI
import SwiftData

// MARK: - Workout Summary Sheet

// MARK: - Identifiable Exercise Wrapper

private struct IdentifiableExerciseName: Identifiable {
    let id: String
    var name: String { id }
}

struct WorkoutSummarySheet: View {
    @Bindable var workout: LiveWorkout
    var achievedPRs: [String: LiveWorkoutViewModel.PRValue] = [:]
    let onDismiss: () -> Void

    @Query private var profiles: [UserProfile]
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse)
    private var allExerciseHistory: [ExerciseHistory]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var showConfetti = false
    @State private var showCelebration = false
    @State private var selectedExercise: IdentifiableExerciseName?

    /// Whether to use metric (kg) based on user profile
    private var usesMetric: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success icon with celebration pulse
                    ZStack {
                        TraiCelebrationPulse(isActive: showCelebration, color: .green)
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: showConfetti)
                    }

                    Text("Workout Complete!")
                        .font(.title)
                        .bold()
                        .traiGradientText()

                    // PRs achieved (if any)
                    if !achievedPRs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                                Text("Personal Records!")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            ForEach(Array(achievedPRs.keys.sorted()), id: \.self) { exerciseName in
                                if let prValue = achievedPRs[exerciseName] {
                                    PRRow(prValue: prValue, usesMetric: usesMetric)
                                }
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 16))
                    }

                    // Stats
                    VStack(spacing: 16) {
                        SummaryStatRow(
                            label: "Duration",
                            value: workout.formattedDuration,
                            icon: "clock.fill"
                        )

                        SummaryStatRow(
                            label: "Exercises",
                            value: "\(workout.entries?.count ?? 0)",
                            icon: "dumbbell.fill"
                        )

                        SummaryStatRow(
                            label: "Total Sets",
                            value: "\(workout.totalSets)",
                            icon: "square.stack.3d.up.fill"
                        )
                    }
                    .traiCard()

                    // Exercises completed with full detail
                    if let entries = workout.entries, !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                                ExerciseSummaryRow(entry: entry, usesMetric: usesMetric) {
                                    selectedExercise = IdentifiableExerciseName(id: entry.exerciseName)
                                }
                            }
                        }
                        .traiCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: onDismiss)
                }
            }
            .task {
                withAnimation {
                    showConfetti = true
                }
                try? await Task.sleep(for: .milliseconds(300))
                showCelebration = true
            }
            .sheet(item: $selectedExercise) { exercise in
                exercisePRSheet(for: exercise.name)
            }
        }
        .overlay {
            // Confetti overlay - covers entire sheet
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .traiBackground()
    }

    /// Build the PR detail sheet for a given exercise name
    @ViewBuilder
    private func exercisePRSheet(for exerciseName: String) -> some View {
        let history = allExerciseHistory.filter { $0.exerciseName == exerciseName }
        let exercise = exercises.first { $0.name == exerciseName }

        if let pr = ExercisePR.from(
            exerciseName: exerciseName,
            history: history,
            muscleGroup: exercise?.targetMuscleGroup
        ) {
            PRDetailSheet(
                pr: pr,
                history: history,
                useLbs: !usesMetric,
                onDeleteAll: {}
            )
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Complete more workouts with \(exerciseName) to see your progress")
                )
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedExercise = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Workout Summary Content (for inline display)

/// Summary content without NavigationStack - for embedding in parent view
struct WorkoutSummaryContent: View {
    @Bindable var workout: LiveWorkout
    var achievedPRs: [String: LiveWorkoutViewModel.PRValue] = [:]
    let onDismiss: () -> Void

    @Query private var profiles: [UserProfile]
    @State private var showConfetti = false
    @State private var showCelebration = false

    /// Whether to use metric (kg) based on user profile
    private var usesMetric: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success icon with celebration pulse
                ZStack {
                    TraiCelebrationPulse(isActive: showCelebration, color: .green)
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showConfetti)
                }

                Text("Workout Complete!")
                    .font(.title)
                    .bold()
                    .traiGradientText()

                // PRs achieved (if any)
                if !achievedPRs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text("Personal Records!")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }

                        ForEach(Array(achievedPRs.keys.sorted()), id: \.self) { exerciseName in
                            if let prValue = achievedPRs[exerciseName] {
                                PRRow(prValue: prValue, usesMetric: usesMetric)
                            }
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(.rect(cornerRadius: 16))
                }

                // Stats
                VStack(spacing: 16) {
                    SummaryStatRow(
                        label: "Duration",
                        value: workout.formattedDuration,
                        icon: "clock.fill"
                    )

                    SummaryStatRow(
                        label: "Exercises",
                        value: "\(workout.entries?.count ?? 0)",
                        icon: "dumbbell.fill"
                    )

                    SummaryStatRow(
                        label: "Total Sets",
                        value: "\(workout.totalSets)",
                        icon: "square.stack.3d.up.fill"
                    )
                }
                .traiCard()

                // Exercises completed with full detail
                if let entries = workout.entries, !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercises")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                            ExerciseSummaryRow(entry: entry, usesMetric: usesMetric)
                        }
                    }
                    .traiCard()
                }
            }
            .padding()
        }
        .overlay {
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .task {
            withAnimation {
                showConfetti = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            showCelebration = true
        }
    }
}

// MARK: - PR Row

struct PRRow: View {
    let prValue: LiveWorkoutViewModel.PRValue
    let usesMetric: Bool

    private var weightUnit: String { usesMetric ? "kg" : "lbs" }

    /// Format a weight value (stored in kg) for display
    private func formatWeight(_ kg: Double) -> String {
        let value = usesMetric ? kg : kg * WeightUtility.kgToLbs
        let rounded = WeightUtility.round(value, unit: usesMetric ? .kg : .lbs)
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded)) \(weightUnit)"
        }
        return String(format: "%.1f %@", rounded, weightUnit)
    }

    /// Format improvement value
    private func formatImprovement(_ kg: Double) -> String {
        let value = usesMetric ? kg : kg * WeightUtility.kgToLbs
        let rounded = WeightUtility.round(value, unit: usesMetric ? .kg : .lbs)
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "+\(Int(rounded)) \(weightUnit)"
        }
        return String(format: "+%.1f %@", rounded, weightUnit)
    }

    /// Formatted new value respecting user's unit preference
    private var formattedNewValue: String {
        switch prValue.type {
        case .weight, .volume:
            return formatWeight(prValue.newValue)
        case .reps:
            return "\(Int(prValue.newValue)) reps"
        }
    }

    /// Formatted improvement respecting user's unit preference
    private var formattedImprovement: String {
        guard !prValue.isFirstTime && prValue.improvement > 0 else { return "" }
        switch prValue.type {
        case .weight, .volume:
            return formatImprovement(prValue.improvement)
        case .reps:
            return "+\(Int(prValue.improvement)) reps"
        }
    }

    var body: some View {
        let metric = prValue.type.metricKind

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(prValue.exerciseName)
                    .font(.subheadline)

                HStack(spacing: 6) {
                    Text(formattedNewValue)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.primary)

                    if prValue.isFirstTime {
                        Text("First time!")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !formattedImprovement.isEmpty {
                        Text(formattedImprovement)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: metric.iconName)
                    .font(.caption2)
                Text(metric.label)
                    .font(.caption)
            }
            .foregroundStyle(metric.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(metric.color.opacity(0.15))
            .clipShape(.capsule)
        }
    }
}

// MARK: - Summary Stat Row

struct SummaryStatRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .bold()
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Exercise Summary Row

struct ExerciseSummaryRow: View {
    let entry: LiveWorkoutEntry
    let usesMetric: Bool
    var onTap: (() -> Void)?

    private var weightUnit: String { usesMetric ? "kg" : "lbs" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exercise name and equipment
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.exerciseName)
                        .font(.subheadline)
                        .bold()

                    if let equipment = entry.equipmentName, !equipment.isEmpty {
                        Text("@ \(equipment)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Sets breakdown
            let completedSets = entry.sets.filter { $0.reps > 0 && !$0.isWarmup }
            if !completedSets.isEmpty {
                // Check if all sets have the same weight - use condensed format
                let weights = Set(completedSets.map { $0.displayWeight(usesMetric: usesMetric) })
                if weights.count == 1, let weight = weights.first, weight > 0 {
                    // Condensed format: "3 sets: 12, 10, 8 @ 80 kg"
                    let reps = completedSets.map { "\($0.reps)" }.joined(separator: ", ")
                    let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(weight))"
                        : String(format: "%.1f", weight)
                    Text("\(completedSets.count) sets: \(reps) @ \(weightStr) \(weightUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Original format with individual badges
                    HStack(spacing: 4) {
                        ForEach(completedSets.indices, id: \.self) { index in
                            let set = completedSets[index]
                            SetBadge(set: set, isBest: set == entry.bestSet, usesMetric: usesMetric)

                            if index < completedSets.count - 1 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Set Badge

struct SetBadge: View {
    let set: LiveWorkoutEntry.SetData
    let isBest: Bool
    let usesMetric: Bool

    var body: some View {
        let weight = set.displayWeight(usesMetric: usesMetric)
        let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weight))"
            : String(format: "%.1f", weight)

        HStack(spacing: 2) {
            if isBest {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text("\(weightStr)×\(set.reps)")
                .font(.caption)
                .foregroundStyle(isBest ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isBest ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview("LiveWorkout Summary") {
    WorkoutSummarySheet(workout: {
        let workout = LiveWorkout(
            name: "Push Day",
            workoutType: .strength,
            targetMuscleGroups: [.chest, .shoulders, .triceps]
        )
        workout.completedAt = Date()
        return workout
    }(), onDismiss: {})
}
