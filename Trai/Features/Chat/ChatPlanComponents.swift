//
//  ChatPlanComponents.swift
//  Trai
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
    let currentFiber: Int?
    let currentSugar: Int?
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

    private var hasFiberChange: Bool {
        enabledMacros.contains(.fiber) &&
        suggestion.fiberGrams != nil && suggestion.fiberGrams != currentFiber
    }

    private var hasSugarChange: Bool {
        enabledMacros.contains(.sugar) &&
        suggestion.sugarGrams != nil && suggestion.sugarGrams != currentSugar
    }

    private var hiddenMacroChangeLabels: [String] {
        var labels: [String] = []

        if !enabledMacros.contains(.fiber),
           suggestion.fiberGrams != nil,
           suggestion.fiberGrams != currentFiber {
            labels.append("Fiber")
        }

        if !enabledMacros.contains(.sugar),
           suggestion.sugarGrams != nil,
           suggestion.sugarGrams != currentSugar {
            labels.append("Sugar")
        }

        return labels
    }

    private var hasAnyChanges: Bool {
        hasCalorieChange || hasProteinChange || hasCarbsChange || hasFatChange ||
        hasFiberChange || hasSugarChange || !hiddenMacroChangeLabels.isEmpty || suggestion.goal != nil
    }

    private var rationaleText: String? {
        guard let rationale = suggestion.rationale?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rationale.isEmpty else {
            return nil
        }
        return rationale
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)

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

            if let rationaleText {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)

                    Text(rationaleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))
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
                        if hasProteinChange || hasCarbsChange || hasFatChange || hasFiberChange || hasSugarChange || suggestion.goalDisplayName != nil {
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
                        if hasCarbsChange || hasFatChange || hasFiberChange || hasSugarChange || suggestion.goalDisplayName != nil {
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
                        if hasFatChange || hasFiberChange || hasSugarChange || suggestion.goalDisplayName != nil {
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
                        if hasFiberChange || hasSugarChange || suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if hasFiberChange, let newFiber = suggestion.fiberGrams, let current = currentFiber {
                        PlanChangeRow(
                            color: MacroType.fiber.color,
                            label: "Fiber",
                            current: current,
                            proposed: newFiber,
                            unit: "g"
                        )
                        if hasSugarChange || suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if hasSugarChange, let newSugar = suggestion.sugarGrams, let current = currentSugar {
                        PlanChangeRow(
                            color: MacroType.sugar.color,
                            label: "Sugar",
                            current: current,
                            proposed: newSugar,
                            unit: "g"
                        )
                        if suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if !hiddenMacroChangeLabels.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Background targets also updated: \(hiddenMacroChangeLabels.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.vertical, 10)
                        if suggestion.goalDisplayName != nil {
                            Divider().padding(.leading, 24)
                        }
                    }

                    if let goalName = suggestion.goalDisplayName {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)

                            Text("Goal")
                                .font(.subheadline)

                            Spacer()

                            Text(goalName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.accentColor)
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
                .buttonStyle(.traiTertiary(color: .secondary))

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
                .buttonStyle(.traiPrimary(color: .accentColor))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
    var plan: PlanUpdateSuggestionEntry?
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Plan updated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Update Detail Sheet

struct PlanUpdateDetailSheet: View {
    let plan: PlanUpdateSuggestionEntry

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let rationale = plan.rationale, !rationale.isEmpty {
                    Section {
                        Text(rationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Why this change")
                    }
                }

                Section {
                    if let calories = plan.calories {
                        AppliedChangeRow(label: "Calories", value: calories, unit: "kcal", color: .orange)
                    }
                    if let protein = plan.proteinGrams {
                        AppliedChangeRow(label: "Protein", value: protein, unit: "g", color: MacroType.protein.color)
                    }
                    if let carbs = plan.carbsGrams {
                        AppliedChangeRow(label: "Carbs", value: carbs, unit: "g", color: MacroType.carbs.color)
                    }
                    if let fat = plan.fatGrams {
                        AppliedChangeRow(label: "Fat", value: fat, unit: "g", color: MacroType.fat.color)
                    }
                    if let fiber = plan.fiberGrams {
                        AppliedChangeRow(label: "Fiber", value: fiber, unit: "g", color: MacroType.fiber.color)
                    }
                    if let sugar = plan.sugarGrams {
                        AppliedChangeRow(label: "Sugar", value: sugar, unit: "g", color: MacroType.sugar.color)
                    }
                    if let goalName = plan.goalDisplayName {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                            Text("Goal")
                            Spacer()
                            Text(goalName)
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.medium)
                        }
                    }
                } header: {
                    Text("New targets")
                }
            }
            .navigationTitle("Plan Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .traiSheetBranding()
    }
}

// MARK: - Applied Change Row

struct AppliedChangeRow: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.medium)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edit Plan Suggestion Sheet

struct EditPlanSuggestionSheet: View {
    let suggestion: PlanUpdateSuggestionEntry
    let currentCalories: Int
    let currentProtein: Int
    let currentCarbs: Int
    let currentFat: Int
    let currentFiber: Int
    let currentSugar: Int
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onSave: (PlanUpdateSuggestionEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var fiberText: String
    @State private var sugarText: String

    /// Macros that are tracked and relevant for plan display.
    private var planMacros: [MacroType] {
        [.protein, .carbs, .fat, .fiber, .sugar].filter { enabledMacros.contains($0) }
    }

    init(
        suggestion: PlanUpdateSuggestionEntry,
        currentCalories: Int,
        currentProtein: Int,
        currentCarbs: Int,
        currentFat: Int,
        currentFiber: Int,
        currentSugar: Int,
        enabledMacros: Set<MacroType> = MacroType.defaultEnabled,
        onSave: @escaping (PlanUpdateSuggestionEntry) -> Void
    ) {
        self.suggestion = suggestion
        self.currentCalories = currentCalories
        self.currentProtein = currentProtein
        self.currentCarbs = currentCarbs
        self.currentFat = currentFat
        self.currentFiber = currentFiber
        self.currentSugar = currentSugar
        self.enabledMacros = enabledMacros
        self.onSave = onSave
        _caloriesText = State(initialValue: String(suggestion.calories ?? currentCalories))
        _proteinText = State(initialValue: String(suggestion.proteinGrams ?? currentProtein))
        _carbsText = State(initialValue: String(suggestion.carbsGrams ?? currentCarbs))
        _fatText = State(initialValue: String(suggestion.fatGrams ?? currentFat))
        _fiberText = State(initialValue: String(suggestion.fiberGrams ?? currentFiber))
        _sugarText = State(initialValue: String(suggestion.sugarGrams ?? currentSugar))
    }

    private var isValid: Bool {
        Int(caloriesText) != nil && Int(caloriesText)! > 0
    }

    private func bindingFor(_ macro: MacroType) -> Binding<String> {
        switch macro {
        case .protein: $proteinText
        case .carbs: $carbsText
        case .fat: $fatText
        case .fiber: $fiberText
        case .sugar: $sugarText
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
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", systemImage: "checkmark") {
                        let updated = PlanUpdateSuggestionEntry(
                            calories: Int(caloriesText),
                            proteinGrams: Int(proteinText),
                            carbsGrams: Int(carbsText),
                            fatGrams: Int(fatText),
                            fiberGrams: Int(fiberText),
                            sugarGrams: Int(sugarText),
                            goal: suggestion.goal,
                            rationale: suggestion.rationale
                        )
                        onSave(updated)
                    }
                    .labelStyle(.iconOnly)
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
