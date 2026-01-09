//
//  ExerciseSuggestions.swift
//  Plates
//
//  Exercise suggestion components for live workout view
//

import SwiftUI

// MARK: - Up Next Suggestion Card

struct UpNextSuggestionCard: View {
    let suggestion: LiveWorkoutViewModel.ExerciseSuggestion
    let lastPerformance: ExerciseHistory?
    let usesMetricWeight: Bool
    let onAdd: () -> Void

    private var weightUnit: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.accent)
                Text("Up Next")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.accent)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.exerciseName)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(suggestion.muscleGroup.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let last = lastPerformance, last.bestSetWeightKg > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("Last: \(last.totalSets)×\(last.bestSetReps) @ \(Int(last.bestSetWeightKg))\(weightUnit)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.accent)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Exercise Suggestion Chip

struct ExerciseSuggestionChip: View {
    let suggestion: LiveWorkoutViewModel.ExerciseSuggestion
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Text(suggestion.exerciseName)
                    .font(.subheadline)
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestions By Muscle Section

struct SuggestionsByMuscleSection: View {
    let suggestionsByMuscle: [String: [LiveWorkoutViewModel.ExerciseSuggestion]]
    let lastPerformances: [String: ExerciseHistory]
    let onAddSuggestion: (LiveWorkoutViewModel.ExerciseSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Suggestions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(suggestionsByMuscle.keys.sorted()), id: \.self) { muscle in
                if let suggestions = suggestionsByMuscle[muscle], !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(muscle.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 8) {
                            ForEach(suggestions) { suggestion in
                                ExerciseSuggestionChip(suggestion: suggestion) {
                                    onAddSuggestion(suggestion)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}
