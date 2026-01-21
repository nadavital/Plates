//
//  EditFoodEntrySheet.swift
//  Trai
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData

struct EditFoodEntrySheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var fiberText: String
    @State private var sugarText: String
    @State private var servingSize: String
    @State private var notes: String

    private var profile: UserProfile? { profiles.first }

    private var enabledMacros: Set<MacroType> {
        profile?.enabledMacros ?? MacroType.defaultEnabled
    }

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _caloriesText = State(initialValue: String(entry.calories))
        _proteinText = State(initialValue: String(format: "%.1f", entry.proteinGrams))
        _carbsText = State(initialValue: String(format: "%.1f", entry.carbsGrams))
        _fatText = State(initialValue: String(format: "%.1f", entry.fatGrams))
        _fiberText = State(initialValue: entry.fiberGrams.map { String(format: "%.1f", $0) } ?? "")
        _sugarText = State(initialValue: entry.sugarGrams.map { String(format: "%.1f", $0) } ?? "")
        _servingSize = State(initialValue: entry.servingSize ?? "")
        _notes = State(initialValue: entry.userDescription ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Image preview
                if let imageData = entry.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(.rect(cornerRadius: 12))
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Basic Info
                Section("Food Details") {
                    TextField("Name", text: $name)

                    TextField("Serving Size", text: $servingSize)
                        .textContentType(.none)
                }

                // Nutrition
                Section("Nutrition") {
                    MacroInputRow(
                        label: "Calories",
                        value: $caloriesText,
                        unit: "kcal",
                        color: .orange
                    )

                    ForEach(orderedEnabledMacros) { macro in
                        MacroInputRow(
                            label: macro.displayName,
                            value: bindingFor(macro),
                            unit: "g",
                            color: macro.color
                        )
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Add notes about this food...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Entry info
                Section {
                    HStack {
                        Text("Logged")
                        Spacer()
                        Text(entry.loggedAt, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Input Method")
                        Spacer()
                        Text(entry.input.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
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

    private func saveChanges() {
        entry.name = name
        entry.calories = Int(caloriesText) ?? entry.calories
        entry.proteinGrams = Double(proteinText) ?? entry.proteinGrams
        entry.carbsGrams = Double(carbsText) ?? entry.carbsGrams
        entry.fatGrams = Double(fatText) ?? entry.fatGrams
        entry.fiberGrams = Double(fiberText).flatMap { $0 > 0 ? $0 : nil }
        entry.sugarGrams = Double(sugarText).flatMap { $0 > 0 ? $0 : nil }
        entry.servingSize = servingSize.isEmpty ? nil : servingSize
        entry.userDescription = notes.isEmpty ? nil : notes

        HapticManager.success()
        dismiss()
    }
}

// MARK: - Macro Input Row

private struct MacroInputRow: View {
    let label: String
    @Binding var value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)

            Spacer()

            TextField("0", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
        }
    }
}

#Preview {
    EditFoodEntrySheet(
        entry: FoodEntry(
            name: "Grilled Chicken Salad",
            mealType: "lunch",
            calories: 450,
            proteinGrams: 40,
            carbsGrams: 15,
            fatGrams: 22
        )
    )
}
