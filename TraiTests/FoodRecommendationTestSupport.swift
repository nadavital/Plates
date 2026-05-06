import Foundation
import SwiftData
import XCTest
@testable import Trai

enum FoodRecommendationTestSupport {
    static func component(
        _ name: String,
        role: FoodComponentRole,
        calories: Int = 100,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0
    ) -> AcceptedFoodComponent {
        AcceptedFoodComponent(
            id: name,
            displayName: name.capitalized,
            normalizedName: FoodNormalizationService().normalizeFoodName(name),
            role: role,
            quantity: nil,
            unit: nil,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: nil,
            sugarGrams: nil,
            preparation: nil,
            confidence: .high,
            source: .ai
        )
    }

    static func entry(
        name: String,
        loggedAt: Date,
        calories: Int = 620,
        protein: Double = 42,
        carbs: Double = 58,
        fat: Double = 16,
        components: [AcceptedFoodComponent],
        sessionID: UUID? = nil,
        sessionOrder: Int = 0,
        input: FoodEntry.InputMethod = .camera
    ) -> FoodEntry {
        let normalizationService = FoodNormalizationService()
        let entry = FoodEntry(
            name: name,
            mealType: FoodEntry.MealType.lunch.rawValue,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
        entry.loggedAt = loggedAt
        entry.sessionId = sessionID
        entry.sessionOrder = sessionOrder
        entry.input = input
        let snapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .camera,
            kind: .meal,
            displayName: name,
            emoji: "🍽️",
            normalizedDisplayName: normalizationService.normalizeFoodName(name),
            nameAliases: normalizationService.aliasCandidates(for: name),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: calories,
            totalProteinGrams: protein,
            totalCarbsGrams: carbs,
            totalFatGrams: fat,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: components,
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: normalizationService.mealTimeBucket(for: loggedAt),
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: ["name"],
            wasUserEdited: false
        )
        entry.setAcceptedSnapshot(snapshot)
        return entry
    }

    static func suggestion(
        name: String,
        calories: Int = 620,
        protein: Double = 42,
        carbs: Double = 58,
        fat: Double = 16,
        components: [AcceptedFoodComponent],
        memoryID: UUID = UUID()
    ) -> FoodSuggestion {
        let suggestedEntry = SuggestedFoodEntry(
            id: name,
            name: name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            servingSize: "1 serving",
            emoji: "🍽️",
            components: components.map {
                SuggestedFoodComponent(
                    id: $0.id,
                    displayName: $0.displayName,
                    role: $0.role.rawValue,
                    calories: $0.calories,
                    proteinGrams: $0.proteinGrams,
                    carbsGrams: $0.carbsGrams,
                    fatGrams: $0.fatGrams,
                    confidence: "high"
                )
            },
            mealKind: FoodMemoryKind.meal.rawValue,
            notes: nil,
            confidence: "high",
            schemaVersion: 2
        )
        return FoodSuggestion(
            memoryID: memoryID,
            title: name,
            subtitle: "",
            detail: "",
            emoji: "🍽️",
            relevanceScore: 1,
            suggestedEntry: suggestedEntry
        )
    }

    static func day(_ offset: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 1 + offset
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components)!
    }
}
