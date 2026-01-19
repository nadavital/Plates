//
//  ExerciseCard.swift
//  Trai
//
//  Exercise card component with sets for live workout tracking
//

import SwiftUI

// MARK: - Exercise Card

struct ExerciseCard: View {
    let entry: LiveWorkoutEntry
    let lastPerformance: ExerciseHistory?
    let personalRecord: ExerciseHistory?
    let usesMetricWeight: Bool
    let onAddSet: () -> Void
    let onRemoveSet: (Int) -> Void
    let onUpdateSet: (Int, Int?, Double?, String?) -> Void
    let onToggleWarmup: (Int) -> Void
    var onDeleteExercise: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false

    private var weightUnit: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    private var lastTimeDisplay: String? {
        guard let last = lastPerformance,
              last.bestSetWeightKg > 0 else { return nil }

        let sets = last.totalSets
        let reps = last.bestSetReps
        let weightKg = last.bestSetWeightKg
        let displayWeight = usesMetricWeight ? weightKg : weightKg * 2.20462
        let weight = Int(displayWeight)

        return "Last: \(sets)×\(reps) @ \(weight)\(weightUnit)"
    }

    private var prDisplay: String? {
        guard let pr = personalRecord,
              pr.bestSetWeightKg > 0 else { return nil }

        let weightKg = pr.bestSetWeightKg
        let displayWeight = usesMetricWeight ? weightKg : weightKg * 2.20462
        let weight = Int(displayWeight)
        let reps = pr.bestSetReps

        return "PR: \(weight)\(weightUnit) × \(reps)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.exerciseName)
                                .font(.headline)

                            HStack(spacing: 8) {
                                Text("\(entry.sets.count) sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let lastTime = lastTimeDisplay {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    Text(lastTime)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }

                                if let pr = prDisplay {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    HStack(spacing: 2) {
                                        Image(systemName: "trophy.fill")
                                            .font(.caption2)
                                        Text(pr)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Delete exercise button (optional)
                if onDeleteExercise != nil {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove Exercise", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }

            // Sets list
            if isExpanded {
                VStack(spacing: 8) {
                    // Header row
                    HStack {
                        Text("SET")
                            .frame(width: 40, alignment: .leading)
                        Text("WEIGHT")
                            .frame(width: 80)
                        Text("REPS")
                            .frame(width: 60)
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    // Set rows
                    ForEach(entry.sets.indices, id: \.self) { index in
                        SetRow(
                            setNumber: index + 1,
                            set: entry.sets[index],
                            usesMetricWeight: usesMetricWeight,
                            onUpdateReps: { reps in onUpdateSet(index, reps, nil, nil) },
                            onUpdateWeight: { weight in onUpdateSet(index, nil, weight, nil) },
                            onUpdateNotes: { notes in onUpdateSet(index, nil, nil, notes) },
                            onToggleWarmup: { onToggleWarmup(index) },
                            onDelete: { onRemoveSet(index) }
                        )
                    }

                    // Add set button
                    Button(action: onAddSet) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Set")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .confirmationDialog(
            "Remove \(entry.exerciseName)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                onDeleteExercise?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the exercise and all its sets from this workout.")
        }
    }
}

// MARK: - Set Row

struct SetRow: View {
    let setNumber: Int
    let set: LiveWorkoutEntry.SetData
    let usesMetricWeight: Bool
    let onUpdateReps: (Int) -> Void
    let onUpdateWeight: (Double) -> Void
    let onUpdateNotes: (String) -> Void
    let onToggleWarmup: () -> Void
    let onDelete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var notesText: String = ""
    @State private var showNotesField = false
    @FocusState private var isWeightFocused: Bool
    @FocusState private var isRepsFocused: Bool
    @FocusState private var isNotesFocused: Bool

    private var weightUnit: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Set number / warmup indicator
                Button(action: onToggleWarmup) {
                    Text(set.isWarmup ? "W" : "\(setNumber)")
                        .font(.subheadline)
                        .bold()
                        .frame(width: 32, height: 32)
                        .background(set.isWarmup ? Color.orange.opacity(0.2) : Color(.tertiarySystemFill))
                        .foregroundStyle(set.isWarmup ? .orange : .primary)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)

                // Weight input
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(cornerRadius: 8))
                    .focused($isWeightFocused)
                    .onChange(of: weightText) { _, newValue in
                        if let weight = Double(newValue) {
                            // Convert to kg if user entered lbs
                            let weightKg = usesMetricWeight ? weight : weight / 2.20462
                            onUpdateWeight(weightKg)
                        }
                    }

                Text(weightUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Reps input
                TextField("0", text: $repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(cornerRadius: 8))
                    .focused($isRepsFocused)
                    .onChange(of: repsText) { _, newValue in
                        if let reps = Int(newValue) {
                            onUpdateReps(reps)
                        }
                    }

                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Notes toggle button
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showNotesField.toggle()
                        if showNotesField {
                            isNotesFocused = true
                        }
                    }
                } label: {
                    Image(systemName: set.notes.isEmpty ? "note.text.badge.plus" : "note.text")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(set.notes.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Inline notes text field (expands below)
            if showNotesField || !set.notes.isEmpty {
                TextField("Add a note...", text: $notesText, axis: .vertical)
                    .font(.caption)
                    .lineLimit(1...3)
                    .padding(8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(.leading, 40)
                    .focused($isNotesFocused)
                    .onChange(of: notesText) { _, newValue in
                        onUpdateNotes(newValue)
                    }
                    .onAppear {
                        notesText = set.notes
                    }
            }
        }
        .onAppear {
            // Convert kg to display unit if needed
            let displayWeight = usesMetricWeight ? set.weightKg : set.weightKg * 2.20462
            weightText = displayWeight > 0 ? formatWeight(displayWeight) : ""
            repsText = set.reps > 0 ? "\(set.reps)" : ""
            notesText = set.notes
            showNotesField = !set.notes.isEmpty
        }
        .onChange(of: usesMetricWeight) { _, newUsesMetric in
            // When unit preference changes, re-display the weight in new unit
            if set.weightKg > 0 {
                let displayWeight = newUsesMetric ? set.weightKg : set.weightKg * 2.20462
                weightText = formatWeight(displayWeight)
            }
        }
    }

    /// Format weight to show whole numbers cleanly (80 not 80.0)
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Preview

#Preview {
    ExerciseCard(
        entry: {
            let entry = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
            entry.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 60, completed: false, isWarmup: true))
            entry.addSet(LiveWorkoutEntry.SetData(reps: 8, weightKg: 70, completed: false, isWarmup: false))
            entry.addSet(LiveWorkoutEntry.SetData(reps: 6, weightKg: 80, completed: false, isWarmup: false))
            return entry
        }(),
        lastPerformance: nil,
        personalRecord: nil,
        usesMetricWeight: true,
        onAddSet: {},
        onRemoveSet: { _ in },
        onUpdateSet: { _, _, _, _ in },
        onToggleWarmup: { _ in }
    )
    .padding()
}
