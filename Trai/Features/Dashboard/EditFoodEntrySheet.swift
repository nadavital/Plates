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
    @Environment(\.modelContext) private var modelContext
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
            ScrollView {
                VStack(spacing: 14) {
                    if let imageData = entry.imageData,
                       let uiImage = UIImage(data: imageData) {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Photo", icon: "camera.fill")
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .frame(maxWidth: .infinity)
                                .clipShape(.rect(cornerRadius: 12))
                        }
                        .traiCard(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Food Details", systemImage: "fork.knife")
                                .font(.traiHeadline())
                                .foregroundStyle(.primary)

                            Text("Name and quantity")
                                .font(.traiLabel(12))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.traiLabel(12))
                                .foregroundStyle(.secondary)

                            TextField("e.g. Grilled chicken salad", text: $name)
                                .padding(12)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quantity")
                                .font(.traiLabel(12))
                                .foregroundStyle(.secondary)

                            TextField("e.g. 1 bowl, 150 g, 2 slices", text: $servingSize)
                                .textContentType(.none)
                                .padding(12)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .traiCard(cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Nutrition", icon: "chart.pie.fill")

                        MacroInputRow(
                            label: "Calories",
                            value: $caloriesText,
                            unit: "kcal",
                            color: .accentColor
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
                    .traiCard(cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Notes", icon: "note.text")
                        TextField("Add notes about this food...", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .traiCard(cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Entry Info", icon: "info.circle")
                        infoRow("Logged", value: entry.loggedAt.formatted(.dateTime.month().day().hour().minute()))
                        infoRow("Input Method", value: entry.input.displayName)
                    }
                    .traiCard(cornerRadius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
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
                    .labelStyle(.iconOnly)
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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

        WidgetDataProvider.shared.updateWidgetData(modelContext: modelContext)
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
                .fill(color.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay {
                    Text(label.prefix(1))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }

            Text(label)

            Spacer()

            TextField("0", text: $value)
                .keyboardType(unit == "kcal" ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
        }
        .font(.subheadline)
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
