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
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?

    let initialName: String
    let onSave: (String, Exercise.MuscleGroup?, Exercise.Category, [String]?) -> Void

    @State private var exerciseName: String = ""
    @State private var selectedCategory: Exercise.Category = .strength
    @State private var selectedMuscleGroup: Exercise.MuscleGroup?

    // AI Analysis state
    @State private var aiService = AIService()
    @State private var isAnalyzing = false
    @State private var analysisResult: ExerciseAnalysis?
    @State private var hasAnalyzed = false
    @State private var presentedAccountSetupContext: AccountSetupContext?

    @FocusState private var isNameFocused: Bool

    private var canAccessExerciseAI: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private var requiresAuthenticatedAccountForExerciseAI: Bool {
        accountSessionService?.isAuthenticated != true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    nameInputCard
                        .traiCard(cornerRadius: 16)

                    aiAnalysisCard
                        .traiCard(cornerRadius: 16)

                    categorySelector
                        .traiCard(cornerRadius: 16)

                    if selectedCategory == .strength {
                        muscleGroupSelector
                            .traiCard(cornerRadius: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        onSave(exerciseName, selectedMuscleGroup, selectedCategory, analysisResult?.secondaryMuscles)
                        HapticManager.success()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                exerciseName = initialName
                if canAccessExerciseAI
                    && !requiresAuthenticatedAccountForExerciseAI
                    && !initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { await analyzeExercise() }
                } else {
                    isNameFocused = true
                }
            }
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
        .traiSheetBranding()
        .proUpsellPresenter()
    }

    // MARK: - Name Input Card

    private var nameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Exercise Name", icon: "figure.strengthtraining.traditional")

            TextField("e.g. Incline DB Press", text: $exerciseName)
                .textInputAutocapitalization(.words)
                .font(.traiHeadline(18))
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
            if !canAccessExerciseAI {
                ProUpsellInlineCard(
                    source: .exerciseAnalysis,
                    actionTitle: "Unlock Trai Pro"
                ) {
                    proUpsellCoordinator?.present(source: .exerciseAnalysis)
                }
            } else if isAnalyzing {
                sectionHeader("Trai Analysis", icon: "sparkles")

                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing exercise...")
                        .font(.traiHeadline(15))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(TraiColors.brandAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else if let analysis = analysisResult {
                sectionHeader("Trai Analysis", icon: "sparkles")

                VStack(alignment: .leading, spacing: 10) {
                    Text(analysis.description)
                        .font(.traiHeadline(15))

                    if let tips = analysis.tips {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.traiLabel(12))
                                .foregroundStyle(.yellow)
                            Text(tips)
                                .font(.traiLabel(12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let secondary = analysis.secondaryMuscles, !secondary.isEmpty {
                        Text("Also works: \(secondary.joined(separator: ", "))")
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(TraiColors.brandAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                sectionHeader("Trai Analysis", icon: "sparkles")

                Button {
                    Task { await analyzeExercise() }
                } label: {
                    Label("Analyze with AI", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true))
                .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Category Selector

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Category", icon: "square.grid.2x2")

            HStack(spacing: 8) {
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
            sectionHeader("Target Muscle", icon: "figure.strengthtraining.traditional")

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

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.traiHeadline())
            .foregroundStyle(.primary)
    }

    // MARK: - Analysis

    private func analyzeExercise() async {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !requiresAuthenticatedAccountForExerciseAI else {
            presentedAccountSetupContext = .aiFeatures
            return
        }
        guard canAccessExerciseAI else {
            proUpsellCoordinator?.present(source: .exerciseAnalysis)
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await aiService.analyzeExercise(name: name)
            analysisResult = analysis
            hasAnalyzed = true

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
        if isSelected {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiSecondary(color: .accentColor, fullWidth: true, fillOpacity: 0.18))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiTertiary(color: .secondary, fullWidth: true))
        }
    }

    private var label: some View {
        VStack(spacing: 6) {
            Image(systemName: category.iconName)
                .font(.traiHeadline(18))
            Text(category.displayName)
                .font(.traiLabel(12))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Muscle Button

private struct MuscleButton: View {
    let muscle: Exercise.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fullWidth: true, fillOpacity: 0.18))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiTertiary(color: .secondary, size: .compact, fullWidth: true))
        }
    }

    private var label: some View {
        VStack(spacing: 6) {
            Image(systemName: muscle.iconName)
                .font(.traiLabel(13))
            Text(muscle.displayName)
                .font(.traiLabel(11))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }
}
