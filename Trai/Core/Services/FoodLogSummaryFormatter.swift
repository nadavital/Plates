//
//  FoodLogSummaryFormatter.swift
//  Trai
//

import Foundation

enum FoodLogSummaryFormatter {
    static func promptSummary(
        for entries: [FoodEntry],
        label: String,
        maxEntries: Int = 8
    ) -> String {
        let sortedEntries = entries.sorted { $0.loggedAt < $1.loggedAt }
        guard !sortedEntries.isEmpty else {
            return "\(label): no logged food entries."
        }

        let totalCalories = sortedEntries.reduce(0) { $0 + $1.calories }
        let totalProtein = Int(sortedEntries.reduce(0.0) { $0 + $1.proteinGrams }.rounded())
        let totalCarbs = Int(sortedEntries.reduce(0.0) { $0 + $1.carbsGrams }.rounded())
        let totalFat = Int(sortedEntries.reduce(0.0) { $0 + $1.fatGrams }.rounded())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        var lines: [String] = [
            "\(label): \(sortedEntries.count) entr\(sortedEntries.count == 1 ? "y" : "ies")",
        ]

        for entry in sortedEntries.prefix(maxEntries) {
            lines.append(
                "- \(timeFormatter.string(from: entry.loggedAt)): \(entry.displayEmoji) \(entry.name) (\(entry.calories) kcal, P \(Int(entry.proteinGrams.rounded()))g, C \(Int(entry.carbsGrams.rounded()))g, F \(Int(entry.fatGrams.rounded()))g)"
            )
        }

        if sortedEntries.count > maxEntries {
            let remainingCount = sortedEntries.count - maxEntries
            lines.append("- \(remainingCount) more entr\(remainingCount == 1 ? "y" : "ies") logged")
        }

        lines.append(
            "Totals: \(totalCalories) kcal, \(totalProtein)g protein, \(totalCarbs)g carbs, \(totalFat)g fat"
        )

        return lines.joined(separator: "\n")
    }
}
