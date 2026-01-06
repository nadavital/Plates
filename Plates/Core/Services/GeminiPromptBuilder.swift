//
//  GeminiPromptBuilder.swift
//  Plates
//
//  Core prompts: food analysis, workout suggestions, system prompt, nutrition advice
//  See also: GeminiChatPrompts.swift, GeminiPlanPrompts.swift
//

import Foundation

/// Builds prompts for Gemini API requests
enum GeminiPromptBuilder {

    // MARK: - Food Analysis

    static func buildFoodAnalysisPrompt(description: String?) -> String {
        var prompt = """
        Analyze this food and provide accurate nutritional information.

        Be accurate with calorie and macro estimates based on typical portion sizes.
        If you see multiple items, estimate the total for everything visible.
        """

        if let description {
            prompt += "\n\nUser description: \(description)"
        }

        return prompt
    }

    /// JSON schema for food analysis structured output
    static var foodAnalysisSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "Name of the food item or meal"
                ],
                "calories": [
                    "type": "integer",
                    "description": "Total calories"
                ],
                "proteinGrams": [
                    "type": "number",
                    "description": "Protein in grams"
                ],
                "carbsGrams": [
                    "type": "number",
                    "description": "Carbohydrates in grams"
                ],
                "fatGrams": [
                    "type": "number",
                    "description": "Fat in grams"
                ],
                "fiberGrams": [
                    "type": "number",
                    "description": "Dietary fiber in grams",
                    "nullable": true
                ],
                "servingSize": [
                    "type": "string",
                    "description": "Estimated serving size",
                    "nullable": true
                ],
                "confidence": [
                    "type": "string",
                    "enum": ["high", "medium", "low"],
                    "description": "Confidence level of the estimate"
                ],
                "notes": [
                    "type": "string",
                    "description": "Any relevant notes about the estimation",
                    "nullable": true
                ],
                "emoji": [
                    "type": "string",
                    "description": "A single relevant emoji for this food (e.g., ☕, 🥗, 🍳, 🍕, 🥪)",
                    "nullable": true
                ]
            ],
            "required": ["name", "calories", "proteinGrams", "carbsGrams", "fatGrams", "confidence", "emoji"]
        ]
    }

    // MARK: - Workout Suggestions

    static func buildWorkoutSuggestionPrompt(
        history: [WorkoutSession],
        goal: String,
        availableTime: Int?
    ) -> String {
        var prompt = """
        You are Trai, a friendly fitness coach. Suggest a workout based on the user's history and goals. Never refer to yourself as an AI or assistant.

        User's Goal: \(goal)
        """

        if let time = availableTime {
            prompt += "\nAvailable Time: \(time) minutes"
        }

        if !history.isEmpty {
            prompt += "\n\nRecent Workouts:\n"
            for session in history.suffix(5) {
                let name = session.displayName
                let date = session.loggedAt.formatted(date: .abbreviated, time: .omitted)
                if session.isStrengthTraining {
                    prompt += "- \(date): \(name) - \(session.sets) sets x \(session.reps) reps"
                    if let weight = session.weightKg {
                        prompt += " @ \(Int(weight))kg"
                    }
                    prompt += "\n"
                } else if let duration = session.formattedDuration {
                    prompt += "- \(date): \(name) - \(duration)\n"
                }
            }
        }

        prompt += """

        Provide a specific workout plan with:
        1. Warm-up (5 minutes)
        2. Main workout (exercises, sets, reps, rest times)
        3. Cool-down (5 minutes)

        Keep the response concise and actionable.
        """

        return prompt
    }

    // MARK: - System Prompt

    static func buildSystemPrompt(context: FitnessContext) -> String {
        var prompt = """
        You are Trai, a friendly fitness and nutrition coach. Never refer to yourself as an AI, Gemini, or assistant. Here's the current context:

        Goal: \(context.userGoal)
        Daily Calorie Target: \(context.dailyCalorieGoal) kcal
        Daily Protein Target: \(context.dailyProteinGoal)g

        Today's Progress:
        - Calories consumed: \(context.todaysCalories) kcal
        - Protein consumed: \(Int(context.todaysProtein))g
        """

        if let current = context.currentWeight, let target = context.targetWeight {
            prompt += "\n- Current weight: \(Int(current))kg, Target: \(Int(target))kg"
        }

        if !context.recentWorkouts.isEmpty {
            prompt += "\n\nRecent workouts: \(context.recentWorkouts.joined(separator: ", "))"
        }

        prompt += """

        Be encouraging, specific, and actionable in your advice. Keep responses concise but helpful.
        """

        return prompt
    }

    // MARK: - Nutrition Advice

    static func buildNutritionAdvicePrompt(meals: [FoodEntry], profile: UserProfile) -> String {
        let totalCalories = meals.reduce(0) { $0 + $1.calories }
        let totalProtein = meals.reduce(0.0) { $0 + $1.proteinGrams }
        let totalCarbs = meals.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat = meals.reduce(0.0) { $0 + $1.fatGrams }

        return """
        User's Daily Goals:
        - Calories: \(profile.dailyCalorieGoal) kcal
        - Protein: \(profile.dailyProteinGoal)g
        - Carbs: \(profile.dailyCarbsGoal)g
        - Fat: \(profile.dailyFatGoal)g

        Today's intake so far:
        - Calories: \(totalCalories) kcal (\(Int(Double(totalCalories) / Double(profile.dailyCalorieGoal) * 100))%)
        - Protein: \(Int(totalProtein))g (\(Int(totalProtein / Double(profile.dailyProteinGoal) * 100))%)
        - Carbs: \(Int(totalCarbs))g (\(Int(totalCarbs / Double(profile.dailyCarbsGoal) * 100))%)
        - Fat: \(Int(totalFat))g (\(Int(totalFat / Double(profile.dailyFatGoal) * 100))%)

        Meals logged:
        \(meals.map { "- \($0.meal.displayName): \($0.name) (\($0.calories) kcal)" }.joined(separator: "\n"))

        Based on this, provide brief nutrition advice for the rest of the day. Suggest specific foods or meals that would help them hit their remaining macros.
        """
    }
}
