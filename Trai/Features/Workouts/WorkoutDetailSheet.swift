//
//  WorkoutDetailSheet.swift
//  Trai
//
//  Detailed view of a completed workout session
//

import SwiftUI
import SwiftData

struct WorkoutDetailSheet: View {
    let workout: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse) private var allExerciseHistory: [ExerciseHistory]
    @Query private var profiles: [UserProfile]

    private var usesMetricExerciseWeight: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    private var weightUnit: String {
        usesMetricExerciseWeight ? "kg" : "lbs"
    }

    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: usesMetricExerciseWeight)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    private func displayVolume(_ volumeKg: Double) -> Int {
        let display = usesMetricExerciseWeight ? volumeKg : (volumeKg * WeightUtility.kgToLbs)
        return Int(display.rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Stats summary
                    statsSection

                    // PR highlights (if any)
                    if !prHighlights.isEmpty {
                        prSection
                    }

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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
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
        .traiCard()
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
                        value: "\(displayWeight(weight))",
                        label: weightUnit,
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
                        DetailRow(label: "Total Volume", value: "\(displayVolume(volume)) \(weightUnit)")
                    }
                } else {
                    DetailRow(label: "Type", value: workout.healthKitWorkoutType?.capitalized ?? "Cardio")
                    if let avgHR = workout.averageHeartRate {
                        DetailRow(label: "Avg Heart Rate", value: "\(avgHR) bpm")
                    }
                }

                DetailRow(label: "Logged", value: workout.loggedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .traiCard()
        }
    }

    // MARK: - PR Section

    private struct PRHighlight: Identifiable {
        let id = UUID()
        let kind: PRMetricKind
        let label: String
        let value: String
    }

    private var prHighlights: [PRHighlight] {
        guard workout.isStrengthTraining else { return [] }

        let exerciseName = workout.displayName
        let previousEntries = allExerciseHistory.filter {
            $0.exerciseName == exerciseName && $0.performedAt < workout.loggedAt
        }
        guard !previousEntries.isEmpty else { return [] }

        var highlights: [PRHighlight] = []

        if let weight = workout.weightKg,
           weight > 0,
           weight > (previousEntries.map(\.bestSetWeightKg).max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .weight,
                label: PRMetricKind.weight.label,
                value: "\(displayWeight(weight)) \(weightUnit)",
            ))
        }

        if workout.reps > 0,
           workout.reps > (previousEntries.map(\.bestSetReps).max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .reps,
                label: PRMetricKind.reps.label,
                value: "\(workout.reps) reps",
            ))
        }

        if let volume = workout.totalVolume,
           volume > 0,
           volume > (previousEntries.map(\.totalVolume).max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .volume,
                label: PRMetricKind.volume.label,
                value: "\(displayVolume(volume)) \(weightUnit)",
            ))
        }

        return highlights
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Personal Records")
                    .font(.headline)
            }

            VStack(spacing: 8) {
                ForEach(prHighlights) { pr in
                    HStack(spacing: 10) {
                        Image(systemName: pr.kind.iconName)
                            .foregroundStyle(pr.kind.color)
                        Text(pr.label)
                            .fontWeight(.medium)
                        Spacer()
                        Text(pr.value)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 10))
                }
            }
            .traiCard()
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .traiCard()
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
        .traiCard()
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
