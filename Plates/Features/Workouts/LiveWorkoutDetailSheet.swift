//
//  LiveWorkoutDetailSheet.swift
//  Plates
//
//  Detailed view of a completed live workout
//

import SwiftUI

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

struct StatPill: View {
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

struct LiveWorkoutExerciseCard: View {
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

struct SetDetailRow: View {
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
