//
//  FoodCameraReview.swift
//  Trai
//
//  Review captured food image/description with AI analysis
//

import SwiftUI

struct FoodCameraReviewView: View {
    let image: UIImage?
    @Binding var description: String
    let isAnalyzing: Bool
    let analysisResult: FoodAnalysis?
    let errorMessage: String?
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onAnalyze: () -> Void
    let onSave: () -> Void
    let onSaveRefined: (SuggestedFoodEntry) -> Void

    @State private var isRefining = false
    @State private var refinementText = ""
    @State private var refinedSuggestion: SuggestedFoodEntry?
    @State private var isLoadingRefinement = false
    @State private var geminiService = GeminiService()
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
            emoji: result.emoji
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
                    // Text-only mode header
                    VStack(spacing: 16) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.tint)

                        Text("Analyzing from description")
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
                    Text(isTextOnly ? "Description" : "Description (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Add details about your food...", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 12))
                        .disabled(isTextOnly && analysisResult != nil)
                }

                // Analysis section
                if let suggestion = currentSuggestion {
                    FoodCameraSuggestionCard(
                        suggestion: suggestion,
                        isRefining: isRefining,
                        enabledMacros: enabledMacros,
                        onSave: {
                            if refinedSuggestion != nil {
                                onSaveRefined(suggestion)
                            } else {
                                onSave()
                            }
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
                }

                // Initial analyze button
                if analysisResult == nil && errorMessage == nil {
                    Button(action: onAnalyze) {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Analyzing...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Label("Analyze with AI", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func sendRefinement() {
        guard !refinementText.trimmingCharacters(in: .whitespaces).isEmpty,
              let current = currentSuggestion else { return }

        isLoadingRefinement = true
        let correction = refinementText
        refinementText = ""

        Task {
            do {
                let imageData = image?.jpegData(compressionQuality: 0.8)
                let result = try await geminiService.refineFoodAnalysis(
                    correction: correction,
                    currentSuggestion: current,
                    imageData: imageData
                )

                withAnimation(.spring(response: 0.3)) {
                    refinedSuggestion = result
                    isRefining = false
                }
                HapticManager.success()
            } catch {
                HapticManager.error()
            }
            isLoadingRefinement = false
        }
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
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onSave) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.traiPrimary)
                }
            }
        }
        .traiCard(tint: .green)
        .overlay(
            RoundedRectangle(cornerRadius: TraiRadius.medium)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
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
            }

            HStack(spacing: 10) {
                TextField("e.g., \"It's actually a wrap\" or \"Add 100 more calories\"", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .focused(isFocused)

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
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .traiCard(glow: .food)
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
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .traiCard()
    }
}
