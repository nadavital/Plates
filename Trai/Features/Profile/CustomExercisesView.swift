//
//  CustomExercisesView.swift
//  Trai
//
//  Manage custom exercises - view, edit, and delete
//

import SwiftUI
import SwiftData

struct CustomExercisesView: View {
    @Environment(\.modelContext) private var modelContext

    // Use @State + manual fetch instead of @Query to avoid navigation freeze
    @State private var customExercises: [Exercise] = []
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var exerciseToDelete: Exercise?
    @State private var showingAddCustomExercise = false

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return customExercises
        }
        return customExercises.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var exercisesByMuscle: [String: [Exercise]] {
        Dictionary(grouping: filteredExercises) { exercise in
            exercise.muscleGroup ?? "Other"
        }
    }

    var body: some View {
        List {
            if customExercises.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No Custom Exercises",
                        systemImage: "dumbbell",
                        description: Text("Custom exercises you create will appear here")
                    )

                    Button("Add Exercise", systemImage: "plus") {
                        showingAddCustomExercise = true
                    }
                    .buttonStyle(.traiSecondary(color: .orange, fullWidth: false))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if filteredExercises.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(exercisesByMuscle.keys.sorted(), id: \.self) { muscleGroup in
                    Section(muscleGroup.capitalized) {
                        ForEach(exercisesByMuscle[muscleGroup] ?? []) { exercise in
                            ExerciseManagementRow(exercise: exercise)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        exerciseToDelete = exercise
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Custom Exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") {
                    showingAddCustomExercise = true
                }
            }
        }
        .onAppear {
            fetchCustomExercises()
        }
        .sheet(isPresented: $showingAddCustomExercise) {
            AddCustomExerciseSheet(initialName: "") { name, muscleGroup, category, secondaryMuscles in
                addCustomExercise(
                    name: name,
                    muscleGroup: muscleGroup,
                    category: category,
                    secondaryMuscles: secondaryMuscles
                )
            }
            .traiSheetBranding()
        }
        .confirmationDialog(
            "Delete Exercise?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let exercise = exerciseToDelete {
                    deleteExercise(exercise)
                }
            }
            Button("Cancel", role: .cancel) {
                exerciseToDelete = nil
            }
        } message: {
            if let exercise = exerciseToDelete {
                Text("Are you sure you want to delete \"\(exercise.name)\"? This cannot be undone.")
            }
        }
    }

    private func fetchCustomExercises() {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true },
            sortBy: [SortDescriptor(\.name)]
        )
        customExercises = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteExercise(_ exercise: Exercise) {
        modelContext.delete(exercise)
        try? modelContext.save()
        exerciseToDelete = nil
        HapticManager.lightTap()
        // Refresh the list
        fetchCustomExercises()
    }

    private func addCustomExercise(
        name: String,
        muscleGroup: Exercise.MuscleGroup?,
        category: Exercise.Category,
        secondaryMuscles: [String]? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = existingExercise(named: trimmed) {
            if existing.exerciseCategory == .strength,
               existing.targetMuscleGroup == nil,
               category == .strength,
               let muscleGroup {
                existing.targetMuscleGroup = muscleGroup
            }
            if let secondaryMuscles, !secondaryMuscles.isEmpty, (existing.secondaryMuscles?.isEmpty ?? true) {
                existing.secondaryMuscles = secondaryMuscles.joined(separator: ",")
            }
            try? modelContext.save()
            fetchCustomExercises()
            HapticManager.success()
            return
        }

        let exercise = Exercise(
            name: trimmed,
            category: category,
            muscleGroup: category == .strength ? muscleGroup : nil
        )
        exercise.isCustom = true
        if let secondaryMuscles, !secondaryMuscles.isEmpty {
            exercise.secondaryMuscles = secondaryMuscles.joined(separator: ",")
        }
        modelContext.insert(exercise)
        try? modelContext.save()
        fetchCustomExercises()
        HapticManager.success()
    }

    private func existingExercise(named name: String) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        let allExercises = (try? modelContext.fetch(descriptor)) ?? []
        return allExercises.first { $0.name.lowercased() == name.lowercased() }
    }
}

// MARK: - Exercise Row

private struct ExerciseManagementRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: exercise.exerciseCategory.iconName)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(exercise.category.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let muscleGroup = exercise.muscleGroup {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(muscleGroup.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let equipment = exercise.equipmentName {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(equipment)
                            .font(.caption)
                            .foregroundStyle(.accent)
                    }
                }
            }

            Spacer()

            // Custom badge
            Text("Custom")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .clipShape(.capsule)
        }
        .padding(.vertical, 4)
    }
}
