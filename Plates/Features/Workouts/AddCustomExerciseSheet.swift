//
//  AddCustomExerciseSheet.swift
//  Plates
//
//  Sheet for adding custom exercises with AI analysis
//

import SwiftUI

// MARK: - Add Custom Exercise Sheet

struct AddCustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let onSave: (String, Exercise.MuscleGroup?, Exercise.Category) -> Void

    @State private var exerciseName: String = ""
    @State private var selectedCategory: Exercise.Category = .strength
    @State private var selectedMuscleGroup: Exercise.MuscleGroup?
    @State private var exerciseDescription: String = ""

    // AI Analysis state
    @State private var geminiService = GeminiService()
    @State private var isAnalyzing = false
    @State private var analysisResult: ExerciseAnalysis?
    @State private var hasAnalyzed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $exerciseName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: exerciseName) { _, _ in
                            // Reset analysis when name changes
                            if hasAnalyzed {
                                hasAnalyzed = false
                                analysisResult = nil
                            }
                        }
                } header: {
                    Text("Name")
                } footer: {
                    Text("e.g., Incline DB Press, Cable Rows, etc.")
                }

                // AI Analysis section
                Section {
                    if isAnalyzing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Trai is analyzing...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if let analysis = analysisResult {
                        // Show AI analysis result
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.accent)
                                Text("Trai's Analysis")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Text(analysis.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let tips = analysis.tips {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                    Text(tips)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let secondary = analysis.secondaryMuscles, !secondary.isEmpty {
                                Text("Also works: \(secondary.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            Task { await analyzeExercise() }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Ask Trai to Analyze")
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                        .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Label("AI Analysis", systemImage: "brain")
                }

                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(Exercise.Category.allCases) { category in
                            Label(category.displayName, systemImage: category.iconName)
                                .tag(category)
                        }
                    }
                } header: {
                    Text("Category")
                }

                if selectedCategory == .strength {
                    Section {
                        Picker("Muscle Group", selection: $selectedMuscleGroup) {
                            Text("None / Other").tag(nil as Exercise.MuscleGroup?)

                            ForEach(Exercise.MuscleGroup.allCases) { muscleGroup in
                                Label(muscleGroup.displayName, systemImage: muscleGroup.iconName)
                                    .tag(muscleGroup as Exercise.MuscleGroup?)
                            }
                        }
                    } header: {
                        Text("Target Muscle")
                    } footer: {
                        Text("Primary muscle group this exercise targets")
                    }
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(exerciseName, selectedMuscleGroup, selectedCategory)
                        dismiss()
                    }
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                exerciseName = initialName
                // Auto-analyze if we have an initial name
                if !initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { await analyzeExercise() }
                }
            }
        }
    }

    private func analyzeExercise() async {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await geminiService.analyzeExercise(name: name)
            analysisResult = analysis
            hasAnalyzed = true

            // Apply AI suggestions
            if let category = Exercise.Category(rawValue: analysis.category) {
                selectedCategory = category
            }

            if let muscleGroupStr = analysis.muscleGroup,
               let muscleGroup = Exercise.MuscleGroup(rawValue: muscleGroupStr) {
                selectedMuscleGroup = muscleGroup
            }

            exerciseDescription = analysis.description
        } catch {
            // Silently fail - user can still manually select
            print("Exercise analysis failed: \(error)")
        }
    }
}
