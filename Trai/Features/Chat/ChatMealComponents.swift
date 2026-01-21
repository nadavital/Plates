//
//  ChatMealComponents.swift
//  Trai
//
//  Meal suggestion and logging UI components for chat
//

import SwiftUI
import SwiftData

// MARK: - Suggested Edit Card

struct SuggestedEditCard: View {
    let edit: SuggestedFoodEdit
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text(edit.displayEmoji)
                    Text("Update this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.orange)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.circle)
                }
            }

            Text(edit.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(edit.changes) { change in
                    HStack {
                        Text(change.field)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(change.oldValue)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(change.newValue)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                        .font(.subheadline)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Update")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Applied Edit Badge

struct AppliedEditBadge: View {
    let edit: SuggestedFoodEdit

    var body: some View {
        HStack(spacing: 6) {
            Text(edit.displayEmoji)
            Text("Updated \(edit.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Logged Meal Badge

struct LoggedMealBadge: View {
    let meal: SuggestedFoodEntry?
    let foodEntryId: UUID?
    let onTap: () -> Void

    private var displayText: String {
        if let name = meal?.name {
            return "Logged \(name)"
        }
        return "Meal logged"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(meal?.displayEmoji ?? "✓")
                Text(displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggested Meal Card

struct SuggestedMealCard: View {
    let meal: SuggestedFoodEntry
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    private func valueFor(_ macro: MacroType) -> Double {
        switch macro {
        case .protein: meal.proteinGrams
        case .carbs: meal.carbsGrams
        case .fat: meal.fatGrams
        case .fiber: meal.fiberGrams ?? 0
        case .sugar: meal.sugarGrams ?? 0
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text(meal.displayEmoji)
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.circle)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.headline)

                    if let servingSize = meal.servingSize {
                        Text(servingSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(meal.calories)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !orderedEnabledMacros.isEmpty {
                HStack(spacing: 12) {
                    ForEach(orderedEnabledMacros) { macro in
                        MealMacroPill(
                            label: macro.displayName,
                            value: Int(valueFor(macro)),
                            color: macro.color
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onEdit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                        Text("Edit")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                        Text("Log")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Meal Macro Pill

struct MealMacroPill: View {
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

// MARK: - Edit Meal Suggestion Sheet

struct EditMealSuggestionSheet: View {
    let meal: SuggestedFoodEntry
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    let onSave: (SuggestedFoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var fiberText: String
    @State private var sugarText: String
    @State private var servingSize: String

    init(
        meal: SuggestedFoodEntry,
        enabledMacros: Set<MacroType> = MacroType.defaultEnabled,
        onSave: @escaping (SuggestedFoodEntry) -> Void
    ) {
        self.meal = meal
        self.enabledMacros = enabledMacros
        self.onSave = onSave
        _name = State(initialValue: meal.name)
        _caloriesText = State(initialValue: String(meal.calories))
        _proteinText = State(initialValue: String(format: "%.0f", meal.proteinGrams))
        _carbsText = State(initialValue: String(format: "%.0f", meal.carbsGrams))
        _fatText = State(initialValue: String(format: "%.0f", meal.fatGrams))
        _fiberText = State(initialValue: meal.fiberGrams.map { String(format: "%.0f", $0) } ?? "")
        _sugarText = State(initialValue: meal.sugarGrams.map { String(format: "%.0f", $0) } ?? "")
        _servingSize = State(initialValue: meal.servingSize ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(caloriesText) != nil
    }

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food Details") {
                    TextField("Name", text: $name)
                    TextField("Serving Size (optional)", text: $servingSize)
                }

                Section("Nutrition") {
                    NutritionInputRow(label: "Calories", text: $caloriesText, unit: "kcal")

                    ForEach(orderedEnabledMacros) { macro in
                        NutritionInputRow(
                            label: macro.displayName,
                            text: bindingFor(macro),
                            unit: "g"
                        )
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", systemImage: "checkmark") {
                        let updated = SuggestedFoodEntry(
                            name: name.trimmingCharacters(in: .whitespaces),
                            calories: Int(caloriesText) ?? meal.calories,
                            proteinGrams: Double(proteinText) ?? meal.proteinGrams,
                            carbsGrams: Double(carbsText) ?? meal.carbsGrams,
                            fatGrams: Double(fatText) ?? meal.fatGrams,
                            fiberGrams: fiberText.isEmpty ? nil : Double(fiberText),
                            sugarGrams: sugarText.isEmpty ? nil : Double(sugarText),
                            servingSize: servingSize.isEmpty ? nil : servingSize
                        )
                        onSave(updated)
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
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
}

// MARK: - Nutrition Input Row

private struct NutritionInputRow: View {
    let label: String
    @Binding var text: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(unit == "kcal" ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
