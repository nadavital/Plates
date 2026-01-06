//
//  ManualFoodEntrySheet.swift
//  Plates
//
//  Manual food entry form for logging meals without camera
//

import SwiftUI
import SwiftData

struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let sessionId: UUID?
    let onSave: (FoodEntry) -> Void

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var servingSize = ""

    private var isValid: Bool {
        !name.isEmpty && Int(caloriesText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food name", text: $name)
                } header: {
                    Text("Name")
                }

                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calories")
                }

                Section {
                    MacroInputRow(label: "Protein", text: $proteinText)
                    MacroInputRow(label: "Carbs", text: $carbsText)
                    MacroInputRow(label: "Fat", text: $fatText)
                    MacroInputRow(label: "Fiber", text: $fiberText)
                } header: {
                    Text("Macros")
                }

                Section {
                    TextField("e.g., 1 cup, 100g", text: $servingSize)
                } header: {
                    Text("Serving Size (optional)")
                }
            }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveEntry() {
        let entry = FoodEntry()
        entry.name = name
        entry.calories = Int(caloriesText) ?? 0
        entry.proteinGrams = Double(proteinText) ?? 0
        entry.carbsGrams = Double(carbsText) ?? 0
        entry.fatGrams = Double(fatText) ?? 0
        entry.fiberGrams = Double(fiberText).flatMap { $0 > 0 ? $0 : nil }
        entry.servingSize = servingSize.isEmpty ? nil : servingSize
        entry.inputMethod = "manual"

        // Assign session if adding to existing session
        if let sessionId {
            entry.sessionId = sessionId
            // Get next order number in session
            let existingCount = try? modelContext.fetchCount(
                FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
            )
            entry.sessionOrder = existingCount ?? 0
        }

        onSave(entry)
        dismiss()
    }
}

// MARK: - Macro Input Row

private struct MacroInputRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("g")
                .foregroundStyle(.secondary)
        }
    }
}
