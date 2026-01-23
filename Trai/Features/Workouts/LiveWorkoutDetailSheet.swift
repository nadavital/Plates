//
//  LiveWorkoutDetailSheet.swift
//  Trai
//
//  Detailed view of a completed live workout
//

import SwiftUI
import SwiftData

struct LiveWorkoutDetailSheet: View {
    @Bindable var workout: LiveWorkout
    var useLbs: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allExerciseHistory: [ExerciseHistory]
    @State private var isEditing = false

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
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    // Edit mode: Cancel (left) and Save (right)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = false
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            syncExerciseHistory()
                            try? modelContext.save()
                            HapticManager.success()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = false
                            }
                        }
                        .tint(.accentColor)
                    }
                } else {
                    // View mode: Edit (left) and Done (right)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit", systemImage: "pencil") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = true
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            dismiss()
                        }
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
            HStack(spacing: 16) {
                if durationMinutes > 0 {
                    StatPill(icon: "clock.fill", value: formatDuration(Double(durationMinutes)), label: "time", color: .blue)
                }

                StatPill(icon: "dumbbell.fill", value: "\(exerciseCount)", label: exerciseCount == 1 ? "exercise" : "exercises", color: .green)
                StatPill(icon: "square.stack.3d.up.fill", value: "\(totalSets)", label: totalSets == 1 ? "set" : "sets", color: .orange)

                // Apple Watch merged data
                if let calories = workout.healthKitCalories {
                    StatPill(icon: "applewatch", value: "\(Int(calories))", label: "kcal", color: .red)
                }
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
                    LiveWorkoutExerciseCard(entry: entry, useLbs: useLbs, isEditing: isEditing)
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

    /// Sync ExerciseHistory entries when workout is edited
    private func syncExerciseHistory() {
        guard let entries = workout.entries else { return }

        for entry in entries {
            // Find existing history entry for this workout entry
            if let history = allExerciseHistory.first(where: { $0.sourceWorkoutEntryId == entry.id }) {
                // Update history with current entry data
                if let best = entry.bestSet {
                    history.bestSetWeightKg = (best.weightKg * 2).rounded() / 2
                    history.bestSetReps = best.reps
                }
                history.totalVolume = entry.totalVolume
                history.totalSets = entry.completedSets?.count ?? 0
                history.totalReps = entry.totalReps
                history.estimatedOneRepMax = entry.estimatedOneRepMax

                // Update rep and weight patterns
                if let completedSets = entry.completedSets, !completedSets.isEmpty {
                    history.repPattern = completedSets.map { "\($0.reps)" }.joined(separator: ",")
                    history.weightPattern = completedSets.map { set -> String in
                        let rounded = (set.weightKg * 2).rounded() / 2
                        return String(format: "%.1f", rounded)
                    }.joined(separator: ",")
                }
            }
        }
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
    @Bindable var entry: LiveWorkoutEntry
    let useLbs: Bool
    var isEditing: Bool = false

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
                        if isEditing {
                            EditableSetRow(
                                entry: entry,
                                setIndex: index,
                                useLbs: useLbs
                            )
                        } else {
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

// MARK: - Editable Set Row

struct EditableSetRow: View {
    @Bindable var entry: LiveWorkoutEntry
    let setIndex: Int
    let useLbs: Bool

    @State private var repsText: String = ""
    @State private var weightText: String = ""

    private var set: LiveWorkoutEntry.SetData {
        entry.sets[setIndex]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set number indicator
            Text(set.isWarmup ? "W" : "\(setIndex + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 24, height: 24)
                .background(set.isWarmup ? Color.orange.opacity(0.2) : Color(.tertiarySystemFill))
                .foregroundStyle(set.isWarmup ? .orange : .secondary)
                .clipShape(.circle)

            // Reps input
            TextField("0", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 50)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 6))
                .onChange(of: repsText) { _, newValue in
                    if let reps = Int(newValue) {
                        var updated = set
                        updated.reps = reps
                        entry.updateSet(at: setIndex, with: updated)
                    }
                }

            Text("reps")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Weight input
            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 6))
                .onChange(of: weightText) { _, newValue in
                    if let weight = Double(newValue) {
                        var updated = set
                        updated.weightKg = useLbs ? weight / 2.20462 : weight
                        entry.updateSet(at: setIndex, with: updated)
                    }
                }

            Text(useLbs ? "lbs" : "kg")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            repsText = set.reps > 0 ? "\(set.reps)" : ""
            let displayWeight = useLbs ? set.weightKg * 2.20462 : set.weightKg
            weightText = displayWeight > 0 ? formatWeight(displayWeight) : ""
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
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
