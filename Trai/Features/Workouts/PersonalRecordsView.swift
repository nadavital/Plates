//
//  PersonalRecordsView.swift
//  Trai
//
//  Personal Records (PR) management screen showing personal bests for exercises
//

import SwiftUI
import SwiftData

struct PersonalRecordsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExerciseHistory.performedAt, order: .reverse)
    private var allHistory: [ExerciseHistory]

    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]

    @State private var selectedMuscleGroup: Exercise.MuscleGroup?
    @State private var searchText = ""
    @State private var selectedExercise: ExercisePR?
    @State private var exerciseToDelete: ExercisePR?
    @State private var showingDeleteConfirmation = false

    /// Whether to use metric (kg) or imperial (lbs) for weight display
    private var useLbs: Bool {
        !(profiles.first?.usesMetricExerciseWeight ?? true)
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    /// Convert kg to display weight (lbs or kg) with proper rounding
    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: !useLbs)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    // MARK: - Computed Properties

    /// Group history by exercise and compute PRs
    private var exercisePRs: [ExercisePR] {
        let grouped = Dictionary(grouping: allHistory) { $0.exerciseName }

        return grouped.compactMap { (name, history) -> ExercisePR? in
            guard !history.isEmpty else { return nil }

            let exercise = exercises.first { $0.name == name }
            let muscleGroup = exercise?.targetMuscleGroup

            return ExercisePR.from(
                exerciseName: name,
                history: history,
                muscleGroup: muscleGroup
            )
        }
        .sorted { $0.exerciseName < $1.exerciseName }
    }

    /// Filtered PRs based on search and muscle group
    private var filteredPRs: [ExercisePR] {
        var result = exercisePRs

        if !searchText.isEmpty {
            result = result.filter { $0.exerciseName.localizedStandardContains(searchText) }
        }

        if let muscleGroup = selectedMuscleGroup {
            result = result.filter { $0.muscleGroup == muscleGroup }
        }

        return result
    }

    /// PRs grouped by muscle group
    private var prsByMuscleGroup: [Exercise.MuscleGroup: [ExercisePR]] {
        var grouped: [Exercise.MuscleGroup: [ExercisePR]] = [:]
        for pr in filteredPRs {
            if let muscleGroup = pr.muscleGroup {
                grouped[muscleGroup, default: []].append(pr)
            }
        }
        return grouped
    }

    /// Muscle groups that have PRs
    private var availableMuscleGroups: [Exercise.MuscleGroup] {
        Array(Set(exercisePRs.compactMap { $0.muscleGroup })).sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if exercisePRs.isEmpty {
                    emptyStateView
                } else {
                    prListView
                }
            }
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedExercise) { pr in
                PRDetailSheet(
                    pr: pr,
                    history: allHistory.filter { $0.exerciseName == pr.exerciseName },
                    useLbs: useLbs,
                    onDeleteAll: {
                        exerciseToDelete = pr
                        showingDeleteConfirmation = true
                    }
                )
            }
            .confirmationDialog(
                "Delete All Records",
                isPresented: $showingDeleteConfirmation,
                presenting: exerciseToDelete
            ) { pr in
                Button("Delete All \(pr.exerciseName) Records", role: .destructive) {
                    deleteAllRecords(for: pr.exerciseName)
                    selectedExercise = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: { pr in
                Text("This will permanently delete all \(pr.totalSessions) workout records for \(pr.exerciseName). This cannot be undone.")
            }
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Personal Records Yet",
            systemImage: "trophy",
            description: Text("Complete workouts to start tracking your personal records")
        )
    }

    private var prListView: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterSection

            List {
                // Summary stats
                Section {
                    HStack {
                        StatBox(
                            title: "Exercises",
                            value: "\(exercisePRs.count)",
                            icon: "dumbbell.fill"
                        )

                        StatBox(
                            title: "Total Sessions",
                            value: "\(exercisePRs.reduce(0) { $0 + $1.totalSessions })",
                            icon: "calendar"
                        )

                        StatBox(
                            title: "Muscle Groups",
                            value: "\(availableMuscleGroups.count)",
                            icon: "figure.strengthtraining.traditional"
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // PRs by muscle group
                if selectedMuscleGroup == nil {
                    ForEach(availableMuscleGroups) { muscleGroup in
                        if let prs = prsByMuscleGroup[muscleGroup], !prs.isEmpty {
                            Section {
                                ForEach(prs) { pr in
                                    ExercisePRRow(pr: pr, useLbs: useLbs) {
                                        selectedExercise = pr
                                    }
                                }
                            } header: {
                                Label(muscleGroup.displayName, systemImage: muscleGroup.iconName)
                            }
                        }
                    }

                    // Exercises without muscle group
                    let noMuscleGroup = filteredPRs.filter { $0.muscleGroup == nil }
                    if !noMuscleGroup.isEmpty {
                        Section {
                            ForEach(noMuscleGroup) { pr in
                                ExercisePRRow(pr: pr, useLbs: useLbs) {
                                    selectedExercise = pr
                                }
                            }
                        } header: {
                            Label("Other", systemImage: "figure.run")
                        }
                    }
                } else {
                    // Show filtered list without sections
                    Section {
                        ForEach(filteredPRs) { pr in
                            ExercisePRRow(pr: pr, useLbs: useLbs) {
                                selectedExercise = pr
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteAllRecords(for exerciseName: String) {
        let historyToDelete = allHistory.filter { $0.exerciseName == exerciseName }
        for history in historyToDelete {
            modelContext.delete(history)
        }
        try? modelContext.save()
        HapticManager.success()
    }

    private var filterSection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(availableMuscleGroups) { muscleGroup in
                    FilterChip(
                        label: muscleGroup.displayName,
                        icon: muscleGroup.iconName,
                        isSelected: selectedMuscleGroup == muscleGroup
                    ) {
                        if selectedMuscleGroup == muscleGroup {
                            selectedMuscleGroup = nil
                        } else {
                            selectedMuscleGroup = muscleGroup
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Data Models

struct ExercisePR: Identifiable {
    var id: String { exerciseName }

    let exerciseName: String
    let muscleGroup: Exercise.MuscleGroup?

    // Weight PR
    let maxWeightKg: Double
    let maxWeightDate: Date?
    let maxWeightReps: Int

    // Reps PR
    let maxReps: Int
    let maxRepsDate: Date?
    let maxRepsWeight: Double

    // Volume PR
    let maxVolume: Double
    let maxVolumeDate: Date?

    // Estimated 1RM
    let estimated1RM: Double?

    let totalSessions: Int
    let lastPerformed: Date

    /// Create an ExercisePR from exercise history entries
    static func from(exerciseName: String, history: [ExerciseHistory], muscleGroup: Exercise.MuscleGroup? = nil) -> ExercisePR? {
        guard let snapshot = ExercisePerformanceService.snapshot(exerciseName: exerciseName, history: history) else {
            return nil
        }
        return from(snapshot: snapshot, muscleGroup: muscleGroup)
    }

    static func from(snapshot: ExercisePerformanceSnapshot, muscleGroup: Exercise.MuscleGroup? = nil) -> ExercisePR {
        ExercisePR(
            exerciseName: snapshot.exerciseName,
            muscleGroup: muscleGroup,
            maxWeightKg: snapshot.weightPR?.bestSetWeightKg ?? 0,
            maxWeightDate: snapshot.weightPR?.performedAt,
            maxWeightReps: snapshot.weightPR?.bestSetReps ?? 0,
            maxReps: snapshot.repsPR?.bestSetReps ?? 0,
            maxRepsDate: snapshot.repsPR?.performedAt,
            maxRepsWeight: snapshot.repsPR?.bestSetWeightKg ?? 0,
            maxVolume: snapshot.volumePR?.totalVolume ?? 0,
            maxVolumeDate: snapshot.volumePR?.performedAt,
            estimated1RM: snapshot.estimatedOneRepMax,
            totalSessions: snapshot.totalSessions,
            lastPerformed: snapshot.lastSession?.performedAt ?? Date()
        )
    }
}

// MARK: - Supporting Views

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            Text(value)
                .font(.title2)
                .bold()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(minHeight: 100)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct ExercisePRRow: View {
    let pr: ExercisePR
    let useLbs: Bool
    let onTap: () -> Void

    private var weightUnit: String { useLbs ? "lbs" : "kg" }

    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: !useLbs)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pr.exerciseName)
                        .font(.headline)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Use Grid for consistent column alignment
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    GridRow {
                        // Max Weight
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Weight")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Max Reps
                        HStack(spacing: 4) {
                            Image(systemName: "number.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text("Reps")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Estimated 1RM (always show column)
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("Est. 1RM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("\(displayWeight(pr.maxWeightKg)) \(weightUnit) × \(pr.maxWeightReps)")
                            .font(.subheadline)
                            .bold()

                        Text("\(pr.maxReps) @ \(displayWeight(pr.maxRepsWeight)) \(weightUnit)")
                            .font(.subheadline)
                            .bold()

                        // Show value or "--" for consistency
                        if let oneRM = pr.estimated1RM {
                            Text("\(displayWeight(oneRM)) \(weightUnit)")
                                .font(.subheadline)
                                .bold()
                        } else {
                            Text("--")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Last performed
                HStack {
                    Text("\(pr.totalSessions) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("Last: \(pr.lastPerformed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - PR Detail Sheet

struct PRDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let pr: ExercisePR
    let history: [ExerciseHistory]
    let useLbs: Bool
    let onDeleteAll: () -> Void

    @State private var historyToEdit: ExerciseHistory?
    @State private var showingDeleteConfirmation = false
    @State private var historyToDelete: ExerciseHistory?

    var body: some View {
        NavigationStack {
            List {
                // Progress chart (only show if enough data)
                if history.count >= 2 {
                    Section {
                        ExerciseTrendsChart(history: history, useLbs: useLbs)
                    } header: {
                        Text("Progress")
                    }
                }

                // PR Stats - Compact 2x2 Grid
                Section {
                    PRStatsGrid(pr: pr, useLbs: useLbs)
                } header: {
                    Text("Personal Records")
                }

                // History with swipe-to-delete
                Section {
                    ForEach(history.prefix(20)) { entry in
                        HistoryRow(entry: entry, useLbs: useLbs)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") {
                                    historyToEdit = entry
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    historyToDelete = entry
                                    showingDeleteConfirmation = true
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    historyToDelete = entry
                                    showingDeleteConfirmation = true
                                }
                            }
                    }

                    if history.count > 20 {
                        Text("+ \(history.count - 20) more sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recent History")
                }

                // Delete all section
                Section {
                    Button("Delete All Records", role: .destructive) {
                        dismiss()
                        onDeleteAll()
                    }
                } footer: {
                    Text("This will permanently delete all \(history.count) workout records for this exercise.")
                }
            }
            .navigationTitle(pr.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $historyToEdit) { entry in
                EditHistorySheet(history: entry, useLbs: useLbs)
            }
            .confirmationDialog(
                "Delete Record",
                isPresented: $showingDeleteConfirmation,
                presenting: historyToDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    deleteHistory(entry)
                }
                Button("Cancel", role: .cancel) {}
            } message: { entry in
                Text("Delete record from \(entry.performedAt.formatted(date: .abbreviated, time: .omitted))?")
            }
        }
    }

    private func deleteHistory(_ history: ExerciseHistory) {
        modelContext.delete(history)
        try? modelContext.save()
        HapticManager.success()
    }
}

struct PRStatsGrid: View {
    let pr: ExercisePR
    let useLbs: Bool

    private var weightUnit: String { useLbs ? "lbs" : "kg" }

    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: !useLbs)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    private func formatVolume(_ volume: Double) -> String {
        let displayVolume = useLbs ? volume * 2.20462 : volume
        if displayVolume >= 1000 {
            return String(format: "%.1fk", displayVolume / 1000)
        }
        return "\(Int(displayVolume))"
    }

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                PRStatCell(
                    icon: "scalemass.fill",
                    iconColor: .orange,
                    label: "Max Weight",
                    value: "\(displayWeight(pr.maxWeightKg)) \(weightUnit)",
                    detail: "× \(pr.maxWeightReps)"
                )
                PRStatCell(
                    icon: "number.circle.fill",
                    iconColor: .blue,
                    label: "Max Reps",
                    value: "\(pr.maxReps)",
                    detail: "@ \(displayWeight(pr.maxRepsWeight))"
                )
            }
            GridRow {
                PRStatCell(
                    icon: "chart.bar.fill",
                    iconColor: .green,
                    label: "Volume",
                    value: formatVolume(pr.maxVolume),
                    detail: weightUnit
                )
                if let oneRM = pr.estimated1RM {
                    PRStatCell(
                        icon: "trophy.fill",
                        iconColor: .yellow,
                        label: "Est. 1RM",
                        value: "\(displayWeight(oneRM))",
                        detail: weightUnit
                    )
                } else {
                    PRStatCell(
                        icon: "trophy.fill",
                        iconColor: .secondary,
                        label: "Est. 1RM",
                        value: "--",
                        detail: ""
                    )
                }
            }
        }
    }
}

struct PRStatCell: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.subheadline)
                        .bold()
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryRow: View {
    let entry: ExerciseHistory
    let useLbs: Bool

    private var weightUnit: String { useLbs ? "lbs" : "kg" }

    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: !useLbs)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    var body: some View {
        HStack {
            Text(entry.performedAt, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text("\(displayWeight(entry.bestSetWeightKg)) \(weightUnit) × \(entry.bestSetReps)")
                .font(.subheadline)
                .bold()

            Spacer()

            Text("\(entry.totalSets)s • \(entry.totalReps)r")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edit History Sheet

private struct EditHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var history: ExerciseHistory
    let useLbs: Bool

    @State private var weightDisplay: Double  // Weight in display units (kg or lbs)
    @State private var reps: Int
    @State private var date: Date

    private var weightUnit: String { useLbs ? "lbs" : "kg" }

    /// Convert display weight to kg for storage
    private var weightKg: Double {
        useLbs ? weightDisplay / 2.20462 : weightDisplay
    }

    init(history: ExerciseHistory, useLbs: Bool) {
        self.history = history
        self.useLbs = useLbs
        // Convert stored kg to display units
        let displayValue = useLbs ? history.bestSetWeightKg * 2.20462 : history.bestSetWeightKg
        _weightDisplay = State(initialValue: displayValue)
        _reps = State(initialValue: history.bestSetReps)
        _date = State(initialValue: history.performedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField(weightUnit, value: $weightDisplay, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(weightUnit)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("reps", value: $reps, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Best Set")
                }

                Section {
                    HStack {
                        Text("Est. 1RM")
                        Spacer()
                        if reps > 0 && reps <= 12 {
                            let oneRM = weightKg * (36.0 / (37.0 - Double(reps)))
                            let displayOneRM = useLbs ? oneRM * 2.20462 : oneRM
                            Text(displayOneRM, format: .number.precision(.fractionLength(1)))
                            Text(weightUnit)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("--")
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack {
                        Text("Volume")
                        Spacer()
                        let volumeKg = weightKg * Double(reps)
                        let displayVolume = useLbs ? volumeKg * 2.20462 : volumeKg
                        Text(displayVolume, format: .number.precision(.fractionLength(0)))
                        Text(weightUnit)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calculated Values")
                } footer: {
                    Text("Estimated 1RM uses the Brzycki formula and is only calculated for 1-12 reps.")
                }
            }
            .navigationTitle("Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(weightDisplay <= 0 || reps <= 0)
                }
            }
        }
    }

    private func saveChanges() {
        // Round weight to nearest 0.5 kg
        history.bestSetWeightKg = (weightKg * 2).rounded() / 2
        history.bestSetWeightLbs = WeightUtility.round(
            history.bestSetWeightKg * WeightUtility.kgToLbs,
            unit: .lbs
        )
        history.bestSetReps = reps
        history.performedAt = date

        // Recalculate derived values
        // Volume = weight × reps × sets (use totalSets if available, otherwise estimate)
        let sets = max(history.totalSets, 1)
        history.totalVolume = history.bestSetWeightKg * Double(reps) * Double(sets)
        history.totalReps = reps * sets
        history.repPattern = Array(repeating: "\(reps)", count: sets).joined(separator: ",")
        let roundedWeightKg = WeightUtility.round(history.bestSetWeightKg, unit: .kg)
        history.weightPattern = Array(
            repeating: String(format: "%.1f", roundedWeightKg),
            count: sets
        ).joined(separator: ",")

        // Recalculate estimated 1RM
        if reps > 0 && reps <= 12 {
            history.estimatedOneRepMax = history.bestSetWeightKg * (36.0 / (37.0 - Double(reps)))
        } else {
            history.estimatedOneRepMax = nil
        }

        try? modelContext.save()
        HapticManager.success()
    }
}

// MARK: - Preview

#Preview {
    PersonalRecordsView()
        .modelContainer(for: [ExerciseHistory.self, Exercise.self], inMemory: true)
}
