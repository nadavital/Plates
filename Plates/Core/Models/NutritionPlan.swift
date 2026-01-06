//
//  NutritionPlan.swift
//  Plates
//
//  Created by AI Assistant on 12/25/25.
//

import Foundation

/// Represents an AI-generated nutrition and fitness plan
/// This is a Codable struct (not SwiftData) since it's generated dynamically
struct NutritionPlan: Codable, Equatable {
    let dailyTargets: DailyTargets
    let rationale: String
    let macroSplit: MacroSplit
    let nutritionGuidelines: [String]
    let mealTimingSuggestion: String
    let weeklyAdjustments: WeeklyAdjustments?
    let warnings: [String]?

    // Enhanced insights
    let progressInsights: ProgressInsights?

    struct DailyTargets: Codable, Equatable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let fiber: Int
        let sugar: Int

        // Custom decoder to handle older plans without sugar
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            calories = try container.decode(Int.self, forKey: .calories)
            protein = try container.decode(Int.self, forKey: .protein)
            carbs = try container.decode(Int.self, forKey: .carbs)
            fat = try container.decode(Int.self, forKey: .fat)
            fiber = try container.decode(Int.self, forKey: .fiber)
            sugar = try container.decodeIfPresent(Int.self, forKey: .sugar) ?? 50 // Default if not present
        }

        init(calories: Int, protein: Int, carbs: Int, fat: Int, fiber: Int, sugar: Int = 50) {
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.fiber = fiber
            self.sugar = sugar
        }
    }

    struct MacroSplit: Codable, Equatable {
        let proteinPercent: Int
        let carbsPercent: Int
        let fatPercent: Int
    }

    struct WeeklyAdjustments: Codable, Equatable {
        let trainingDayCalories: Int?
        let restDayCalories: Int?
        let recommendation: String?
    }

    struct ProgressInsights: Codable, Equatable {
        let estimatedWeeklyChange: String // e.g., "-0.5 kg" or "+0.25 kg"
        let estimatedTimeToGoal: String? // e.g., "12-16 weeks" or null if maintenance
        let calorieDeficitOrSurplus: Int // negative = deficit, positive = surplus
        let shortTermMilestone: String // e.g., "Lose 2kg in the first month"
        let longTermOutlook: String // e.g., "Sustainable progress toward your goal"
    }

    /// Placeholder plan used for binding when actual plan is nil
    static let placeholder = NutritionPlan(
        dailyTargets: DailyTargets(calories: 2000, protein: 150, carbs: 200, fat: 65, fiber: 30, sugar: 50),
        rationale: "",
        macroSplit: MacroSplit(proteinPercent: 30, carbsPercent: 40, fatPercent: 30),
        nutritionGuidelines: [],
        mealTimingSuggestion: "",
        weeklyAdjustments: nil,
        warnings: nil,
        progressInsights: nil
    )

    // MARK: - JSON Serialization

    /// Serialize plan to JSON string for storage
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    /// Deserialize plan from JSON string
    static func fromJSON(_ json: String) -> NutritionPlan? {
        guard let data = json.data(using: .utf8),
              let plan = try? JSONDecoder().decode(NutritionPlan.self, from: data) else {
            return nil
        }
        return plan
    }
}

// MARK: - Request Model for AI Plan Generation

struct PlanGenerationRequest {
    let name: String
    let age: Int
    let gender: UserProfile.Gender
    let heightCm: Double
    let weightKg: Double
    let targetWeightKg: Double?
    let activityLevel: UserProfile.ActivityLevel
    let activityNotes: String
    let goal: UserProfile.GoalType
    let additionalNotes: String

