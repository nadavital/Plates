//
//  MacroType.swift
//  Plates
//
//  Represents the types of macronutrients that can be tracked
//

import SwiftUI

/// Represents the types of macronutrients that users can track
enum MacroType: String, CaseIterable, Identifiable, Codable {
    case protein
    case carbs
    case fat
    case fiber
    case sugar

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        }
    }

    /// Short abbreviation for compact displays
    var shortName: String {
        switch self {
        case .protein: "P"
        case .carbs: "C"
        case .fat: "F"
        case .fiber: "Fi"
        case .sugar: "S"
        }
    }

    /// Color used for this macro in UI
    var color: Color {
        switch self {
        case .protein: .blue
        case .carbs: .orange
        case .fat: .purple
        case .fiber: .green
        case .sugar: .pink
        }
    }

    /// Calories per gram (used for calorie contribution calculations)
    var caloriesPerGram: Double {
        switch self {
        case .protein: 4
        case .carbs: 4
        case .fat: 9
        case .fiber: 0  // Fiber doesn't contribute to calories
        case .sugar: 4  // Sugar is a carb, 4 cal/g
        }
    }

    /// Whether this macro contributes to total calories
    var contributesToCalories: Bool {
        caloriesPerGram > 0
    }

    /// Description of what this macro does
    var description: String {
        switch self {
        case .protein: "Builds and repairs muscle tissue"
        case .carbs: "Primary energy source for your body"
        case .fat: "Essential for hormone production and nutrient absorption"
        case .fiber: "Supports digestive health and satiety"
        case .sugar: "Quick energy, best consumed in moderation"
        }
    }

    /// Icon name for this macro
    var iconName: String {
        switch self {
        case .protein: "figure.strengthtraining.traditional"
        case .carbs: "bolt.fill"
        case .fat: "drop.fill"
        case .fiber: "leaf.fill"
        case .sugar: "cube.fill"
        }
    }

    /// The default set of enabled macros for new users
    static var defaultEnabled: Set<MacroType> {
        [.protein, .carbs, .fat, .fiber]
    }

    /// All macros sorted in display order
    static var displayOrder: [MacroType] {
        [.protein, .carbs, .fat, .fiber, .sugar]
    }
}

// MARK: - Set Extension for JSON Serialization

extension Set where Element == MacroType {
    /// Encode set to JSON string for CloudKit storage
    var jsonString: String {
        let array = self.map { $0.rawValue }.sorted()
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Decode set from JSON string
    init(jsonString: String) {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            self = MacroType.defaultEnabled
            return
        }
        self = Set(array.compactMap { MacroType(rawValue: $0) })
    }
}
