//
//  LiveWorkoutComponents.swift
//  Plates
//
//  UI components for live workout tracking
//

import SwiftUI

// MARK: - Workout Timer Header

struct WorkoutTimerHeader: View {
    let workoutName: String
    let workoutStartedAt: Date
    let isTimerRunning: Bool
    let totalPauseDuration: TimeInterval
    let totalSets: Int
    let completedSets: Int
    let totalVolume: Double

    var body: some View {
        VStack(spacing: 16) {
            // Workout name and timer
            VStack(spacing: 4) {
                Text(workoutName)
                    .font(.headline)

                // Use TimelineView for smooth, scroll-friendly timer updates
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let elapsed = calculateElapsed(at: context.date)
                    Text(formatTime(elapsed))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }

            // Stats row
            HStack(spacing: 24) {
                TimerStat(
                    value: "\(completedSets)/\(totalSets)",
                    label: "Sets"
                )

                if totalVolume > 0 {
                    TimerStat(
                        value: formatVolume(totalVolume),
                        label: "Volume"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func calculateElapsed(at date: Date) -> TimeInterval {
        guard isTimerRunning else {
            // When paused, show the time at pause
            return date.timeIntervalSince(workoutStartedAt) - totalPauseDuration
        }
        return date.timeIntervalSince(workoutStartedAt) - totalPauseDuration
    }

    private func formatTime(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

// MARK: - Timer Stat

struct TimerStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    let entry: LiveWorkoutEntry
    let lastPerformance: ExerciseHistory?
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
        let weight = Int(last.bestSetWeightKg)

        return "Last: \(sets)×\(reps) @ \(weight)\(weightUnit)"
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
                            onUpdateWeight(weight)
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
            weightText = set.weightKg > 0 ? formatWeight(set.weightKg) : ""
            repsText = set.reps > 0 ? "\(set.reps)" : ""
            notesText = set.notes
            showNotesField = !set.notes.isEmpty
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

// MARK: - Cardio Exercise Card

struct CardioExerciseCard: View {
    let entry: LiveWorkoutEntry
    let onUpdateDuration: (Int) -> Void
    let onUpdateDistance: (Double) -> Void
    let onComplete: () -> Void
    var onDeleteExercise: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false
    @State private var durationMinutes: String = ""
    @State private var durationSeconds: String = ""
    @State private var distanceKm: String = ""

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
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                                Text(entry.exerciseName)
                                    .font(.headline)
                            }

                            if entry.completedAt != nil {
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

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

            // Cardio inputs
            if isExpanded {
                VStack(spacing: 16) {
                    // Duration input
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text("Duration")
                            .font(.subheadline)

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("00", text: $durationMinutes)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 40)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: durationMinutes) { _, _ in
                                    updateDuration()
                                }

                            Text(":")
                                .foregroundStyle(.secondary)

                            TextField("00", text: $durationSeconds)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 40)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: durationSeconds) { _, _ in
                                    updateDuration()
                                }
                        }
                    }

                    // Distance input
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text("Distance")
                            .font(.subheadline)

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("0.00", text: $distanceKm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: distanceKm) { _, newValue in
                                    if let km = Double(newValue) {
                                        onUpdateDistance(km * 1000) // Convert to meters
                                    }
                                }

                            Text("km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Complete button
                    Button(action: onComplete) {
                        HStack {
                            Image(systemName: entry.completedAt != nil ? "checkmark.circle.fill" : "circle")
                            Text(entry.completedAt != nil ? "Completed" : "Mark Complete")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(entry.completedAt != nil ? .green : .accent)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .onAppear {
            // Load existing values
            if let seconds = entry.durationSeconds {
                durationMinutes = "\(seconds / 60)"
                durationSeconds = String(format: "%02d", seconds % 60)
            }
            if let meters = entry.distanceMeters {
                distanceKm = String(format: "%.2f", meters / 1000)
            }
        }
        .confirmationDialog(
            "Remove \(entry.exerciseName)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                onDeleteExercise?()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func updateDuration() {
        let mins = Int(durationMinutes) ?? 0
        let secs = Int(durationSeconds) ?? 0
        onUpdateDuration(mins * 60 + secs)
    }
}

// MARK: - Add Exercise Button

struct AddExerciseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Add Exercise")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Bottom Bar

struct WorkoutBottomBar: View {
    let onEndWorkout: () -> Void
    let onAskTrai: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onAskTrai) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                    Text("Ask Trai")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onEndWorkout) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("End Workout")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Workout Summary Sheet

struct WorkoutSummarySheet: View {
    let workout: LiveWorkout
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Workout Complete!")
                        .font(.title)
                        .bold()

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

                    // Exercises completed
                    if let entries = workout.entries, !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises")
                                .font(.headline)

                            ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                                HStack {
                                    Text(entry.exerciseName)
                                    Spacer()
                                    Text("\(entry.completedSets?.count ?? 0) sets")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
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
                    Button("Done", action: onDismiss)
                }
            }
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

// MARK: - Muscle Group Selector

struct MuscleGroupSelector: View {
    @Binding var selectedMuscles: Set<LiveWorkout.MuscleGroup>
    let isCustomWorkout: Bool

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - tap to expand if custom workout
            Button {
                if isCustomWorkout || selectedMuscles.isEmpty {
                    withAnimation(.snappy) { isExpanded.toggle() }
                    HapticManager.lightTap()
                }
            } label: {
                HStack {
                    if selectedMuscles.isEmpty {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.accent)
                        Text("Select target muscles")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.accent)
                        Text("Targeting")
                            .foregroundStyle(.secondary)

                        // Show selected muscles as chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(selectedMuscles).sorted { $0.displayName < $1.displayName }) { muscle in
                                    Text(muscle.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(.capsule)
                                }
                            }
                        }
                    }

                    Spacer()

                    if isCustomWorkout || selectedMuscles.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)

            // Expanded selection
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Quick presets
                    HStack(spacing: 8) {
                        PresetChip(title: "Push", isSelected: isPushSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.pushMuscles)
                        }
                        PresetChip(title: "Pull", isSelected: isPullSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.pullMuscles)
                        }
                        PresetChip(title: "Legs", isSelected: isLegsSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.legMuscles)
                        }
                    }

                    // Individual muscles
                    FlowLayout(spacing: 8) {
                        ForEach(LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }) { muscle in
                            MuscleSelectChip(
                                muscle: muscle,
                                isSelected: selectedMuscles.contains(muscle)
                            ) {
                                toggleMuscle(muscle)
                            }
                        }
                    }

                    // Done button
                    Button {
                        withAnimation(.snappy) { isExpanded = false }
                    } label: {
                        Text("Done")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .onAppear {
            // Auto-expand for custom workouts with no muscles selected
            if isCustomWorkout && selectedMuscles.isEmpty {
                isExpanded = true
            }
        }
    }

    private var isPushSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pushMuscles).isSubset(of: selectedMuscles)
    }

    private var isPullSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pullMuscles).isSubset(of: selectedMuscles)
    }

    private var isLegsSelected: Bool {
        Set(LiveWorkout.MuscleGroup.legMuscles).isSubset(of: selectedMuscles)
    }

    private func togglePreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        let muscleSet = Set(muscles)
        if muscleSet.isSubset(of: selectedMuscles) {
            selectedMuscles.subtract(muscleSet)
        } else {
            selectedMuscles.formUnion(muscleSet)
        }
        HapticManager.lightTap()
    }

    private func toggleMuscle(_ muscle: LiveWorkout.MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
        HapticManager.selectionChanged()
    }
}

