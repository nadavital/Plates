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
                ContentUnavailableView(
                    "No Custom Exercises",
                    systemImage: "dumbbell",
                    description: Text("Custom exercises you create will appear here")
                )
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
        .onAppear {
            fetchCustomExercises()
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
