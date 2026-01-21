//
//  WorkoutSummarySheet.swift
//  Trai
//
//  Workout completion summary sheet
//

import SwiftUI
import SwiftData

// MARK: - Workout Summary Sheet

struct WorkoutSummarySheet: View {
    @Bindable var workout: LiveWorkout
    var achievedPRs: [String: LiveWorkoutViewModel.PRType] = [:]
    let onDismiss: () -> Void

    @State private var showConfetti = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showConfetti)

                    Text("Workout Complete!")
                        .font(.title)
                        .bold()

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
                                if let prType = achievedPRs[exerciseName] {
                                    HStack {
                                        Text(exerciseName)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(prType.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor)
                                            .clipShape(.capsule)
                                    }
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

                        if workout.totalVolume > 0 {
                            SummaryStatRow(
                                label: "Total Volume",
                                value: "\(Int(workout.totalVolume)) kg",
                                icon: "scalemass.fill"
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    // Exercises completed with full detail
                    if let entries = workout.entries, !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises")
                                .font(.headline)

                            ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                                ExerciseSummaryRow(entry: entry)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 16))
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
            .onAppear {
                withAnimation {
                    showConfetti = true
                }
                HapticManager.success()
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
    }
}

// MARK: - Workout Summary Content (for inline display)

/// Summary content without NavigationStack - for embedding in parent view
struct WorkoutSummaryContent: View {
    @Bindable var workout: LiveWorkout
    var achievedPRs: [String: LiveWorkoutViewModel.PRType] = [:]
    let onDismiss: () -> Void

    @State private var showConfetti = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: showConfetti)

                Text("Workout Complete!")
                    .font(.title)
                    .bold()

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
                            if let prType = achievedPRs[exerciseName] {
                                HStack {
                                    Text(exerciseName)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(prType.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor)
                                        .clipShape(.capsule)
                                }
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

                    if workout.totalVolume > 0 {
                        SummaryStatRow(
                            label: "Total Volume",
                            value: "\(Int(workout.totalVolume)) kg",
                            icon: "scalemass.fill"
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 16))

                // Exercises completed with full detail
                if let entries = workout.entries, !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercises")
                            .font(.headline)

                        ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                            ExerciseSummaryRow(entry: entry)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
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
        .onAppear {
            withAnimation {
                showConfetti = true
            }
            HapticManager.success()
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
        }
    }
}

// MARK: - Exercise Summary Row

struct ExerciseSummaryRow: View {
    let entry: LiveWorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exercise name and volume
            HStack {
                Text(entry.exerciseName)
                    .font(.subheadline)
                    .bold()

                Spacer()

                if entry.totalVolume > 0 {
                    Text("\(Int(entry.totalVolume)) kg")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Sets breakdown
            let completedSets = entry.sets.filter { $0.reps > 0 && !$0.isWarmup }
            if !completedSets.isEmpty {
                // Check if all sets have the same weight - use condensed format
                let weights = Set(completedSets.map { $0.weightKg })
                if weights.count == 1, let weight = weights.first, weight > 0 {
                    // Condensed format: "3 sets: 12, 10, 8 @ 80kg"
                    let reps = completedSets.map { "\($0.reps)" }.joined(separator: ", ")
                    Text("\(completedSets.count) sets: \(reps) @ \(Int(weight))kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Original format with individual badges
                    HStack(spacing: 4) {
                        ForEach(completedSets.indices, id: \.self) { index in
                            let set = completedSets[index]
                            SetBadge(set: set, isBest: set == entry.bestSet)

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
        .padding(.vertical, 6)
    }
}

// MARK: - Set Badge

struct SetBadge: View {
    let set: LiveWorkoutEntry.SetData
    let isBest: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isBest {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text("\(Int(set.weightKg))×\(set.reps)")
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
