//
//  MacroDetailSheet.swift
//  Trai
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData
import Charts

struct MacroDetailSheet: View {
    let entries: [FoodEntry]
    let proteinGoal: Int
    let carbsGoal: Int
    let fatGoal: Int
    var fiberGoal: Int = 30
    var sugarGoal: Int = 50
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    var historicalEntries: [FoodEntry] = []
    var onAddFood: (() -> Void)?
    let onEditEntry: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showTrends = false

    private var macroValues: [MacroType: Double] {
        [
            .protein: entries.reduce(0) { $0 + $1.proteinGrams },
            .carbs: entries.reduce(0) { $0 + $1.carbsGrams },
            .fat: entries.reduce(0) { $0 + $1.fatGrams },
            .fiber: entries.reduce(0) { $0 + ($1.fiberGrams ?? 0) },
            .sugar: entries.reduce(0) { $0 + ($1.sugarGrams ?? 0) }
        ]
    }

    private var macroGoals: [MacroType: Int] {
        [
            .protein: proteinGoal,
            .carbs: carbsGoal,
            .fat: fatGoal,
            .fiber: fiberGoal,
            .sugar: sugarGoal
        ]
    }

    private var orderedEnabledMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    private var trendData: [TrendsService.DailyNutrition] {
        TrendsService.aggregateNutritionByDay(entries: historicalEntries, days: 7)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if orderedEnabledMacros.isEmpty {
                        emptyMacrosView
                    } else {
                        // Visual macro breakdown
                        MacroRingsDisplay(
                            macroValues: macroValues,
                            macroGoals: macroGoals,
                            enabledMacros: enabledMacros
                        )
                        .padding(.top)

                        // Calorie contribution (only shows calorie-contributing macros)
                        let calorieContributingMacros = orderedEnabledMacros.filter { $0.contributesToCalories }
                        if !calorieContributingMacros.isEmpty {
                            CalorieContributionCard(
                                macroValues: macroValues,
                                enabledMacros: enabledMacros
                            )
                        }

                        // 7-Day Trends (collapsible)
                        if !historicalEntries.isEmpty {
                            MacroTrendsSection(
                                trendData: trendData,
                                macroGoals: macroGoals,
                                enabledMacros: enabledMacros,
                                isExpanded: $showTrends
                            )
                        }

                        // Detailed breakdown by food
                        MacrosByFoodSection(
                            entries: entries,
                            enabledMacros: enabledMacros,
                            onEditEntry: onEditEntry
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Macro Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }

                if let addAction = onAddFood {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Food", systemImage: "plus", action: addAction)
                    }
                }
            }
        }
    }

    private var emptyMacrosView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Macro tracking is disabled")
                .font(.headline)

            Text("Enable macros in Profile > Macro Tracking to see detailed breakdowns here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Macro Rings Display

private struct MacroRingsDisplay: View {
    let macroValues: [MacroType: Double]
    let macroGoals: [MacroType: Int]
    let enabledMacros: Set<MacroType>

    private var orderedMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(orderedMacros) { macro in
                MacroRing(
                    name: macro.displayName,
                    current: macroValues[macro] ?? 0,
                    goal: Double(macroGoals[macro] ?? 100),
                    color: macro.color,
                    unit: "g"
                )
            }
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
    let macroValues: [MacroType: Double]
    let enabledMacros: Set<MacroType>

    // Only include calorie-contributing macros (protein, carbs, fat, sugar - not fiber)
    private var calorieContributingMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) && $0.contributesToCalories }
    }

    private var caloriesByMacro: [MacroType: Double] {
        var result: [MacroType: Double] = [:]
        for macro in calorieContributingMacros {
            result[macro] = (macroValues[macro] ?? 0) * macro.caloriesPerGram
        }
        return result
    }

    private var totalCals: Double {
        // Only count protein, carbs, fat for total (sugar is part of carbs)
        let protein = (macroValues[.protein] ?? 0) * 4
        let carbs = (macroValues[.carbs] ?? 0) * 4
        let fat = (macroValues[.fat] ?? 0) * 9
        return protein + carbs + fat
    }

    private func percentageFor(_ macro: MacroType) -> Double {
        guard totalCals > 0 else { return 0 }
        return (caloriesByMacro[macro] ?? 0) / totalCals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calorie Contribution")
                .font(.headline)

            // Only show bar for main macros (protein, carbs, fat)
            let mainMacros: [MacroType] = [.protein, .carbs, .fat].filter { enabledMacros.contains($0) }

            // Bar visualization
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(mainMacros) { macro in
                        let pct = percentageFor(macro)
                        if pct > 0 {
                            Rectangle()
                                .fill(macro.color)
                                .frame(width: geometry.size.width * pct)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 16) {
                ForEach(mainMacros) { macro in
                    MacroLegendItem(
                        name: macro.displayName,
                        calories: Int(caloriesByMacro[macro] ?? 0),
                        percentage: percentageFor(macro) * 100,
                        color: macro.color
                    )
                }
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
    let enabledMacros: Set<MacroType>
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
                        FoodMacroRow(
                            entry: entry,
                            enabledMacros: enabledMacros,
                            onTap: { onEditEntry(entry) }
                        )
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
    let enabledMacros: Set<MacroType>
    let onTap: () -> Void

    private var orderedMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    private func valueFor(_ macro: MacroType) -> Double {
        switch macro {
        case .protein: entry.proteinGrams
        case .carbs: entry.carbsGrams
        case .fat: entry.fatGrams
        case .fiber: entry.fiberGrams ?? 0
        case .sugar: entry.sugarGrams ?? 0
        }
    }

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
                    ForEach(orderedMacros) { macro in
                        MacroValue(
                            value: valueFor(macro),
                            unit: macro.shortName,
                            color: macro.color
                        )
                    }
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

// MARK: - Macro Trends Section

private struct MacroTrendsSection: View {
    let trendData: [TrendsService.DailyNutrition]
    let macroGoals: [MacroType: Int]
    let enabledMacros: Set<MacroType>
    @Binding var isExpanded: Bool

    private var orderedMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("7-Day Trends", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Show a chart for each enabled macro
                ForEach(orderedMacros) { macro in
                    NutritionTrendChart(
                        data: trendData,
                        goal: macroGoals[macro] ?? 100,
                        metric: metricFor(macro),
                        title: "\(macro.displayName) Trend"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func metricFor(_ macro: MacroType) -> NutritionTrendChart.NutritionMetric {
        switch macro {
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .fiber: .fiber
        case .sugar: .sugar
        }
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
        enabledMacros: MacroType.defaultEnabled,
        onAddFood: {},
        onEditEntry: { _ in }
    )
}