// MARK: - Preset Chip

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Muscle Select Chip

private struct MuscleSelectChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: muscle.iconName)
                    .font(.caption2)
                Text(muscle.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Up Next Suggestion Card

struct UpNextSuggestionCard: View {
    let suggestion: LiveWorkoutViewModel.ExerciseSuggestion
    let lastPerformance: ExerciseHistory?
    let usesMetricWeight: Bool
    let onAdd: () -> Void

    private var weightUnit: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.accent)
                Text("Up Next")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.accent)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.exerciseName)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(suggestion.muscleGroup.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let last = lastPerformance, last.bestSetWeightKg > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("Last: \(last.totalSets)×\(last.bestSetReps) @ \(Int(last.bestSetWeightKg))\(weightUnit)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.accent)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Exercise Suggestion Chip

struct ExerciseSuggestionChip: View {
    let suggestion: LiveWorkoutViewModel.ExerciseSuggestion
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Text(suggestion.exerciseName)
                    .font(.subheadline)
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestions By Muscle Section

struct SuggestionsByMuscleSection: View {
    let suggestionsByMuscle: [String: [LiveWorkoutViewModel.ExerciseSuggestion]]
    let lastPerformances: [String: ExerciseHistory]
    let onAddSuggestion: (LiveWorkoutViewModel.ExerciseSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Suggestions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(suggestionsByMuscle.keys.sorted()), id: \.self) { muscle in
                if let suggestions = suggestionsByMuscle[muscle], !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(muscle.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 8) {
                            ForEach(suggestions) { suggestion in
                                ExerciseSuggestionChip(suggestion: suggestion) {
                                    onAddSuggestion(suggestion)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
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
        usesMetricWeight: true,
        onAddSet: {},
        onRemoveSet: { _ in },
        onUpdateSet: { _, _, _, _ in },
        onToggleWarmup: { _ in }
    )
    .padding()
}
