//
//  ExerciseListView.swift
//  Plates
//
//  Exercise selection with search, filters, and recent exercises
//

import SwiftUI
import SwiftData

struct ExerciseListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse)
    private var exerciseHistory: [ExerciseHistory]

    // Selection callback
    private let onSelect: ((Exercise) -> Void)?
    @Binding private var selectedExercise: Exercise?

    // Target muscle groups from current workout (for prioritized sorting)
    private let targetMuscleGroups: [Exercise.MuscleGroup]

    // Search and filter state
    @State private var searchText = ""
    @State private var selectedCategory: Exercise.Category?
    @State private var selectedMuscleGroup: Exercise.MuscleGroup?
    @State private var showingAddCustom = false
    @State private var customExerciseName = ""

    // Photo identification state
    @State private var showingCamera = false
    @State private var showingEquipmentResult = false
    @State private var equipmentAnalysis: ExercisePhotoAnalysis?
    @State private var isAnalyzingPhoto = false

    // MARK: - Initializers

    /// Closure-based initializer for adding exercises to workouts
    init(
        targetMuscleGroups: [Exercise.MuscleGroup] = [],
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.targetMuscleGroups = targetMuscleGroups
        self.onSelect = onSelect
        self._selectedExercise = .constant(nil)
    }

    /// Binding-based initializer for form selection
    init(selectedExercise: Binding<Exercise?>) {
        self.targetMuscleGroups = []
        self.onSelect = nil
        self._selectedExercise = selectedExercise
    }

    // MARK: - Computed Properties

    private var recentExerciseNames: [String] {
        // Get unique exercise names from recent history
        var seen = Set<String>()
        return exerciseHistory
            .compactMap { history -> String? in
                guard !seen.contains(history.exerciseName) else { return nil }
                seen.insert(history.exerciseName)
                return history.exerciseName
            }
            .prefix(5)
            .map { $0 }
    }

    private var recentExercises: [Exercise] {
        recentExerciseNames.compactMap { name in
            exercises.first { $0.name == name }
        }
    }

    private var filteredExercises: [Exercise] {
        var result = exercises

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(searchText) }
        }

        // Apply category filter
        if let category = selectedCategory {
            result = result.filter { $0.exerciseCategory == category }
        }

        // Apply muscle group filter
        if let muscleGroup = selectedMuscleGroup {
            result = result.filter { $0.targetMuscleGroup == muscleGroup }
        }

        return result
    }

    private var exercisesByCategory: [Exercise.Category: [Exercise]] {
        Dictionary(grouping: filteredExercises) { $0.exerciseCategory }
    }

    private var exercisesByMuscleGroup: [Exercise.MuscleGroup: [Exercise]] {
        var grouped: [Exercise.MuscleGroup: [Exercise]] = [:]
        for exercise in filteredExercises {
            if let muscleGroup = exercise.targetMuscleGroup {
                grouped[muscleGroup, default: []].append(exercise)
            }
        }
        return grouped
    }

    private var sortedMuscleGroups: [Exercise.MuscleGroup] {
        let allGroups = Array(exercisesByMuscleGroup.keys)

        // Sort with target muscle groups first, then alphabetically
        return allGroups.sorted { a, b in
            let aIsTarget = targetMuscleGroups.contains(a)
            let bIsTarget = targetMuscleGroups.contains(b)

            if aIsTarget && !bIsTarget {
                return true // a comes first
            } else if !aIsTarget && bIsTarget {
                return false // b comes first
            } else {
                return a.displayName < b.displayName // alphabetical
            }
        }
    }

    /// Whether to search for custom exercises (when search yields no results)
    private var showCustomOption: Bool {
        !searchText.isEmpty && filteredExercises.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                filterSection

                List {
                    // Load defaults if empty
                    if exercises.isEmpty {
                        Section {
                            Button("Load Default Exercises") {
                                loadDefaultExercises()
                            }
                        }
                    } else {
                        // Create custom exercise option (always available at top)
                        Section {
                            Button {
                                showingAddCustom = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.accent)
                                    Text("Create Custom Exercise")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.primary)

                            Button {
                                showingCamera = true
                            } label: {
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .foregroundStyle(.accent)
                                    Text("Identify Machine from Photo")
                                    Spacer()
                                    if isAnalyzingPhoto {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                            .disabled(isAnalyzingPhoto)
                        }

                        // Option to add searched exercise directly
                        if showCustomOption {
                            Section {
                                Button {
                                    addCustomExercise(name: searchText)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.accent)
                                        Text("Add \"\(searchText)\"")
                                        Spacer()
                                    }
                                }
                                .foregroundStyle(.primary)
                            } header: {
                                Text("Not in list?")
                            }
                        }

                        // Recent exercises section
                        if searchText.isEmpty && selectedCategory == nil && selectedMuscleGroup == nil && !recentExercises.isEmpty {
                            Section {
                                ForEach(recentExercises) { exercise in
                                    exerciseRow(exercise)
                                }
                            } header: {
                                Label("Recently Used", systemImage: "clock.arrow.circlepath")
                            }
                        }

                        // Exercises by muscle group (primary grouping)
                        ForEach(sortedMuscleGroups) { muscleGroup in
                            if let muscleExercises = exercisesByMuscleGroup[muscleGroup], !muscleExercises.isEmpty {
                                Section {
                                    ForEach(muscleExercises) { exercise in
                                        exerciseRow(exercise)
                                    }
                                } header: {
                                    Label(muscleGroup.displayName, systemImage: muscleGroup.iconName)
                                }
                            }
                        }

                        // Show exercises without muscle group (cardio, etc.)
                        let noMuscleGroupExercises = filteredExercises.filter { $0.targetMuscleGroup == nil }
                        if !noMuscleGroupExercises.isEmpty {
                            Section {
                                ForEach(noMuscleGroupExercises) { exercise in
                                    exerciseRow(exercise)
                                }
                            } header: {
                                Label(selectedCategory?.displayName ?? "Other", systemImage: "figure.run")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomExerciseSheet(
                    initialName: searchText,
                    onSave: { name, muscleGroup, category in
                        addCustomExercise(name: name, muscleGroup: muscleGroup, category: category)
                    }
                )
            }
            .fullScreenCover(isPresented: $showingCamera) {
                EquipmentCameraView { imageData in
                    showingCamera = false
                    Task { await analyzeEquipmentPhoto(imageData) }
                }
            }
            .sheet(isPresented: $showingEquipmentResult) {
                if let analysis = equipmentAnalysis {
                    EquipmentAnalysisSheet(
                        analysis: analysis,
                        onSelectExercise: { exerciseName, muscleGroup in
                            addCustomExercise(
                                name: exerciseName,
                                muscleGroup: Exercise.MuscleGroup(rawValue: muscleGroup),
                                category: .strength
                            )
                        }
                    )
                }
            }
        }
    }

    // MARK: - Photo Analysis

    private func analyzeEquipmentPhoto(_ imageData: Data) async {
        isAnalyzingPhoto = true
        defer { isAnalyzingPhoto = false }

        let geminiService = GeminiService()
        do {
            let analysis = try await geminiService.analyzeExercisePhoto(imageData: imageData)
            equipmentAnalysis = analysis
            showingEquipmentResult = true
            HapticManager.success()
        } catch {
            // Handle error - could show alert
            HapticManager.error()
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Category filters
                FilterChip(
                    label: "All",
                    isSelected: selectedCategory == nil && selectedMuscleGroup == nil
                ) {
                    selectedCategory = nil
                    selectedMuscleGroup = nil
                }

                Divider()
                    .frame(height: 20)

                // Category filters
                ForEach(Exercise.Category.allCases) { category in
                    FilterChip(
                        label: category.displayName,
                        icon: category.iconName,
                        isSelected: selectedCategory == category
                    ) {
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                            selectedMuscleGroup = nil
                        }
                    }
                }

                // Muscle group filters (only show for strength)
                if selectedCategory == .strength || selectedCategory == nil {
                    Divider()
                        .frame(height: 20)

                    ForEach(Exercise.MuscleGroup.allCases) { muscleGroup in
                        FilterChip(
                            label: muscleGroup.displayName,
                            icon: muscleGroup.iconName,
                            isSelected: selectedMuscleGroup == muscleGroup
                        ) {
                            if selectedMuscleGroup == muscleGroup {
                                selectedMuscleGroup = nil
                            } else {
                                selectedMuscleGroup = muscleGroup
                                selectedCategory = .strength
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Exercise Row

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            selectExercise(exercise)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)

                    if let muscleGroup = exercise.targetMuscleGroup {
                        Text(muscleGroup.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selectedExercise?.id == exercise.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Actions

    private func selectExercise(_ exercise: Exercise) {
        if let onSelect {
            onSelect(exercise)
        } else {
            selectedExercise = exercise
        }
        dismiss()
    }

    private func loadDefaultExercises() {
        for (name, category, muscleGroup) in Exercise.defaultExercises {
            let exercise = Exercise(name: name, category: category, muscleGroup: muscleGroup)
            modelContext.insert(exercise)
        }
        try? modelContext.save()
    }

    private func addCustomExercise(
        name: String,
        muscleGroup: Exercise.MuscleGroup? = nil,
        category: Exercise.Category = .strength
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check if exercise already exists
        if let existing = exercises.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            selectExercise(existing)
            return
        }

        // Create new custom exercise
        let exercise = Exercise(
            name: trimmed,
            category: category,
            muscleGroup: muscleGroup
        )
        exercise.isCustom = true
        modelContext.insert(exercise)
        try? modelContext.save()

        selectExercise(exercise)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ExerciseListView { exercise in
        print("Selected: \(exercise.name)")
    }
    .modelContainer(for: [Exercise.self, ExerciseHistory.self], inMemory: true)
}
