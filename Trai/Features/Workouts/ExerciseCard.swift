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
    let onUpdateSet: (Int, Int?, Double?, Double?, String?, WeightUnit?) -> Void  // (index, reps, kg, lbs, notes, preferred unit override)
    let onToggleWarmup: (Int) -> Void
    var onDeleteExercise: (() -> Void)? = nil
    var onChangeExercise: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false

    private var weightUnit: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    private var lastTimeDisplay: String? {
        guard let last = lastPerformance,
              last.bestSetWeightKg > 0 else { return nil }

        let reps = last.bestSetReps
        let unit = WeightUnit(usesMetric: usesMetricWeight)
        let weight = WeightUtility.displayInt(last.bestSetWeightKg, displayUnit: unit)

        return "Last: \(weight) \(weightUnit) \u{00D7} \(reps)"
    }

    private var prDisplay: String? {
        guard let pr = personalRecord,
              pr.bestSetWeightKg > 0 else { return nil }

        let unit = WeightUnit(usesMetric: usesMetricWeight)
        let weight = WeightUtility.displayInt(pr.bestSetWeightKg, displayUnit: unit)
        let reps = pr.bestSetReps

        return "PR: \(weight) \(weightUnit) \u{00D7} \(reps)"
    }

    var body: some View {
        let sets = entry.sets

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.exerciseName)
                                .font(.headline)

                            // Equipment name if available
                            if let equipment = entry.equipmentName, !equipment.isEmpty {
                                Text("@ \(equipment)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text("\(sets.count) sets")
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

                                // Show historical PR (live PR detection removed - shown in summary only)
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
                                    .foregroundStyle(Color.accentColor)
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

                // Exercise options menu
                if onDeleteExercise != nil || onChangeExercise != nil {
                    Menu {
                        if onChangeExercise != nil {
                            Button {
                                onChangeExercise?()
                            } label: {
                                Label("Change Exercise", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        if onDeleteExercise != nil {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Remove Exercise", systemImage: "trash")
                            }
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
                            .frame(width: ExerciseSetLayout.setColumnWidth, alignment: .leading)
                        Text("WEIGHT")
                            .frame(width: ExerciseSetLayout.weightColumnWidth)
                        Text("REPS")
                            .frame(width: ExerciseSetLayout.repsColumnWidth)
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    // Set rows
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        SetRow(
                            setNumber: index + 1,
                            set: set,
                            usesMetricWeight: usesMetricWeight,
                            previousSetWeight: index > 0 ? sets[index - 1].weightKg : nil,
                            onUpdateReps: { reps in onUpdateSet(index, reps, nil, nil, nil, set.preferredWeightUnit) },
                            onUpdateWeight: { kg, lbs in onUpdateSet(index, nil, kg, lbs, nil, set.preferredWeightUnit) },
                            onUpdateNotes: { notes in onUpdateSet(index, nil, nil, nil, notes, set.preferredWeightUnit) },
                            onUpdateWeightUnit: { preferredUnit in
                                onUpdateSet(index, nil, nil, nil, nil, preferredUnit)
                            },
                            onToggleWarmup: { onToggleWarmup(index) },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    onRemoveSet(index)
                                }
                            }
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
                    .accessibilityIdentifier("liveWorkoutAddSetButton")
                    .padding(.top, 4)
                }
            }
        }
        .traiCard()
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

private enum ExerciseSetLayout {
    static let setColumnWidth: CGFloat = 40
    static let weightFieldWidth: CGFloat = 70
    static let weightUnitWidth: CGFloat = 36
    static let weightColumnWidth: CGFloat = weightFieldWidth + 8 + weightUnitWidth
    static let repsFieldWidth: CGFloat = 50
    static let repsLabelWidth: CGFloat = 36
    static let repsColumnWidth: CGFloat = repsFieldWidth + 8 + repsLabelWidth
}

// MARK: - Set Row

struct SetRow: View {
    let setNumber: Int
    let set: LiveWorkoutEntry.SetData
    let usesMetricWeight: Bool
    let previousSetWeight: Double?  // Previous set's weight for jump detection
    let onUpdateReps: (Int) -> Void
    let onUpdateWeight: (Double, Double) -> Void  // (kg, lbs)
    let onUpdateNotes: (String) -> Void
    let onUpdateWeightUnit: (WeightUnit?) -> Void
    let onToggleWarmup: () -> Void
    let onDelete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var notesText: String = ""
    @State private var showNotesField = false
    @State private var isUpdatingFromUnitChange = false
    @State private var showWeightJumpConfirmation = false
    @State private var pendingWeight: CleanWeight?
    @State private var currentDisplayUnit: WeightUnit = .kg
    @FocusState private var isWeightFocused: Bool
    @FocusState private var isRepsFocused: Bool
    @FocusState private var isNotesFocused: Bool

    // Debounce tasks for input fields
    @State private var weightDebounceTask: Task<Void, Never>?
    @State private var repsDebounceTask: Task<Void, Never>?
    @State private var notesDebounceTask: Task<Void, Never>?

    // Debounce delay in seconds
    private let debounceDelay: Duration = .milliseconds(500)
    
    // Weight jump detection thresholds
    private let percentageThreshold: Double = 0.5  // 50% increase
    private let absoluteThresholdKg: Double = 25.0  // 25kg / ~55lbs absolute jump

    private var defaultDisplayUnit: WeightUnit {
        WeightUnit(usesMetric: usesMetricWeight)
    }

    private var effectiveDisplayUnit: WeightUnit {
        get {
            set.preferredWeightUnit ?? defaultDisplayUnit
        }
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
                        .background(set.isWarmup ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                        .foregroundStyle(set.isWarmup ? Color.accentColor : .primary)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .frame(width: ExerciseSetLayout.setColumnWidth, alignment: .leading)

                // Weight input
                HStack(spacing: 8) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: ExerciseSetLayout.weightFieldWidth)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 8))
                        .focused($isWeightFocused)
                        .onChange(of: weightText) { _, newValue in
                            guard !isUpdatingFromUnitChange else { return }
                            weightDebounceTask?.cancel()
                            weightDebounceTask = Task { @MainActor in
                                try? await Task.sleep(for: debounceDelay)
                                guard !Task.isCancelled else { return }
                                commitWeight(newValue)
                            }
                        }
                        .onChange(of: isWeightFocused) { _, focused in
                            if !focused {
                                weightDebounceTask?.cancel()
                                commitWeight(weightText)
                            }
                        }

                    Button {
                        toggleDisplayUnit()
                    } label: {
                        Text(currentDisplayUnit.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: ExerciseSetLayout.weightUnitWidth)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: ExerciseSetLayout.weightColumnWidth)

                Spacer()

                // Reps input
                HStack(spacing: 8) {
                    TextField("0", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: ExerciseSetLayout.repsFieldWidth)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 8))
                        .focused($isRepsFocused)
                        .onChange(of: repsText) { _, newValue in
                            repsDebounceTask?.cancel()
                            repsDebounceTask = Task { @MainActor in
                                try? await Task.sleep(for: debounceDelay)
                                guard !Task.isCancelled else { return }
                                commitReps(newValue)
                            }
                        }
                        .onChange(of: isRepsFocused) { _, focused in
                            if !focused {
                                repsDebounceTask?.cancel()
                                commitReps(repsText)
                            }
                        }

                    Text("reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: ExerciseSetLayout.repsLabelWidth, alignment: .leading)
                }
                .frame(width: ExerciseSetLayout.repsColumnWidth)

                // Notes toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                        // Cancel any pending debounce
                        notesDebounceTask?.cancel()
                        // Start new debounced update
                        notesDebounceTask = Task { @MainActor in
                            try? await Task.sleep(for: debounceDelay)
                            guard !Task.isCancelled else { return }
                            onUpdateNotes(newValue)
                        }
                    }
                    .onChange(of: isNotesFocused) { _, focused in
                        // Commit immediately when focus leaves
                        if !focused {
                            notesDebounceTask?.cancel()
                            onUpdateNotes(notesText)
                        }
                    }
                    .onAppear {
                        notesText = set.notes
                    }
            }
        }
        .onAppear {
            currentDisplayUnit = effectiveDisplayUnit
            let displayWeight = displayWeightValue(for: effectiveDisplayUnit)
            weightText = displayWeight > 0 ? formatWeight(displayWeight) : ""
            repsText = set.reps > 0 ? "\(set.reps)" : ""
            notesText = set.notes
            showNotesField = !set.notes.isEmpty
        }
        .onChange(of: effectiveDisplayUnit) { _, newUnit in
            currentDisplayUnit = newUnit
            let displayWeight = displayWeightValue(for: newUnit)
            isUpdatingFromUnitChange = true
            weightText = displayWeight > 0 ? formatWeight(displayWeight) : ""
            Task { @MainActor in
                isUpdatingFromUnitChange = false
            }
        }
        .confirmationDialog(
            "Large Weight Increase",
            isPresented: $showWeightJumpConfirmation,
            titleVisibility: .visible
        ) {
            Button("Use \(pendingWeight?.formatted(unit: currentDisplayUnit, showUnit: true) ?? "")") {
                if let weight = pendingWeight {
                    onUpdateWeight(weight.kg, weight.lbs)
                }
                pendingWeight = nil
            }
            Button("Cancel", role: .cancel) {
                let displayWeight = displayWeightValue(for: currentDisplayUnit)
                weightText = displayWeight > 0 ? formatWeight(displayWeight) : ""
                pendingWeight = nil
            }
        } message: {
            if let weight = pendingWeight {
                let previousDisplay = previousSetWeight.map { WeightUtility.format($0, displayUnit: currentDisplayUnit, showUnit: true) } ?? WeightUtility.format(set.weightKg, displayUnit: currentDisplayUnit, showUnit: true)
                Text("This is a significant increase from \(previousDisplay) to \(weight.formatted(unit: currentDisplayUnit, showUnit: true)). Is this correct?")
            }
        }
    }

    /// Commit weight value to parent (called after debounce or on focus loss)
    private func commitWeight(_ value: String) {
        guard let cleanWeight = WeightUtility.parseToCleanWeight(value, inputUnit: currentDisplayUnit) else { return }
        
        // Check for large weight jump
        if isLargeWeightJump(newWeightKg: cleanWeight.kg) {
            pendingWeight = cleanWeight
            showWeightJumpConfirmation = true
        } else {
            onUpdateWeight(cleanWeight.kg, cleanWeight.lbs)
        }
    }
    
    /// Check if the new weight represents a suspiciously large jump
    private func isLargeWeightJump(newWeightKg: Double) -> Bool {
        // Get the reference weight (previous set or current set's original value)
        let referenceWeightKg: Double
        if let previousSetWeight, previousSetWeight > 0 {
            referenceWeightKg = previousSetWeight
        } else if set.weightKg > 0 {
            referenceWeightKg = set.weightKg
        } else {
            // No reference weight, can't detect a jump
            return false
        }
        
        // Skip if new weight is lower (decreasing weight is normal)
        guard newWeightKg > referenceWeightKg else { return false }
        
        // Skip small weights (under 10kg) - relative jumps don't matter as much
        guard referenceWeightKg >= 10 else { return false }
        
        let absoluteJump = newWeightKg - referenceWeightKg
        let percentageJump = absoluteJump / referenceWeightKg
        
        // Flag if jump exceeds both thresholds (must be significant in both relative and absolute terms)
        return percentageJump >= percentageThreshold && absoluteJump >= absoluteThresholdKg
    }

    /// Commit reps value to parent (called after debounce or on focus loss)
    private func commitReps(_ value: String) {
        if let reps = Int(value) {
            onUpdateReps(reps)
        }
    }

    /// Format weight to show whole numbers cleanly (80 not 80.0)
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }

    private func displayWeightValue(for unit: WeightUnit) -> Double {
        unit == .kg ? set.weightKg : set.weightLbs
    }

    private func toggleDisplayUnit() {
        let toggled: WeightUnit = currentDisplayUnit == .kg ? .lbs : .kg
        let override = toggled == defaultDisplayUnit ? nil : toggled
        onUpdateWeightUnit(override)
    }
}

// MARK: - Preview

#Preview {
    ExerciseCard(
        entry: {
            let entry = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
            entry.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 60, lbs: 132.5), completed: false, isWarmup: true))
            entry.addSet(LiveWorkoutEntry.SetData(reps: 8, weight: CleanWeight(kg: 70, lbs: 155), completed: false, isWarmup: false))
            entry.addSet(LiveWorkoutEntry.SetData(reps: 6, weight: CleanWeight(kg: 80, lbs: 177.5), completed: false, isWarmup: false))
            return entry
        }(),
        lastPerformance: nil,
        personalRecord: nil,
        usesMetricWeight: true,
        onAddSet: {},
        onRemoveSet: { _ in },
        onUpdateSet: { _, _, _, _, _, _ in },
        onToggleWarmup: { _ in }
    )
    .padding()
}
