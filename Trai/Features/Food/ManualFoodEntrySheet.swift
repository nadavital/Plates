//
//  ManualFoodEntrySheet.swift
//  Trai
//
//  Manual food entry form for logging meals without camera
//

import SwiftUI
import SwiftData

struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @Query private var profiles: [UserProfile]

    let sessionId: UUID?
    let onSave: (FoodEntry) -> Void

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var sugarText = ""
    @State private var servingSize = ""

    private var profile: UserProfile? { profiles.first }

    private var enabledMacros: Set<MacroType> {
        profile?.enabledMacros ?? MacroType.defaultEnabled
    }

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    private var isValid: Bool {
        !name.isEmpty && Int(caloriesText) != nil
    }

    private var shouldShowUpgradeRow: Bool {
        !(monetizationService?.canAccessAIFeatures ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if shouldShowUpgradeRow {
                        upgradeRow
                            .traiCard(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Name", icon: "fork.knife")
                        TextField("Food name", text: $name)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .traiCard(cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Calories", icon: "flame.fill")
                        MacroInputRow(label: "Calories", text: $caloriesText, unit: "kcal", color: .orange)
                    }
                    .traiCard(cornerRadius: 16)

                    if !orderedEnabledMacros.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Macros", icon: "chart.pie.fill")
                            ForEach(orderedEnabledMacros) { macro in
                                MacroInputRow(
                                    label: macro.displayName,
                                    text: bindingFor(macro),
                                    unit: "g",
                                    color: macro.color
                                )
                            }
                        }
                        .traiCard(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Serving Size", icon: "scalemass")
                        TextField("e.g., 1 cup, 100g", text: $servingSize)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .traiCard(cornerRadius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("Manual Entry")
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
                        saveEntry()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!isValid)
                }
            }
        }
        .proUpsellPresenter()
        .traiSheetBranding()
    }

    private var upgradeRow: some View {
        ProUpsellInlineCard(source: .foodAnalysis) {
            proUpsellCoordinator?.present(source: .foodAnalysis)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
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

    private func saveEntry() {
        let entry = FoodEntry()
        entry.name = name
        entry.calories = Int(caloriesText) ?? 0
        entry.proteinGrams = Double(proteinText) ?? 0
        entry.carbsGrams = Double(carbsText) ?? 0
        entry.fatGrams = Double(fatText) ?? 0
        entry.fiberGrams = Double(fiberText).flatMap { $0 > 0 ? $0 : nil }
        entry.sugarGrams = Double(sugarText).flatMap { $0 > 0 ? $0 : nil }
        entry.servingSize = servingSize.isEmpty ? nil : servingSize
        entry.inputMethod = "manual"
        entry.emoji = FoodEmojiResolver.resolve(preferred: nil, foodName: name)
        entry.ensureDisplayMetadata()

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
    }
}

// MARK: - Macro Input Row

private struct MacroInputRow: View {
    let label: String
    @Binding var text: String
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
            TextField("0", text: $text)
                .keyboardType(unit == "kcal" ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .font(.subheadline)
    }
}
