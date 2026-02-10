//
//  WidgetData.swift
//  Shared
//
//  Widget payload shared by app and widget extension.
//

import Foundation

struct WidgetData: Codable {
    var caloriesConsumed: Int
    var calorieGoal: Int
    var proteinConsumed: Int
    var proteinGoal: Int
    var carbsConsumed: Int
    var carbsGoal: Int
    var fatConsumed: Int
    var fatGoal: Int
    var readyMuscleCount: Int
    var recommendedWorkout: String?
    var workoutStreak: Int
    var todayWorkoutCompleted: Bool
    var lastUpdated: Date

    static let empty = WidgetData(
        caloriesConsumed: 0,
        calorieGoal: 2000,
        proteinConsumed: 0,
        proteinGoal: 150,
        carbsConsumed: 0,
        carbsGoal: 200,
        fatConsumed: 0,
        fatGoal: 65,
        readyMuscleCount: 0,
        recommendedWorkout: nil,
        workoutStreak: 0,
        todayWorkoutCompleted: false,
        lastUpdated: Date()
    )

    func progress(for macro: Macro) -> Double {
        switch macro {
        case .calories:
            guard calorieGoal > 0 else { return 0 }
            return min(Double(caloriesConsumed) / Double(calorieGoal), 1.0)
        case .protein:
            guard proteinGoal > 0 else { return 0 }
            return min(Double(proteinConsumed) / Double(proteinGoal), 1.0)
        case .carbs:
            guard carbsGoal > 0 else { return 0 }
            return min(Double(carbsConsumed) / Double(carbsGoal), 1.0)
        case .fat:
            guard fatGoal > 0 else { return 0 }
            return min(Double(fatConsumed) / Double(fatGoal), 1.0)
        }
    }

    func consumed(for macro: Macro) -> Int {
        switch macro {
        case .calories: caloriesConsumed
        case .protein: proteinConsumed
        case .carbs: carbsConsumed
        case .fat: fatConsumed
        }
    }

    func goal(for macro: Macro) -> Int {
        switch macro {
        case .calories: calorieGoal
        case .protein: proteinGoal
        case .carbs: carbsGoal
        case .fat: fatGoal
        }
    }

    func remaining(for macro: Macro) -> Int {
        max(0, goal(for: macro) - consumed(for: macro))
    }

    var calorieProgress: Double { progress(for: .calories) }
    var proteinProgress: Double { progress(for: .protein) }

    enum Macro {
        case calories
        case protein
        case carbs
        case fat

        var label: String {
            switch self {
            case .calories: "Calories"
            case .protein: "Protein"
            case .carbs: "Carbs"
            case .fat: "Fat"
            }
        }

        var unit: String {
            switch self {
            case .calories: ""
            case .protein, .carbs, .fat: "g"
            }
        }
    }
}