    /// Calculate BMR using Mifflin-St Jeor equation
    var bmr: Double {
        let base = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age))
        switch gender {
        case .male:
            return base + 5
        case .female:
            return base - 161
        case .notSpecified:
            // Use average of male/female formulas
            return base - 78
        }
    }

    /// Calculate TDEE (Total Daily Energy Expenditure)
    var tdee: Double {
        bmr * activityLevel.multiplier
    }

    /// Suggested calorie target based on goal
    var suggestedCalories: Int {
        let base = tdee
        switch goal {
        case .loseWeight:
            return Int(base - 500) // ~1 lb/week loss
        case .loseFat:
            return Int(base - 400) // Slower for muscle preservation
        case .buildMuscle:
            return Int(base + 300) // Lean bulk
        case .recomposition:
            return Int(base) // Maintenance with recomp
        case .maintenance:
            return Int(base)
        case .performance:
            return Int(base + 200) // Slight surplus for performance
        case .health:
            return Int(base)
        }
    }
}

// MARK: - Default Plan Generator (Fallback)

extension NutritionPlan {
    /// Creates a default plan using TDEE calculations when AI is unavailable
    static func createDefault(from request: PlanGenerationRequest) -> NutritionPlan {
        let calories = request.suggestedCalories

        // Determine macro split based on goal
        let (proteinPct, carbsPct, fatPct) = macroSplitForGoal(request.goal)

        let protein = Int(Double(calories) * Double(proteinPct) / 100 / 4)
        let carbs = Int(Double(calories) * Double(carbsPct) / 100 / 4)
        let fat = Int(Double(calories) * Double(fatPct) / 100 / 9)
        let fiber = 30 // Standard recommendation
        let sugar = 50 // Standard recommendation (~10% of calories from added sugar)

        let rationale = buildDefaultRationale(request: request, calories: calories)

        return NutritionPlan(
            dailyTargets: DailyTargets(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                fiber: fiber,
                sugar: sugar
            ),
            rationale: rationale,
            macroSplit: MacroSplit(
                proteinPercent: proteinPct,
                carbsPercent: carbsPct,
                fatPercent: fatPct
            ),
            nutritionGuidelines: defaultGuidelines(for: request.goal),
            mealTimingSuggestion: "3-4 meals spread evenly throughout the day",
            weeklyAdjustments: nil,
            warnings: generateWarnings(for: request),
            progressInsights: generateProgressInsights(for: request, calories: calories)
        )
    }

    private static func macroSplitForGoal(_ goal: UserProfile.GoalType) -> (Int, Int, Int) {
        switch goal {
        case .loseWeight:
            return (30, 40, 30) // Balanced deficit
        case .loseFat:
            return (40, 30, 30) // High protein for muscle retention
        case .buildMuscle:
            return (30, 45, 25) // Higher carbs for energy
        case .recomposition:
            return (35, 35, 30) // High protein, moderate everything
        case .maintenance:
            return (25, 45, 30) // Standard balanced
        case .performance:
            return (25, 50, 25) // High carbs for athletic performance
        case .health:
            return (25, 45, 30) // Standard balanced
        }
    }

    private static func buildDefaultRationale(request: PlanGenerationRequest, calories: Int) -> String {
        var parts: [String] = []

        parts.append("Based on your profile (\(request.age) years old, \(Int(request.heightCm))cm, \(Int(request.weightKg))kg)")
        parts.append("your estimated daily energy expenditure is \(Int(request.tdee)) calories.")

        switch request.goal {
        case .loseWeight, .loseFat:
            parts.append("To support your weight loss goal, we've set a moderate deficit of \(Int(request.tdee) - calories) calories below maintenance.")
        case .buildMuscle:
            parts.append("To support muscle growth, we've added \(calories - Int(request.tdee)) calories above maintenance for a lean bulk.")
        case .recomposition:
            parts.append("For body recomposition, we're keeping you at maintenance calories with higher protein to support muscle growth while losing fat.")
        default:
            parts.append("Your calorie target is set to maintain your current weight while supporting your \(request.goal.displayName.lowercased()) goals.")
        }

        return parts.joined(separator: " ")
    }

