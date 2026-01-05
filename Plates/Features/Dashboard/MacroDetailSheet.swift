//
//  MacroDetailSheet.swift
//  Plates
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData

struct MacroDetailSheet: View {
    let entries: [FoodEntry]
    let proteinGoal: Int
    let carbsGoal: Int
    let fatGoal: Int
    var fiberGoal: Int = 30
    var onAddFood: (() -> Void)?
    let onEditEntry: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    private var totalProtein: Double {
        entries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        entries.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        entries.reduce(0) { $0 + $1.fatGrams }
    }

    private var totalFiber: Double {
        entries.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
    }

    private var totalCaloriesFromMacros: Int {
        Int((totalProtein * 4) + (totalCarbs * 4) + (totalFat * 9))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Visual macro breakdown
                    MacroRingsDisplay(
                        protein: totalProtein,
                        carbs: totalCarbs,
                        fat: totalFat,
                        fiber: totalFiber,
                        proteinGoal: proteinGoal,
                        carbsGoal: carbsGoal,
                        fatGoal: fatGoal,
                        fiberGoal: fiberGoal
                    )
                    .padding(.top)

                    // Calorie contribution
                    CalorieContributionCard(
                        protein: totalProtein,
                        carbs: totalCarbs,
                        fat: totalFat
                    )

                    // Detailed breakdown by food
                    MacrosByFoodSection(entries: entries, onEditEntry: onEditEntry)
                }
                .padding()
            }
            .navigationTitle("Macro Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }

                if let addAction = onAddFood {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Food", systemImage: "plus", action: addAction)
                    }
                }
            }
        }
    }
}

// MARK: - Macro Rings Display

private struct MacroRingsDisplay: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let proteinGoal: Int
    let carbsGoal: Int
    let fatGoal: Int
    let fiberGoal: Int

    var body: some View {
        HStack(spacing: 20) {
            MacroRing(
                name: "Protein",
                current: protein,
                goal: Double(proteinGoal),
                color: .blue,
                unit: "g"
            )

            MacroRing(
                name: "Carbs",
                current: carbs,
                goal: Double(carbsGoal),
                color: .orange,
                unit: "g"
            )

            MacroRing(
                name: "Fat",
                current: fat,
                goal: Double(fatGoal),
                color: .purple,
                unit: "g"
            )

            MacroRing(
                name: "Fiber",
                current: fiber,
                goal: Double(fiberGoal),
                color: .green,
                unit: "g"
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct MacroRing: View {
    let name: String
    let current: Double
    let goal: Double
    let color: Color
    let unit: String

    private var progress: Double {
        min(current / goal, 1.0)
    }

    private var remaining: Double {
        max(goal - current, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.6), value: progress)

                VStack(spacing: 2) {
                    Text("\(Int(current))")
                        .font(.title2)
                        .bold()

                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(Int(remaining))\(unit) left")
                .font(.caption2)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Calorie Contribution Card

private struct CalorieContributionCard: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private var proteinCals: Double { protein * 4 }
    private var carbsCals: Double { carbs * 4 }
    private var fatCals: Double { fat * 9 }
    private var totalCals: Double { proteinCals + carbsCals + fatCals }

    private var proteinPct: Double { totalCals > 0 ? proteinCals / totalCals : 0 }
    private var carbsPct: Double { totalCals > 0 ? carbsCals / totalCals : 0 }
    private var fatPct: Double { totalCals > 0 ? fatCals / totalCals : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calorie Contribution")
                .font(.headline)

            // Bar visualization
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if proteinPct > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * proteinPct)
                    }
                    if carbsPct > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * carbsPct)
                    }
                    if fatPct > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: geometry.size.width * fatPct)
                    }
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 16) {
                MacroLegendItem(
                    name: "Protein",
                    calories: Int(proteinCals),
                    percentage: proteinPct * 100,
                    color: .blue
                )
                MacroLegendItem(
                    name: "Carbs",
                    calories: Int(carbsCals),
                    percentage: carbsPct * 100,
                    color: .orange
                )
                MacroLegendItem(
                    name: "Fat",
                    calories: Int(fatCals),
                    percentage: fatPct * 100,
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct MacroLegendItem: View {
    let name: String
    let calories: Int
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(calories) kcal")
                .font(.caption)
                .bold()

            Text("\(percentage, format: .number.precision(.fractionLength(0)))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Macros By Food Section

private struct MacrosByFoodSection: View {
    let entries: [FoodEntry]
    let onEditEntry: (FoodEntry) -> Void

    private var sortedByProtein: [FoodEntry] {
        entries.sorted { $0.proteinGrams > $1.proteinGrams }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macros by Food")
                .font(.headline)

            if entries.isEmpty {
                Text("No food logged today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedByProtein) { entry in
                        FoodMacroRow(entry: entry, onTap: { onEditEntry(entry) })
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct FoodMacroRow: View {
    let entry: FoodEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(entry.calories) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    MacroValue(value: entry.proteinGrams, unit: "P", color: .blue)
                    MacroValue(value: entry.carbsGrams, unit: "C", color: .orange)
                    MacroValue(value: entry.fatGrams, unit: "F", color: .purple)
                    MacroValue(value: entry.fiberGrams ?? 0, unit: "Fi", color: .green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct MacroValue: View {
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(value))")
                .font(.caption)
                .bold()
                .foregroundStyle(color)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 32)
    }
}

#Preview {
    MacroDetailSheet(
        entries: [
            FoodEntry(name: "Chicken Breast", mealType: "lunch", calories: 300, proteinGrams: 45, carbsGrams: 0, fatGrams: 8),
            FoodEntry(name: "Brown Rice", mealType: "lunch", calories: 220, proteinGrams: 5, carbsGrams: 45, fatGrams: 2),
            FoodEntry(name: "Avocado", mealType: "lunch", calories: 240, proteinGrams: 3, carbsGrams: 12, fatGrams: 22),
        ],
        proteinGoal: 150,
        carbsGoal: 200,
        fatGoal: 65,
        onAddFood: {},
        onEditEntry: { _ in }
    )
}
