//
//  ChatPlanComponents.swift
//  Plates
//
//  Plan suggestion and update UI components for chat
//

import SwiftUI

// MARK: - Plan Update Suggestion Card

struct PlanUpdateSuggestionCard: View {
    let suggestion: PlanUpdateSuggestionEntry
    let currentCalories: Int?
    let currentProtein: Int?
    let currentCarbs: Int?
    let currentFat: Int?
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    private var hasAnyChanges: Bool {
        (suggestion.calories != nil && suggestion.calories != currentCalories) ||
        (suggestion.proteinGrams != nil && suggestion.proteinGrams != currentProtein) ||
        (suggestion.carbsGrams != nil && suggestion.carbsGrams != currentCarbs) ||
        (suggestion.fatGrams != nil && suggestion.fatGrams != currentFat) ||
        suggestion.goal != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.purple)

                    Text("Suggested Plan Update")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.quaternarySystemFill))
                        .clipShape(.circle)
                }
            }

            // Changes grid
            if hasAnyChanges {
                VStack(spacing: 0) {
                    if let newCalories = suggestion.calories, let current = currentCalories, newCalories != current {
                        PlanChangeRow(
                            color: .orange,
                            label: "Calories",
                            current: current,
                            proposed: newCalories,
                            unit: "kcal"
                        )
                        Divider().padding(.leading, 24)
                    }

                    if let newProtein = suggestion.proteinGrams, let current = currentProtein, newProtein != current {
                        PlanChangeRow(
                            color: .blue,
                            label: "Protein",
                            current: current,
                            proposed: newProtein,
                            unit: "g"
                        )
                        Divider().padding(.leading, 24)
                    }

                    if let newCarbs = suggestion.carbsGrams, let current = currentCarbs, newCarbs != current {
                        PlanChangeRow(
                            color: .green,
                            label: "Carbs",
                            current: current,
                            proposed: newCarbs,
                            unit: "g"
                        )
                        Divider().padding(.leading, 24)
                    }

                    if let newFat = suggestion.fatGrams, let current = currentFat, newFat != current {
                        PlanChangeRow(
                            color: .yellow,
                            label: "Fat",
                            current: current,
                            proposed: newFat,
                            unit: "g"
                        )
                    }

                    if let goalName = suggestion.goalDisplayName {
                        if suggestion.calories != nil || suggestion.proteinGrams != nil ||
                           suggestion.carbsGrams != nil || suggestion.fatGrams != nil {
                            Divider().padding(.leading, 24)
                        }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 10, height: 10)

                            Text("Goal")
                                .font(.subheadline)

                            Spacer()

                            Text(goalName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.purple)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onEdit()
                } label: {
                    Text("Edit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.subheadline)
                        Text("Apply Changes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Plan Change Row

struct PlanChangeRow: View {
    let color: Color
    let label: String
    let current: Int
    let proposed: Int
    let unit: String

    private var change: Int { proposed - current }

    private var changeColor: Color {
        change > 0 ? .green : .orange
    }

    private var changeText: String {
        change > 0 ? "+\(change)" : "\(change)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 6) {
                Text("\(current)")
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("\(proposed)")
                    .fontWeight(.semibold)

                Text(changeText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(changeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(changeColor.opacity(0.15))
                    .clipShape(.capsule)
            }
            .font(.subheadline)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Plan Update Applied Badge

struct PlanUpdateAppliedBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.purple)
            Text("Plan updated")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Edit Plan Suggestion Sheet

struct EditPlanSuggestionSheet: View {
    let suggestion: PlanUpdateSuggestionEntry
    let currentCalories: Int
    let currentProtein: Int
    let currentCarbs: Int
    let currentFat: Int
    let onSave: (PlanUpdateSuggestionEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    init(
        suggestion: PlanUpdateSuggestionEntry,
        currentCalories: Int,
        currentProtein: Int,
        currentCarbs: Int,
        currentFat: Int,
        onSave: @escaping (PlanUpdateSuggestionEntry) -> Void
    ) {
        self.suggestion = suggestion
        self.currentCalories = currentCalories
        self.currentProtein = currentProtein
        self.currentCarbs = currentCarbs
        self.currentFat = currentFat
        self.onSave = onSave
        _caloriesText = State(initialValue: String(suggestion.calories ?? currentCalories))
        _proteinText = State(initialValue: String(suggestion.proteinGrams ?? currentProtein))
        _carbsText = State(initialValue: String(suggestion.carbsGrams ?? currentCarbs))
        _fatText = State(initialValue: String(suggestion.fatGrams ?? currentFat))
    }

    private var isValid: Bool {
        Int(caloriesText) != nil && Int(caloriesText)! > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if let rationale = suggestion.rationale, !rationale.isEmpty {
                    Section {
                        Text(rationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("AI Recommendation")
                    }
                }

                Section {
                    MacroEditRow(label: "Calories", value: $caloriesText, unit: "kcal", color: .orange)
                    MacroEditRow(label: "Protein", value: $proteinText, unit: "g", color: .blue)
                    MacroEditRow(label: "Carbs", value: $carbsText, unit: "g", color: .green)
                    MacroEditRow(label: "Fat", value: $fatText, unit: "g", color: .yellow)
                } header: {
                    Text("New Targets")
                }
            }
            .navigationTitle("Edit Plan Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let updated = PlanUpdateSuggestionEntry(
                            calories: Int(caloriesText),
                            proteinGrams: Int(proteinText),
                            carbsGrams: Int(carbsText),
                            fatGrams: Int(fatText),
                            goal: suggestion.goal,
                            rationale: suggestion.rationale
                        )
                        onSave(updated)
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Macro Edit Row

struct MacroEditRow: View {
    let label: String
    @Binding var value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)

            Spacer()

            TextField("0", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)

            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
