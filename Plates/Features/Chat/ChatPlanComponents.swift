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
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    private var hasCalorieChange: Bool {
        suggestion.calories != nil && suggestion.calories != currentCalories
    }

    private var hasProteinChange: Bool {
        enabledMacros.contains(.protein) &&
        suggestion.proteinGrams != nil && suggestion.proteinGrams != currentProtein
    }

    private var hasCarbsChange: Bool {
        enabledMacros.contains(.carbs) &&
        suggestion.carbsGrams != nil && suggestion.carbsGrams != currentCarbs
    }

    private var hasFatChange: Bool {
        enabledMacros.contains(.fat) &&
        suggestion.fatGrams != nil && suggestion.fatGrams != currentFat
    }

    private var hasAnyChanges: Bool {
        hasCalorieChange || hasProteinChange || hasCarbsChange || hasFatChange || suggestion.goal != nil
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
                    if hasCalorieChange, let newCalories = suggestion.calories, let current = currentCalories {
                        PlanChangeRow(
                            color: .orange,
                            label: "Calories",
                            current: current,
                            proposed: newCalories,
                            unit: "kcal"
                        )
                        if hasProteinChange || hasCarbsChange || hasFatChange || suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if hasProteinChange, let newProtein = suggestion.proteinGrams, let current = currentProtein {
                        PlanChangeRow(
                            color: MacroType.protein.color,
                            label: "Protein",
                            current: current,
                            proposed: newProtein,
                            unit: "g"
                        )
                        if hasCarbsChange || hasFatChange || suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if hasCarbsChange, let newCarbs = suggestion.carbsGrams, let current = currentCarbs {
                        PlanChangeRow(
                            color: MacroType.carbs.color,
                            label: "Carbs",
                            current: current,
                            proposed: newCarbs,
                            unit: "g"
                        )
                        if hasFatChange || suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if hasFatChange, let newFat = suggestion.fatGrams, let current = currentFat {
                        PlanChangeRow(
                            color: MacroType.fat.color,
                            label: "Fat",
                            current: current,
                            proposed: newFat,
                            unit: "g"
                        )
                        if suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if let goalName = suggestion.goalDisplayName {
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
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onSave: (PlanUpdateSuggestionEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    /// Macros that are tracked and relevant for plan (protein, carbs, fat only)
    private var planMacros: [MacroType] {
        [.protein, .carbs, .fat].filter { enabledMacros.contains($0) }
    }

    init(
        suggestion: PlanUpdateSuggestionEntry,
        currentCalories: Int,
        currentProtein: Int,
        currentCarbs: Int,
        currentFat: Int,
        enabledMacros: Set<MacroType> = MacroType.defaultEnabled,
        onSave: @escaping (PlanUpdateSuggestionEntry) -> Void
    ) {
        self.suggestion = suggestion
        self.currentCalories = currentCalories
        self.currentProtein = currentProtein
        self.currentCarbs = currentCarbs
        self.currentFat = currentFat
        self.enabledMacros = enabledMacros
        self.onSave = onSave
        _caloriesText = State(initialValue: String(suggestion.calories ?? currentCalories))
        _proteinText = State(initialValue: String(suggestion.proteinGrams ?? currentProtein))
        _carbsText = State(initialValue: String(suggestion.carbsGrams ?? currentCarbs))
        _fatText = State(initialValue: String(suggestion.fatGrams ?? currentFat))
    }

    private var isValid: Bool {
        Int(caloriesText) != nil && Int(caloriesText)! > 0
    }

    private func bindingFor(_ macro: MacroType) -> Binding<String> {
        switch macro {
        case .protein: $proteinText
        case .carbs: $carbsText
        case .fat: $fatText
        default: $proteinText // Won't be used for fiber/sugar
        }
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

                    ForEach(planMacros) { macro in
                        MacroEditRow(
                            label: macro.displayName,
                            value: bindingFor(macro),
                            unit: "g",
                            color: macro.color
                        )
                    }
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
