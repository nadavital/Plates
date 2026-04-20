//
//  FoodCameraReview.swift
//  Trai
//
//  Review captured food image/description with AI analysis
//

import SwiftUI

struct FoodCameraReviewView: View {
    let image: UIImage?
    let inputSource: FoodLogInputSource
    @Binding var description: String
    let isAnalyzing: Bool
    let analysisResult: FoodAnalysis?
    let refinedSuggestion: SuggestedFoodEntry?
    let errorMessage: String?
    let refinementErrorMessage: String?
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let isLoadingRefinement: Bool
    let onAnalyze: () -> Void
    let onSave: (SuggestedFoodEntry, Bool) -> Void
    let onRefine: (String) -> Void

    @State private var isRefining = false
    @State private var refinementText = ""
    @FocusState private var isRefinementFocused: Bool

    private var isTextOnly: Bool {
        image == nil
    }

    private var currentSuggestion: SuggestedFoodEntry? {
        if let refined = refinedSuggestion {
            return refined
        }
        guard let result = analysisResult else { return nil }
        return SuggestedFoodEntry(
            name: result.name,
            calories: result.calories,
            proteinGrams: result.proteinGrams,
            carbsGrams: result.carbsGrams,
            fatGrams: result.fatGrams,
            fiberGrams: result.fiberGrams,
            sugarGrams: result.sugarGrams,
            servingSize: result.servingSize,
            emoji: result.emoji,
            components: result.components?.map(SuggestedFoodComponent.init(component:)) ?? [],
            mealKind: result.mealKind,
            notes: result.notes,
            confidence: result.confidence,
            schemaVersion: 2
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Captured image or text-only indicator
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipShape(.rect(cornerRadius: 16))
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: headerSystemImage)
                            .font(.system(size: 50))
                            .foregroundStyle(.tint)

                        Text(headerTitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                }

                // Description input
                VStack(alignment: .leading, spacing: 8) {
                    Text(descriptionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Add details about your food...", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 12))
                        .disabled(isTextOnly && analysisResult != nil && inputSource != .memorySuggestion)
                }

                // Analysis section
                if let suggestion = currentSuggestion {
                    FoodCameraSuggestionCard(
                        suggestion: suggestion,
                        isRefining: isRefining,
                        enabledMacros: enabledMacros,
                        onSave: {
                            onSave(suggestion, refinedSuggestion != nil)
                        },
                        onStartRefine: {
                            withAnimation(.spring(response: 0.3)) {
                                isRefining = true
                            }
                            isRefinementFocused = true
                        }
                    )
                } else if let error = errorMessage {
                    FoodCameraErrorCard(message: error, onRetry: onAnalyze)
                }

                // Refinement chat interface
                if isRefining {
                    VStack(spacing: 12) {
                        FoodRefinementInput(
                            text: $refinementText,
                            isLoading: isLoadingRefinement,
                            isFocused: $isRefinementFocused,
                            onSend: sendRefinement,
                            onCancel: {
                                withAnimation(.spring(response: 0.3)) {
                                    isRefining = false
                                    refinementText = ""
                                }
                            }
                        )

                        if let refinementErrorMessage, !refinementErrorMessage.isEmpty {
                            Text(refinementErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Initial analyze button
                if currentSuggestion == nil && errorMessage == nil {
                    Button(action: onAnalyze) {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Analyzing...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Analyze with AI", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.traiPrimary())
                    .disabled(isAnalyzing)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .onChange(of: refinedSuggestion) { _, newValue in
            guard newValue != nil, isRefining else { return }

            withAnimation(.spring(response: 0.3)) {
                isRefining = false
            }
            refinementText = ""
            isRefinementFocused = false
        }
    }

    private var headerTitle: String {
        switch inputSource {
        case .memorySuggestion:
            return "Using remembered food"
        case .description:
            return "Analyzing from description"
        default:
            return "Review your food"
        }
    }

    private var headerSystemImage: String {
        switch inputSource {
        case .memorySuggestion:
            return "sparkles.rectangle.stack.fill"
        case .description:
            return "text.bubble.fill"
        default:
            return "fork.knife.circle.fill"
        }
    }

    private var descriptionLabel: String {
        switch inputSource {
        case .memorySuggestion:
            return "Notes (optional)"
        default:
            return isTextOnly ? "Description" : "Description (optional)"
        }
    }

    private func sendRefinement() {
        guard !refinementText.trimmingCharacters(in: .whitespaces).isEmpty,
              currentSuggestion != nil else { return }

        let correction = refinementText.trimmingCharacters(in: .whitespacesAndNewlines)
        refinementText = ""
        onRefine(correction)
    }
}

// MARK: - Food Camera Suggestion Card

struct FoodCameraSuggestionCard: View {
    let suggestion: SuggestedFoodEntry
    let isRefining: Bool
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onSave: () -> Void
    let onStartRefine: () -> Void

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    private func valueFor(_ macro: MacroType) -> Double {
        switch macro {
        case .protein: suggestion.proteinGrams
        case .carbs: suggestion.carbsGrams
        case .fat: suggestion.fatGrams
        case .fiber: suggestion.fiberGrams ?? 0
        case .sugar: suggestion.sugarGrams ?? 0
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text(suggestion.displayEmoji)
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()
            }

            // Meal name and calories
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.name)
                        .font(.headline)

                    if let servingSize = suggestion.servingSize {
                        Text(servingSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(suggestion.calories)")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Macros (filtered by enabledMacros)
            if !orderedEnabledMacros.isEmpty {
                HStack(spacing: 12) {
                    ForEach(orderedEnabledMacros) { macro in
                        FoodCameraMacroPill(
                            label: macro.displayName,
                            value: Int(valueFor(macro)),
                            color: macro.color
                        )
                    }
                }
            }

            // Action buttons
            if !isRefining {
                HStack(spacing: 10) {
                    Button(action: onStartRefine) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.subheadline)
                            Text("Refine")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiTertiary())
                    .accessibilityIdentifier("foodCameraReviewRefineButton")

                    Button(action: onSave) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiPrimary())
                    .accessibilityIdentifier("foodCameraReviewSaveButton")
                }
            }
            }
            .traiCard(tint: .green)
    }
}

// MARK: - Food Camera Macro Pill

struct FoodCameraMacroPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Food Refinement Input

struct FoodRefinementInput: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("What should I change?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .accessibilityIdentifier("foodCameraRefinementCancelButton")
            }

            HStack(spacing: 10) {
                TextField("e.g., \"It's actually a wrap\" or \"Add 100 more calories\"", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .focused(isFocused)
                    .accessibilityIdentifier("foodCameraRefinementField")

                Button {
                    onSend()
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                    }
                }
                .accessibilityIdentifier("foodCameraRefinementSendButton")
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .traiCard()
    }
}

// MARK: - Food Camera Error Card

struct FoodCameraErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.traiPrimary())
        }
        .frame(maxWidth: .infinity)
        .traiCard()
    }
}
