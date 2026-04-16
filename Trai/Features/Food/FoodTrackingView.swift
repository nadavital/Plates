//
//  FoodTrackingView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct FoodTrackingView: View {
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    private var allFoodEntries: [FoodEntry]

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddFood = false
    @State private var selectedDate = Date()

    private var todaysEntries: [FoodEntry] {
        let calendar = Calendar.current
        return allFoodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: selectedDate) }
    }

    private var entriesByMeal: [FoodEntry.MealType: [FoodEntry]] {
        Dictionary(grouping: todaysEntries) { $0.meal }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Date", systemImage: "calendar")
                            .font(.headline)
                        DatePicker(
                            "Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                    .traiCard(cornerRadius: 16)

                    DailySummaryRow(entries: todaysEntries)
                        .traiCard(cornerRadius: 16)

                    ForEach(FoodEntry.MealType.allCases) { mealType in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(mealType.displayName, systemImage: mealType.iconName)
                                .font(.headline)

                            if let entries = entriesByMeal[mealType], !entries.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(entries) { entry in
                                        FoodEntryRow(entry: entry) {
                                            deleteEntry(entry)
                                        }
                                    }
                                }
                            } else {
                                Button {
                                    showingAddFood = true
                                } label: {
                                    Label("Add \(mealType.displayName)", systemImage: "plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.traiTertiary(fullWidth: true))
                            }
                        }
                        .traiCard(cornerRadius: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Food", systemImage: "plus") {
                        showingAddFood = true
                    }
                    .buttonStyle(.traiPrimary(size: .compact, width: 36, height: 36))
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showingAddFood) {
                AddFoodView()
                    .traiSheetBranding()
            }
        }
    }

    private func deleteEntry(_ entry: FoodEntry) {
        entry.imageData = nil
        modelContext.delete(entry)
    }
}

// MARK: - Daily Summary Row

struct DailySummaryRow: View {
    let entries: [FoodEntry]

    private var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        entries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        entries.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        entries.reduce(0) { $0 + $1.fatGrams }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Today's Total")
                    .font(.headline)
                Spacer()
                Text("\(totalCalories) kcal")
                    .font(.title3)
                    .bold()
            }

            HStack(spacing: 16) {
                MacroLabel(name: "Protein", value: totalProtein, color: MacroType.protein.color)
                MacroLabel(name: "Carbs", value: totalCarbs, color: MacroType.carbs.color)
                MacroLabel(name: "Fat", value: totalFat, color: MacroType.fat.color)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MacroLabel: View {
    let name: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(value))g")
                .font(.subheadline)
                .bold()
                .foregroundStyle(color)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Food Entry Row

struct FoodEntryRow: View {
    let entry: FoodEntry
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(entry.displayEmoji)
                            .font(.system(size: 24))
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.body)

                if let serving = entry.servingSize {
                    Text(serving)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.calories)")
                    .font(.headline)

                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    FoodTrackingView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
