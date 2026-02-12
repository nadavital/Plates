//
//  GeminiPlanPrompts.swift
//  Trai
//
//  Onboarding plan generation and refinement prompts
//

import Foundation

// MARK: - Plan Generation

extension GeminiPromptBuilder {

    static func buildPlanGenerationPrompt(
        request: PlanGenerationRequest,
        enabledMacros: Set<MacroType>? = nil,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a certified nutritionist and fitness coach creating a personalized nutrition plan. Never mention being an AI or assistant.
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        USER PROFILE:
        - Name: \(request.name)
        - Age: \(request.age) years old
        - Gender: \(request.gender.displayName)
        - Height: \(Int(request.heightCm)) cm
        - Current Weight: \(String(format: "%.1f", request.weightKg)) kg
        """

        if let target = request.targetWeightKg {
            prompt += "\n- Target Weight: \(String(format: "%.1f", target)) kg"
        }

        prompt += """

        - Activity Level: \(request.activityLevel.displayName) (\(request.activityLevel.description))
        - Primary Goal: \(request.goal.displayName) - \(request.goal.description)
        """

        if !request.activityNotes.isEmpty {
            prompt += "\n- Activity Details: \(request.activityNotes)"
        }

        if !request.additionalNotes.isEmpty {
            prompt += "\n- Additional Notes: \(request.additionalNotes)"
        }

        // Add macro tracking preferences
        if let macros = enabledMacros {
            let macroNames = macros.map { $0.displayName }.sorted().joined(separator: ", ")
            prompt += "\n- Tracking Macros: \(macroNames.isEmpty ? "Calories only" : macroNames)"

            // Note if user is tracking sugar
            if macros.contains(.sugar) {
                prompt += "\n  (User wants to monitor sugar intake)"
            }
        }

        prompt += """


        CALCULATED VALUES (for reference):
        - BMR (Mifflin-St Jeor): \(Int(request.bmr)) calories
        - TDEE: \(Int(request.tdee)) calories
        - Suggested starting calories: \(request.suggestedCalories) calories

        INSTRUCTIONS:
        Create a personalized nutrition plan. You may adjust the suggested calories if you have good reason based on the user's specific situation.

        Include progress insights with realistic estimates:
        - estimatedWeeklyChange: Expected weekly weight change (e.g., "-0.5 kg" for deficit, "+0.2 kg" for surplus, "Maintain" for maintenance)
        - estimatedTimeToGoal: If they have a target weight, estimate how long to reach it (e.g., "12-16 weeks")
        - calorieDeficitOrSurplus: The daily calorie difference from TDEE (negative = deficit, positive = surplus)
        - shortTermMilestone: A specific, achievable 4-week milestone
        - longTermOutlook: What to expect over 3-6 months

        Be specific to this person's profile. Don't give generic advice - tailor everything to their age, gender, activity level, goal, and any restrictions.
        """

        return prompt
    }

    static var nutritionPlanSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "dailyTargets": [
                    "type": "object",
                    "properties": [
                        "calories": ["type": "integer"],
                        "protein": ["type": "integer"],
                        "carbs": ["type": "integer"],
                        "fat": ["type": "integer"],
                        "fiber": ["type": "integer"],
                        "sugar": ["type": "integer"]
                    ],
                    "required": ["calories", "protein", "carbs", "fat", "fiber", "sugar"]
                ],
                "rationale": ["type": "string"],
                "macroSplit": [
                    "type": "object",
                    "properties": [
                        "proteinPercent": ["type": "integer"],
                        "carbsPercent": ["type": "integer"],
                        "fatPercent": ["type": "integer"]
                    ],
                    "required": ["proteinPercent", "carbsPercent", "fatPercent"]
                ],
                "nutritionGuidelines": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "mealTimingSuggestion": ["type": "string"],
                "weeklyAdjustments": [
                    "type": "object",
                    "properties": [
                        "trainingDayCalories": ["type": "integer"],
                        "restDayCalories": ["type": "integer"],
                        "recommendation": ["type": "string"]
                    ],
                    "nullable": true
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ],
                "progressInsights": [
                    "type": "object",
                    "properties": [
                        "estimatedWeeklyChange": ["type": "string"],
                        "estimatedTimeToGoal": ["type": "string", "nullable": true],
                        "calorieDeficitOrSurplus": ["type": "integer"],
                        "shortTermMilestone": ["type": "string"],
                        "longTermOutlook": ["type": "string"]
                    ],
                    "required": ["estimatedWeeklyChange", "calorieDeficitOrSurplus", "shortTermMilestone", "longTermOutlook"]
                ]
            ],
            "required": ["dailyTargets", "rationale", "macroSplit", "nutritionGuidelines", "mealTimingSuggestion", "progressInsights"]
        ]
    }
}

// MARK: - Plan Refinement

extension GeminiPromptBuilder {

    static func buildPlanRefinementPrompt(
        currentPlan: NutritionPlan,
        request: PlanGenerationRequest,
        userMessage: String,
        conversationHistory: [PlanChatMessage],
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a friendly nutrition coach chatting with the user about their plan. Never refer to yourself as an AI or assistant. This is a casual chat, so keep responses SHORT and conversational (1-3 sentences max).
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        RESPONSE TYPES - Choose ONE:
        1. "message" - For questions, clarifications, or asking follow-ups. Use this MOST of the time.
        2. "proposePlan" - When you want to SUGGEST a new plan. The user will see a preview and can accept/reject.
        3. "planUpdate" - ONLY use when you are 100% certain this matches what the user wants (e.g., they explicitly confirmed a proposal).

        CURRENT USER PROFILE:
        - Name: \(request.name)
        - Age: \(request.age) years old
        - Gender: \(request.gender.displayName)
        - Height: \(Int(request.heightCm)) cm
        - Weight: \(String(format: "%.1f", request.weightKg)) kg
        - Activity Level: \(request.activityLevel.displayName)
        - Goal: \(request.goal.displayName)

        CURRENT PLAN:
        - Calories: \(currentPlan.dailyTargets.calories) kcal
        - Protein: \(currentPlan.dailyTargets.protein)g
        - Carbs: \(currentPlan.dailyTargets.carbs)g
        - Fat: \(currentPlan.dailyTargets.fat)g
        - Fiber: \(currentPlan.dailyTargets.fiber)g
        - Sugar: \(currentPlan.dailyTargets.sugar)g

        """

        // Add conversation history
        if !conversationHistory.isEmpty {
            prompt += "\nCONVERSATION HISTORY:\n"
            for msg in conversationHistory.suffix(6) {
                let role = msg.role == .user ? "User" : "Assistant"
                prompt += "\(role): \(msg.content)\n"
            }
        }

        prompt += """

        USER'S MESSAGE: \(userMessage)

        GUIDELINES:
        - Keep responses SHORT and chat-like. No walls of text!
        - Ask follow-up questions to understand what they really want
        - If they ask to change something, ask clarifying questions first (e.g., "How much lower would you like the calories?" or "Any specific reason?")
        - Only use "proposePlan" when you have enough info to make a good suggestion
        - Only use "planUpdate" if the user explicitly accepts a proposal or gives very clear instructions
        - Keep the selected coach tone consistent with the rest of the app
        """

        return prompt
    }

