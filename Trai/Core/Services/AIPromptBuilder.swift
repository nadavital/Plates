//
//  AIPromptBuilder.swift
//  Trai
//
//  Core prompts: food analysis, workout suggestions, system prompt, nutrition advice
//  See also: AIChatPrompts.swift, AIPlanPrompts.swift
//

import Foundation

/// Builds prompts for Trai AI requests
enum AIPromptBuilder {

    // MARK: - Food Analysis

    static func buildFoodAnalysisPrompt(description: String?) -> String {
        var prompt = """
        Analyze this food and provide accurate nutritional information.

        You are an expert nutrition coach and food logger. Be decisive and professionally confident when the primary food is identifiable.
        Your top priority is producing the most accurate loggable estimate possible from the image and any user description.
        Use visual evidence first, then reasonable nutrition estimation based on typical real-world preparation and portion sizes.

        Rules:
        - Focus on the food or drink the user most likely intends to log (main/foreground item or plated meal).
        - Ignore incidental/background foods, nearby items, other people's meals, and unopened packaging unless clearly part of what they ate.
        - Estimate portion size from visible cues such as plate size, bowl size, cup size, packaging, hand scale, cut pieces, fill level, and common serving presentations.
        - If the food appears cooked in a recognizable way, infer the most likely cooking method when it materially affects calories or macros. Use visual cues like grill marks, breading, frying texture, roasting, sauteed appearance, sauces, oil sheen, or visible preparation style.
        - You may infer common included components when they are strongly implied by the visible food presentation, but do NOT add speculative extras that are not reasonably supported by the image or description.
        - If one meal contains multiple clear components (for example a plate plus a visible side), include those visible components together.
        - If the image is a beverage, identify the beverage directly. For plain water or plain sparkling water with no visible additions, return water with 0 calories and 0g macros.
        - Prefer the most specific food name that is actually supported by the image. Do not guess a polished dish name when multiple materially different foods are still plausible.
        - When the primary food is identifiable, give your best expert estimate instead of hesitating. Use normal real-world assumptions about preparation and serving size unless the image contradicts them.
        - In notes, briefly capture the main assumptions that materially affected calories, macros, or serving size.
        - Only use the failure fallback when no identifiable food or drink is visible at all.
        - Do NOT use the failure fallback just because portion size, recipe details, or cooking method are uncertain. If the food or drink is identifiable, choose a generic visible label and give the best estimate.
        - If there is no identifiable loggable food or drink visible at all, return the sentinel result with:
          name: "Unclear food or drink"
          calories: 0
          proteinGrams: 0
          carbsGrams: 0
          fatGrams: 0
          confidence: "low"
          notes: "The image is not clear enough for a reliable food estimate."
          emoji: "🍽️"

        Estimation guidance:
        - Be realistic and nutritionally useful. Use typical portion sizes only when visually plausible.
        - If quantity is uncertain, estimate the most likely visible serving instead of refusing, unless the food itself is too unclear to identify.
        - If preparation style is visually likely and meaningfully changes calories or macros, incorporate that into the estimate.
        - Macros and calories should reflect the total visible serving the user is most likely trying to log.
        - Use confidence "high" or "medium" for most identifiable meals and drinks. Use confidence "low" only when the primary item itself is genuinely hard to identify.
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
                    "description": "Name of the visible food or drink. Use a generic visible label if uncertain, not a specific guess."
                ],
                "calories": [
                    "type": "integer",
                    "description": "Estimated total calories for the visible serving. Use 0 only when the item is clearly zero-calorie, such as plain water, or the image is too unclear to identify a loggable item."
                ],
                "proteinGrams": [
                    "type": "number",
                    "description": "Estimated protein in grams for the visible serving"
                ],
                "carbsGrams": [
                    "type": "number",
                    "description": "Estimated carbohydrates in grams for the visible serving"
                ],
                "fatGrams": [
                    "type": "number",
                    "description": "Estimated fat in grams for the visible serving"
                ],
                "fiberGrams": [
                    "type": "number",
                    "description": "Estimated dietary fiber in grams if reasonably inferable",
                    "nullable": true
                ],
                "servingSize": [
                    "type": "string",
                    "description": "Estimated visible serving size such as '1 medium bowl' or '16 oz bottle'",
                    "nullable": true
                ],
                "confidence": [
                    "type": "string",
                    "enum": ["high", "medium", "low"],
                    "description": "Confidence level of the identification and nutrition estimate. Use low when the primary item itself is hard to identify.",
                    "nullable": true
                ],
                "notes": [
                    "type": "string",
                    "description": "Short explanation of uncertainty, assumptions, or what is not visible. If confidence is low, explain why.",
                    "nullable": true
                ],
                "emoji": [
                    "type": "string",
                    "description": "A single relevant emoji for the identified food or drink. Use 🍽️ for unclear items.",
                    "nullable": true
                ]
            ],
            "required": ["name", "calories", "proteinGrams", "carbsGrams", "fatGrams"]
        ]
    }

    // MARK: - Workout Suggestions

    static func buildWorkoutSuggestionPrompt(
        history: [WorkoutSession],
        goal: String,
        availableTime: Int?,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a friendly fitness coach. Suggest a workout based on the user's history and goals. Never refer to yourself as an AI or assistant.
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

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

    static func buildSystemPrompt(
        context: FitnessContext,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a friendly fitness and nutrition coach. Never refer to yourself as an AI, language model, or assistant. Here's the current context:
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

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

        Be specific and actionable in your advice. Keep responses concise and helpful.
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
