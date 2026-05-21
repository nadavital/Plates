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
    let onSave: (String, Exercise.MuscleGroup?, Exercise.Category, [String]?, [String], [Exercise.TrackingField]) -> Void

    @State private var exerciseName: String = ""
    @State private var selectedCategory: Exercise.Category = .strength
    @State private var selectedTargets: Set<String> = []
    @State private var selectedTrackingFields: Set<Exercise.TrackingField> = Set(Exercise.defaultTrackingFields(for: .strength))

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

                    if !canAccessExerciseAI {
                        lockedExerciseAnalysisCard
                    } else {
                        aiAnalysisCard
                            .traiCard(cornerRadius: 16)
                    }

                    categorySelector
                        .traiCard(cornerRadius: 16)

                    targetSelector
                        .traiCard(cornerRadius: 16)

                    trackingFieldSelector
                        .traiCard(cornerRadius: 16)
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
                        onSave(
                            exerciseName,
                            primaryMuscleGroup,
                            selectedCategory,
                            secondaryMuscleGroups,
                            Array(selectedTargets).sorted(),
                            orderedSelectedTrackingFields
                        )
                        HapticManager.success()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                exerciseName = initialName
                resetDefaultsForSelectedCategory()
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
            if isAnalyzing {
                sectionHeader("Trai Analysis", icon: "circle.hexagongrid.circle")

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
                sectionHeader("Trai Analysis", icon: "circle.hexagongrid.circle")

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
                sectionHeader("Trai Analysis", icon: "circle.hexagongrid.circle")

                Button {
                    Task { await analyzeExercise() }
                } label: {
                    Label("Analyze with Trai", systemImage: "circle.hexagongrid.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true))
                .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var lockedExerciseAnalysisCard: some View {
        ProUpsellInlineCard(
            source: .exerciseAnalysis,
            actionTitle: "Unlock Trai Pro"
        ) {
            proUpsellCoordinator?.present(source: .exerciseAnalysis)
        }
    }

    // MARK: - Category Selector

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Category", icon: "square.grid.2x2")

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(Exercise.Category.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedCategory = category
                            resetDefaultsForSelectedCategory()
                            HapticManager.selectionChanged()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Target Selector

    private var targetSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What are you targeting?", icon: selectedCategory.iconName)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(visibleTargetOptions, id: \.self) { target in
                    TargetButton(
                        title: target,
                        isSelected: selectedTargets.contains(target)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if selectedTargets.contains(target) {
                                selectedTargets.remove(target)
                            } else {
                                selectedTargets.insert(target)
                            }
                            HapticManager.selectionChanged()
                        }
                    }
                }
            }
        }
    }

    private var trackingFieldSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Track", icon: "slider.horizontal.3")

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(Exercise.TrackingField.allCases) { field in
                    TargetButton(
                        title: field.displayName,
                        icon: field.iconName,
                        isSelected: selectedTrackingFields.contains(field)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if selectedTrackingFields.contains(field) {
                                selectedTrackingFields.remove(field)
                            } else {
                                selectedTrackingFields.insert(field)
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
                    resetDefaultsForSelectedCategory()
                }

                if let targetTags = analysis.targetTags, !targetTags.isEmpty {
                    selectedTargets = Set(targetTags.map(Self.displayTargetTag))
                }

                if let fields = analysis.trackingFields?
                    .compactMap(Exercise.TrackingField.init(rawValue:)),
                   !fields.isEmpty {
                    selectedTrackingFields = Set(fields)
                }

                if let muscleGroupStr = analysis.muscleGroup,
                   let muscleGroup = Exercise.MuscleGroup(rawValue: muscleGroupStr) {
                    selectedTargets.insert(muscleGroup.displayName)
                }
            }
        } catch {
            print("Exercise analysis failed: \(error)")
        }
    }

    private var primaryMuscleGroup: Exercise.MuscleGroup? {
        selectedMuscleTargets.first
    }

    private var secondaryMuscleGroups: [String]? {
        let secondary = selectedMuscleTargets.dropFirst().map(\.rawValue)
        return secondary.isEmpty ? analysisResult?.secondaryMuscles : Array(secondary)
    }

    private var selectedMuscleTargets: [Exercise.MuscleGroup] {
        selectedTargets
            .compactMap { target in
                Exercise.MuscleGroup.allCases.first { $0.displayName == target || $0.rawValue == target }
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private var orderedSelectedTrackingFields: [Exercise.TrackingField] {
        let selected = Exercise.TrackingField.allCases.filter { selectedTrackingFields.contains($0) }
        return selected.isEmpty ? Exercise.defaultTrackingFields(for: selectedCategory) : selected
    }

    private var visibleTargetOptions: [String] {
        let defaults = Exercise.targetOptions(for: selectedCategory)
        let extra = selectedTargets
            .filter { !defaults.contains($0) }
            .sorted()
        return defaults + extra
    }

    private func resetDefaultsForSelectedCategory() {
        let defaults = Exercise.defaultTargetTags(for: selectedCategory)
        selectedTargets = Set(defaults)
        selectedTrackingFields = Set(Exercise.defaultTrackingFields(for: selectedCategory))
    }

    private static func displayTargetTag(_ tag: String) -> String {
        tag
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
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

private struct TargetButton: View {
    let title: String
    var icon: String?
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
            if let icon {
                Image(systemName: icon)
                    .font(.traiLabel(13))
            }
            Text(title)
                .font(.traiLabel(11))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }
}