    static var planRefinementSchema: [String: Any] {
        let planSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "dailyTargets": [
                    "type": "object",
                    "properties": [
                        "calories": ["type": "integer"],
                        "protein": ["type": "integer"],
                        "carbs": ["type": "integer"],
                        "fat": ["type": "integer"],
                        "fiber": ["type": "integer"],
                        "sugar": ["type": "integer"]
                    ],
                    "required": ["calories", "protein", "carbs", "fat", "fiber", "sugar"]
                ],
                "rationale": ["type": "string"],
                "macroSplit": [
                    "type": "object",
                    "properties": [
                        "proteinPercent": ["type": "integer"],
                        "carbsPercent": ["type": "integer"],
                        "fatPercent": ["type": "integer"]
                    ],
                    "required": ["proteinPercent", "carbsPercent", "fatPercent"]
                ],
                "nutritionGuidelines": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "mealTimingSuggestion": ["type": "string"],
                "weeklyAdjustments": [
                    "type": "object",
                    "nullable": true,
                    "properties": [
                        "trainingDayCalories": ["type": "integer"],
                        "restDayCalories": ["type": "integer"],
                        "recommendation": ["type": "string"]
                    ]
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ],
                "progressInsights": [
                    "type": "object",
                    "properties": [
                        "estimatedWeeklyChange": ["type": "string"],
                        "estimatedTimeToGoal": ["type": "string", "nullable": true],
                        "calorieDeficitOrSurplus": ["type": "integer"],
                        "shortTermMilestone": ["type": "string"],
                        "longTermOutlook": ["type": "string"]
                    ],
                    "required": ["estimatedWeeklyChange", "calorieDeficitOrSurplus", "shortTermMilestone", "longTermOutlook"]
                ]
            ],
            "required": ["dailyTargets", "rationale", "macroSplit", "nutritionGuidelines", "mealTimingSuggestion", "progressInsights"]
        ]

        return [
            "type": "object",
            "properties": [
                "responseType": [
                    "type": "string",
                    "enum": ["message", "proposePlan", "planUpdate"]
                ],
                "message": ["type": "string"],
                "proposedPlan": ["type": "object", "nullable": true] + planSchema,
                "updatedPlan": ["type": "object", "nullable": true] + planSchema
            ],
            "required": ["responseType", "message"]
        ]
    }
}

// Helper to merge dictionaries
private func + (lhs: [String: Any], rhs: [String: Any]) -> [String: Any] {
    var result = lhs
    for (key, value) in rhs {
        result[key] = value
    }
    return result
}
