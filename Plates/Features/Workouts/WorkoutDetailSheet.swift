//
//  WorkoutDetailSheet.swift
//  Plates
//
//  Detailed view of a completed workout session
//

import SwiftUI

struct WorkoutDetailSheet: View {
    let workout: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Stats summary
                    statsSection

                    // Workout details
                    detailsSection

                    // Notes (if any)
                    if let notes = workout.notes, !notes.isEmpty {
                        notesSection(notes)
                    }

                    // HealthKit info
                    if workout.sourceIsHealthKit {
                        healthKitSection
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: workout.isStrengthTraining ? "dumbbell.fill" : "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            // Name
            Text(workout.displayName)
                .font(.title2)
                .bold()

            // Date and time
            Text(workout.loggedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 16) {
            if workout.isStrengthTraining {
                WorkoutStatCard(
                    value: "\(workout.sets)",
                    label: "Sets",
                    icon: "square.stack.3d.up.fill",
                    color: .blue
                )
                WorkoutStatCard(
                    value: "\(workout.reps)",
                    label: "Reps",
                    icon: "repeat",
                    color: .green
                )
                if let weight = workout.weightKg {
                    WorkoutStatCard(
                        value: "\(Int(weight))",
                        label: "kg",
                        icon: "scalemass.fill",
                        color: .orange
                    )
                }
            } else {
                if let duration = workout.durationMinutes {
                    WorkoutStatCard(
                        value: formatDuration(duration),
                        label: "Duration",
                        icon: "clock.fill",
                        color: .blue
                    )
                }
                if let distance = workout.distanceMeters {
                    WorkoutStatCard(
                        value: formatDistance(distance),
                        label: "Distance",
                        icon: "figure.walk",
                        color: .green
                    )
                }
            }

            if let calories = workout.caloriesBurned {
                WorkoutStatCard(
                    value: "\(calories)",
                    label: "kcal",
                    icon: "flame.fill",
                    color: .red
                )
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 0) {
                if workout.isStrengthTraining {
                    DetailRow(label: "Type", value: "Strength Training")
                    if let volume = workout.totalVolume {
                        DetailRow(label: "Total Volume", value: "\(Int(volume)) kg")
                    }
                } else {
                    DetailRow(label: "Type", value: workout.healthKitWorkoutType?.capitalized ?? "Cardio")
                    if let avgHR = workout.averageHeartRate {
                        DetailRow(label: "Avg Heart Rate", value: "\(avgHR) bpm")
                    }
                }

                DetailRow(label: "Logged", value: workout.loggedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Notes Section

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            Text(notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - HealthKit Section

    private var healthKitSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text("Imported from Apple Health")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(totalMinutes)m"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

// MARK: - Workout Stat Card

struct WorkoutStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Live Workout Detail Sheet

struct LiveWorkoutDetailSheet: View {
    let workout: LiveWorkout
    var useLbs: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var exerciseCount: Int {
        workout.entries?.count ?? 0
    }

    private var totalSets: Int {
        workout.entries?.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    private var completedSets: Int {
        workout.entries?.reduce(0) { $0 + ($1.completedSets?.count ?? 0) } ?? 0
    }

    private var maxWeightKg: Double? {
        workout.entries?.flatMap { $0.sets }.compactMap { $0.weightKg }.filter { $0 > 0 }.max()
    }

    private var durationMinutes: Int {
        Int(workout.duration / 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header (includes stats)
                    headerSection

                    // Exercises list
                    if let entries = workout.entries, !entries.isEmpty {
                        exercisesSection(entries: entries.sorted { $0.orderIndex < $1.orderIndex })
                    }

                    // Notes (if any)
                    if !workout.notes.isEmpty {
                        notesSection(workout.notes)
                    }

                    // HealthKit merge info
                    if workout.mergedHealthKitWorkoutID != nil {
                        healthKitMergeSection
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header Section (includes stats)

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon and title
            VStack(spacing: 8) {
                Image(systemName: workout.type == .cardio ? "figure.run" : "dumbbell.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.accent)

                Text(workout.name)
                    .font(.title2)
                    .bold()

                Text(workout.startedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 20) {
                if durationMinutes > 0 {
                    StatPill(icon: "clock.fill", value: formatDuration(Double(durationMinutes)), label: "time", color: .blue)
                }

                StatPill(icon: "dumbbell.fill", value: "\(exerciseCount)", label: exerciseCount == 1 ? "exercise" : "exercises", color: .green)
                StatPill(icon: "square.stack.3d.up.fill", value: "\(totalSets)", label: totalSets == 1 ? "set" : "sets", color: .orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Exercises Section

    private func exercisesSection(entries: [LiveWorkoutEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(entries) { entry in
                    LiveWorkoutExerciseCard(entry: entry, useLbs: useLbs)
                }
            }
        }
    }

    // MARK: - Notes Section

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            Text(notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - HealthKit Merge Section

    private var healthKitMergeSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .foregroundStyle(.green)
            Text("Merged with Apple Watch data")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let calories = workout.healthKitCalories {
                Text("• \(Int(calories)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(totalMinutes)m"
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Live Workout Exercise Card

private struct LiveWorkoutExerciseCard: View {
    let entry: LiveWorkoutEntry
    let useLbs: Bool

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Exercise name
            Text(entry.exerciseName)
                .font(.subheadline)
                .fontWeight(.semibold)

            // Sets as rows
            if !entry.sets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(entry.sets.indices, id: \.self) { index in
                        let set = entry.sets[index]
                        SetDetailRow(
                            setNumber: index + 1,
                            reps: set.reps,
                            weight: set.weightKg,
                            isWarmup: set.isWarmup,
                            notes: set.notes,
                            useLbs: useLbs
                        )
                    }
                }
            }

            // Notes for this exercise
            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Set Detail Row

private struct SetDetailRow: View {
    let setNumber: Int
    let reps: Int
    let weight: Double
    let isWarmup: Bool
    let notes: String
    let useLbs: Bool

    private var displayWeight: String {
        guard weight > 0 else { return "" }
        let converted = useLbs ? Int(weight * 2.20462) : Int(weight)
        let unit = useLbs ? "lbs" : "kg"
        return "\(converted) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Set number indicator
                Text(isWarmup ? "W" : "\(setNumber)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 24, height: 24)
                    .background(isWarmup ? Color.orange.opacity(0.2) : Color(.tertiarySystemFill))
                    .foregroundStyle(isWarmup ? .orange : .secondary)
                    .clipShape(.circle)

                // Reps
                Text("\(reps) reps")
                    .font(.subheadline)

                Spacer()

                // Weight
                if weight > 0 {
                    Text(displayWeight)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Notes inline
            if !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("WorkoutSession Detail") {
    WorkoutDetailSheet(workout: {
        let workout = WorkoutSession()
        workout.exerciseName = "Bench Press"
        workout.sets = 4
        workout.reps = 8
        workout.weightKg = 80
        workout.caloriesBurned = 150
        return workout
    }())
}

#Preview("LiveWorkout Detail") {
    LiveWorkoutDetailSheet(workout: {
        let workout = LiveWorkout(
            name: "Push Day",
            workoutType: .strength,
            targetMuscleGroups: [.chest, .shoulders, .triceps]
        )
        workout.completedAt = Date()
        return workout
    }())
}
