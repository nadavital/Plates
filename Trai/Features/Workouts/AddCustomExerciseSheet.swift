//
//  AddCustomExerciseSheet.swift
//  Trai
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

    // AI Analysis state
    @State private var geminiService = GeminiService()
    @State private var isAnalyzing = false
    @State private var analysisResult: ExerciseAnalysis?
    @State private var hasAnalyzed = false

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Exercise name input
                    nameInputCard

                    // AI Analysis card
                    aiAnalysisCard

                    // Category selector
                    categorySelector

                    // Muscle group selector (strength only)
                    if selectedCategory == .strength {
                        muscleGroupSelector
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
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
                        HapticManager.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                exerciseName = initialName
                if !initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { await analyzeExercise() }
                } else {
                    isNameFocused = true
                }
            }
        }
    }

    // MARK: - Name Input Card

    private var nameInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise Name")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            TextField("e.g., Incline DB Press", text: $exerciseName)
                .textInputAutocapitalization(.words)
                .font(.title3)
                .fontWeight(.medium)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))
                .focused($isNameFocused)
                .onChange(of: exerciseName) { _, _ in
                    if hasAnalyzed {
                        hasAnalyzed = false
                        analysisResult = nil
                    }
                }
        }
    }

    // MARK: - AI Analysis Card

    private var aiAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Trai Analysis")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Analyzing exercise...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .clipShape(.rect(cornerRadius: 12))
            } else if let analysis = analysisResult {
                VStack(alignment: .leading, spacing: 10) {
                    Text(analysis.description)
                        .font(.subheadline)

                    if let tips = analysis.tips {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(tips)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let secondary = analysis.secondaryMuscles, !secondary.isEmpty {
                        HStack(spacing: 4) {
                            Text("Also works:")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(secondary.joined(separator: ", "))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .clipShape(.rect(cornerRadius: 12))
            } else {
                Button {
                    Task { await analyzeExercise() }
                } label: {
                    HStack {
                        Text("Analyze with AI")
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Category Selector

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(Exercise.Category.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedCategory = category
                            HapticManager.selectionChanged()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Muscle Group Selector

    private var muscleGroupSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Muscle")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(Exercise.MuscleGroup.allCases) { muscle in
                    MuscleButton(
                        muscle: muscle,
                        isSelected: selectedMuscleGroup == muscle
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if selectedMuscleGroup == muscle {
                                selectedMuscleGroup = nil
                            } else {
                                selectedMuscleGroup = muscle
                            }
                            HapticManager.selectionChanged()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Analysis

    private func analyzeExercise() async {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await geminiService.analyzeExercise(name: name)
            analysisResult = analysis
            hasAnalyzed = true

            // Apply AI suggestions with animation
            withAnimation(.snappy(duration: 0.2)) {
                if let category = Exercise.Category(rawValue: analysis.category) {
                    selectedCategory = category
                }

                if let muscleGroupStr = analysis.muscleGroup,
                   let muscleGroup = Exercise.MuscleGroup(rawValue: muscleGroupStr) {
                    selectedMuscleGroup = muscleGroup
                }
            }
        } catch {
            print("Exercise analysis failed: \(error)")
        }
    }
}

// MARK: - Category Button

private struct CategoryButton: View {
    let category: Exercise.Category
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .font(.title2)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .accent : .primary)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Muscle Button

private struct MuscleButton: View {
    let muscle: Exercise.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: muscle.iconName)
                    .font(.title3)
                Text(muscle.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .accent : .primary)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