    private static func defaultGuidelines(for goal: UserProfile.GoalType) -> [String] {
        var guidelines = [
            "Aim for protein at each meal (25-40g per serving)",
            "Stay hydrated with at least 8 glasses of water daily",
            "Include vegetables with most meals for fiber and micronutrients"
        ]

        switch goal {
        case .loseWeight, .loseFat:
            guidelines.append("Prioritize whole, unprocessed foods to stay fuller longer")
            guidelines.append("Consider meal prepping to maintain consistency")
        case .buildMuscle:
            guidelines.append("Time carbohydrates around your workouts for optimal energy")
            guidelines.append("Don't skip post-workout nutrition")
        case .performance:
            guidelines.append("Fuel properly before training sessions")
            guidelines.append("Focus on recovery nutrition post-workout")
        default:
            break
        }

        return guidelines
    }

    private static func generateWarnings(for request: PlanGenerationRequest) -> [String]? {
        var warnings: [String] = []

        if request.suggestedCalories < 1200 {
            warnings.append("Your calculated calorie target is quite low. Consider consulting a healthcare provider.")
        }

        if let target = request.targetWeightKg {
            let weightDiff = request.weightKg - target
            if weightDiff > 20 {
                warnings.append("Your weight loss goal is ambitious. Consider setting intermediate milestones.")
            }
        }

        return warnings.isEmpty ? nil : warnings
    }

    private static func generateProgressInsights(for request: PlanGenerationRequest, calories: Int) -> ProgressInsights {
        let deficitOrSurplus = calories - Int(request.tdee)

        // Calculate weekly change (~7700 kcal = 1kg)
        let weeklyCalorieDiff = deficitOrSurplus * 7
        let weeklyKgChange = Double(weeklyCalorieDiff) / 7700.0

        let weeklyChangeStr: String
        if weeklyKgChange < -0.05 {
            weeklyChangeStr = String(format: "%.1f kg", weeklyKgChange)
        } else if weeklyKgChange > 0.05 {
            weeklyChangeStr = String(format: "+%.1f kg", weeklyKgChange)
        } else {
            weeklyChangeStr = "Maintain current weight"
        }

        // Estimate time to goal
        var timeToGoal: String? = nil
        if let targetWeight = request.targetWeightKg {
            let weightDiff = request.weightKg - targetWeight
            if abs(weightDiff) > 0.5 && abs(weeklyKgChange) > 0.1 {
                let weeksNeeded = abs(weightDiff / weeklyKgChange)
                if weeksNeeded < 52 {
                    timeToGoal = "\(Int(weeksNeeded))-\(Int(weeksNeeded * 1.25)) weeks"
                } else {
                    let months = Int(weeksNeeded / 4)
                    timeToGoal = "\(months)-\(Int(Double(months) * 1.25)) months"
                }
            }
        }

        // Short term milestone
        let shortTerm: String
        switch request.goal {
        case .loseWeight, .loseFat:
            let monthlyLoss = abs(weeklyKgChange * 4)
            shortTerm = String(format: "Aim to lose %.1f kg in the first month", monthlyLoss)
        case .buildMuscle:
            shortTerm = "Focus on progressive overload in your first 4 weeks"
        case .recomposition:
            shortTerm = "Track measurements weekly—the scale may not move much"
        default:
            shortTerm = "Build consistent eating habits over the first month"
        }

        // Long term outlook
        let longTerm: String
        switch request.goal {
        case .loseWeight, .loseFat:
            longTerm = "Sustainable fat loss with preserved muscle mass"
        case .buildMuscle:
            longTerm = "Gradual strength and muscle gains with minimal fat gain"
        case .recomposition:
            longTerm = "Improved body composition while maintaining weight"
        case .performance:
            longTerm = "Optimized energy for athletic performance"
        default:
            longTerm = "Maintained health and energy through balanced nutrition"
        }

        return ProgressInsights(
            estimatedWeeklyChange: weeklyChangeStr,
            estimatedTimeToGoal: timeToGoal,
            calorieDeficitOrSurplus: deficitOrSurplus,
            shortTermMilestone: shortTerm,
            longTermOutlook: longTerm
        )
    }
}
