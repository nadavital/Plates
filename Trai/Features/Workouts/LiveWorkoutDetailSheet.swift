//
//  LiveWorkoutDetailSheet.swift
//  Trai
//
//  Detailed view of a completed live workout
//

import SwiftUI
import SwiftData

// MARK: - Identifiable String Wrapper

private struct IdentifiableExercise: Identifiable {
    let id: String
    var name: String { id }
}

struct LiveWorkoutDetailSheet: View {
    @Bindable var workout: LiveWorkout
    var useLbs: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse)
    private var allExerciseHistory: [ExerciseHistory]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var isEditing = false
    @State private var selectedExercise: IdentifiableExercise?
    @State private var showingExercisePicker = false
    @State private var originalEntryIDs: Set<UUID> = []

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

    private var volumePRMode: UserProfile.VolumePRMode {
        profiles.first?.volumePRModeValue ?? .perSet
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

                    if isEditing {
                        editActionsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if originalEntryIDs.isEmpty {
                    originalEntryIDs = Set((workout.entries ?? []).map(\.id))
                }
            }
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
                            originalEntryIDs = Set((workout.entries ?? []).map(\.id))
                            HapticManager.success()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = false
                            }
                        }
                        .labelStyle(.iconOnly)
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
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $selectedExercise) { exercise in
                exercisePRSheet(for: exercise.name)
                    .traiSheetBranding()
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExerciseListView(targetMuscleGroups: targetExerciseMuscleGroups) { exercise in
                    addExercise(exercise)
                }
            }
        }
        .traiSheetBranding()
    }

    /// Build the PR detail sheet for a given exercise name
    @ViewBuilder
    private func exercisePRSheet(for exerciseName: String) -> some View {
        let history = allExerciseHistory.filter { $0.exerciseName == exerciseName }
        let exercise = exercises.first { $0.name == exerciseName }

        if let pr = ExercisePR.from(
            exerciseName: exerciseName,
            history: history,
            muscleGroup: exercise?.targetMuscleGroup,
            volumePRMode: volumePRMode
        ) {
            PRDetailSheet(
                pr: pr,
                history: history,
                useLbs: useLbs,
                volumePRMode: volumePRMode,
                onDeleteAll: {}
            )
        } else {
            // No history yet - show simple info
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
                    LiveWorkoutExerciseCard(
                        entry: entry,
                        useLbs: useLbs,
                        isEditing: isEditing,
                        onTap: {
                            selectedExercise = IdentifiableExercise(id: entry.exerciseName)
                        },
                        onAddSet: {
                            addSet(to: entry)
                        },
                        onRemoveExercise: {
                            removeExercise(entry)
                        },
                        onToggleWarmup: { setIndex in
                            toggleWarmup(at: setIndex, in: entry)
                        },
                        onRemoveSet: { setIndex in
                            removeSet(at: setIndex, from: entry)
                        }
                    )
                }
            }
        }
    }

    private var editActionsSection: some View {
        Button {
            showingExercisePicker = true
        } label: {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.traiPrimary())
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

    private var targetExerciseMuscleGroups: [Exercise.MuscleGroup] {
        var seen = Set<Exercise.MuscleGroup>()
        return workout.muscleGroups.compactMap { muscle in
            let mapped = muscle.toExerciseMuscleGroup
            guard !seen.contains(mapped) else { return nil }
            seen.insert(mapped)
            return mapped
        }
    }

    private func addExercise(_ exercise: Exercise) {
        if workout.entries == nil {
            workout.entries = []
        }

        let newOrder = workout.entries?.count ?? 0
        let entry = LiveWorkoutEntry(exercise: exercise, orderIndex: newOrder)
        let lastPerformance = allExerciseHistory.first { $0.exerciseName == exercise.name }

        let suggestedReps = lastPerformance?.repPatternArray.first ?? lastPerformance?.bestSetReps ?? 10
        let suggestedWeightKg = lastPerformance?.weightPatternArray.first ?? lastPerformance?.bestSetWeightKg ?? 0
        let cleanWeight = WeightUtility.cleanWeightFromKg(suggestedWeightKg)

        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: true,
            isWarmup: false
        ))

        modelContext.insert(entry)
        workout.entries?.append(entry)
        HapticManager.selectionChanged()
    }

    private func removeExercise(_ entry: LiveWorkoutEntry) {
        workout.entries?.removeAll { $0.id == entry.id }

        for (index, updatedEntry) in (workout.entries ?? []).enumerated() {
            updatedEntry.orderIndex = index
        }

        modelContext.delete(entry)
        HapticManager.selectionChanged()
    }

    private func addSet(to entry: LiveWorkoutEntry) {
        let currentSetIndex = entry.sets.count
        let lastSet = entry.sets.last

        let lastPerformance = allExerciseHistory.first { $0.exerciseName == entry.exerciseName }
        let repPattern = lastPerformance?.repPatternArray ?? []
        let weightPattern = lastPerformance?.weightPatternArray ?? []

        let suggestedReps: Int
        if currentSetIndex < repPattern.count {
            suggestedReps = repPattern[currentSetIndex]
        } else {
            suggestedReps = lastSet?.reps ?? lastPerformance?.bestSetReps ?? 10
        }

        let cleanWeight: CleanWeight
        if currentSetIndex < weightPattern.count {
            cleanWeight = WeightUtility.cleanWeightFromKg(weightPattern[currentSetIndex])
        } else if let lastSet {
            cleanWeight = CleanWeight(kg: lastSet.weightKg, lbs: lastSet.weightLbs)
        } else {
            cleanWeight = .zero
        }

        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: true,
            isWarmup: false
        ))
        HapticManager.selectionChanged()
    }

    private func removeSet(at index: Int, from entry: LiveWorkoutEntry) {
        guard index < entry.sets.count, entry.sets.count > 1 else { return }
        entry.removeSet(at: index)
        HapticManager.selectionChanged()
    }

    private func toggleWarmup(at index: Int, in entry: LiveWorkoutEntry) {
        guard index < entry.sets.count else { return }
        var set = entry.sets[index]
        set.isWarmup.toggle()
        entry.updateSet(at: index, with: set)
        HapticManager.selectionChanged()
    }

    /// Sync ExerciseHistory entries when workout is edited
    private func syncExerciseHistory() {
        guard let entries = workout.entries else { return }
        let currentEntryIDs = Set(entries.map(\.id))

        // Remove stale history for entries deleted in this sheet.
        let removedEntryIDs = originalEntryIDs.subtracting(currentEntryIDs)
        if !removedEntryIDs.isEmpty {
            for history in allExerciseHistory {
                if let sourceId = history.sourceWorkoutEntryId, removedEntryIDs.contains(sourceId) {
                    modelContext.delete(history)
                }
            }
        }

        for entry in entries {
            // Find existing history entry for this workout entry
            if let history = allExerciseHistory.first(where: { $0.sourceWorkoutEntryId == entry.id }) {
                // Delete history if the edited exercise has no completed working sets.
                guard let completedSets = entry.completedSets, !completedSets.isEmpty else {
                    modelContext.delete(history)
                    continue
                }

                // Update history with current entry data
                if let best = entry.bestSet {
                    history.bestSetWeightKg = WeightUtility.round(best.weightKg, unit: .kg)
                    history.bestSetWeightLbs = WeightUtility.round(best.weightLbs, unit: .lbs)
                    history.bestSetReps = best.reps
                }
                history.exerciseId = entry.exerciseId
                history.exerciseName = entry.exerciseName
                history.performedAt = workout.completedAt ?? workout.startedAt
                history.totalVolume = entry.totalVolume
                history.totalSets = completedSets.count
                history.totalReps = entry.totalReps
                history.estimatedOneRepMax = entry.estimatedOneRepMax

                // Update rep and weight patterns
                history.repPattern = completedSets.map { "\($0.reps)" }.joined(separator: ",")
                history.weightPattern = completedSets.map { set -> String in
                    let rounded = WeightUtility.round(set.weightKg, unit: .kg)
                    return String(format: "%.1f", rounded)
                }.joined(separator: ",")
            } else if entry.completedSets?.isEmpty == false {
                let newHistory = ExerciseHistory(from: entry, performedAt: workout.completedAt ?? workout.startedAt)
                modelContext.insert(newHistory)
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
    var onTap: (() -> Void)?
    var onAddSet: (() -> Void)?
    var onRemoveExercise: (() -> Void)?
    var onToggleWarmup: ((Int) -> Void)?
    var onRemoveSet: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Exercise name with chevron when tappable
            HStack {
                Text(entry.exerciseName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if !isEditing && onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Sets as rows
            if !entry.sets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(entry.sets.indices, id: \.self) { index in
                        if isEditing {
                            EditableSetRow(
                                entry: entry,
                                setIndex: index,
                                useLbs: useLbs,
                                canRemoveSet: entry.sets.count > 1,
                                onToggleWarmup: {
                                    onToggleWarmup?(index)
                                },
                                onRemoveSet: {
                                    onRemoveSet?(index)
                                }
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

            if isEditing {
                HStack(spacing: 12) {
                    Button {
                        onAddSet?()
                    } label: {
                        Label("Add Set", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(role: .destructive) {
                        onRemoveExercise?()
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onTap?()
            }
        }
    }
}

// MARK: - Editable Set Row

struct EditableSetRow: View {
    @Bindable var entry: LiveWorkoutEntry
    let setIndex: Int
    let useLbs: Bool
    var canRemoveSet: Bool = true
    var onToggleWarmup: (() -> Void)?
    var onRemoveSet: (() -> Void)?

    @State private var repsText: String = ""
    @State private var weightText: String = ""

    private var set: LiveWorkoutEntry.SetData {
        entry.sets[setIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        let unit = WeightUnit(usesMetric: !useLbs)
                        if let cleanWeight = WeightUtility.parseToCleanWeight(newValue, inputUnit: unit) {
                            var updated = set
                            updated.weightKg = cleanWeight.kg
                            updated.weightLbs = cleanWeight.lbs
                            entry.updateSet(at: setIndex, with: updated)
                        }
                    }

                Text(useLbs ? "lbs" : "kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    onToggleWarmup?()
                } label: {
                    Label(set.isWarmup ? "Set as Working" : "Set as Warm-up", systemImage: "flame")
                }
                .buttonStyle(.borderless)

                Spacer()

                if canRemoveSet {
                    Button(role: .destructive) {
                        onRemoveSet?()
                    } label: {
                        Label("Remove Set", systemImage: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .onAppear {
            repsText = set.reps > 0 ? "\(set.reps)" : ""
            // Use stored clean value directly
            let displayWeight = set.displayWeight(usesMetric: !useLbs)
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
        // Weight is stored in kg, convert for display
        let displayValue = useLbs ? weight * WeightUtility.kgToLbs : weight
        let rounded = WeightUtility.round(displayValue, unit: useLbs ? .lbs : .kg)
        let unit = useLbs ? "lbs" : "kg"
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded)) \(unit)"
        }
        return String(format: "%.1f %@", rounded, unit)
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
