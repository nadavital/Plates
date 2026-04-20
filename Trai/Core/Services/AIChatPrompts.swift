//
//  AIChatPrompts.swift
//  Trai
//
//  Chat-related prompts and schemas for structured output
//

import Foundation

// MARK: - Chat Image Analysis

extension AIPromptBuilder {

    /// Build prompt for image-based chat (analyzing photos)
    static func buildImageChatPrompt(
        userMessage: String,
        context: FitnessContext,
        currentDateTime: String,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        """
        You are Trai, a friendly fitness coach. Never refer to yourself as an AI, language model, or assistant. The user is sharing an image with you.
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        Current date/time: \(currentDateTime)

        User's fitness context:
        - Goal: \(context.userGoal)
        - Daily calorie goal: \(context.dailyCalorieGoal) kcal
        - Daily protein goal: \(context.dailyProteinGoal)g
        - Today's progress: \(context.todaysCalories) kcal consumed, \(Int(context.todaysProtein))g protein

        User's message: \(userMessage)

        Look at the image and respond helpfully. The image might be:
        - Food/meal: Suggest logging it with nutritional info in suggestMealLog
        - Gym equipment: Explain how to use it or suggest exercises
        - Body progress photo: Give encouraging feedback
        - Nutrition label: Help interpret it
        - Something else: Respond appropriately

        ONLY include suggestMealLog if this is clearly food the user wants to track.
        Be confidently helpful like an expert nutrition coach when the primary food is identifiable.
        When estimating nutrition, focus on the intended meal and ignore incidental/background items not clearly part of what they ate.
        Estimate portion size from visible cues like plate size, bowl size, packaging, fill level, or common serving presentation.
        If the cooking method is visually likely and materially affects calories or macros, include the most likely preparation style in your estimate.
        Do NOT invent speculative extras that are not reasonably supported by the image or explicitly mentioned.
        If the primary food is identifiable, provide your best estimate instead of hedging.
        If the image is ambiguous, low quality, or too unclear to identify the primary food or drink reliably, do not include suggestMealLog. Instead ask the user for a clearer photo or a short description.
        If the image appears to be plain water or plain sparkling water with no visible additions, treat it as water rather than inventing a meal.
        IMPORTANT: You are SUGGESTING a meal to log - the user must confirm before it's saved. So say things like "Here's what I found" or "Want me to log this?" - NOT "I've logged this for you".
        If the user mentions they ate at a specific time, include loggedAtTime in HH:mm 24-hour format.
        If the user mentions a specific day other than today, include loggedAtDate in YYYY-MM-DD format.
        Include a relevant emoji for the food (e.g., ☕ for coffee, 🥗 for salad, 🍳 for eggs).
        If the meal has multiple clear components, include a structured components array with the major items and their approximate macros.

        Keep your message brief (1-2 sentences).
        """
    }

    /// Build prompt for text-based chat (may suggest meals from descriptions)
    static func buildTextChatPrompt(
        userMessage: String,
        context: FitnessContext,
        currentDateTime: String,
        conversationHistory: String,
        pendingSuggestion: SuggestedFoodEntry? = nil,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var pendingContext = ""
        if let pending = pendingSuggestion {
            pendingContext = """

            PENDING MEAL SUGGESTION (not yet logged):
            - Name: \(pending.name)
            - Calories: \(pending.calories) kcal
            - Protein: \(Int(pending.proteinGrams))g, Carbs: \(Int(pending.carbsGrams))g, Fat: \(Int(pending.fatGrams))g
            \(pending.loggedAtDateString.map { "- Date: \($0)" } ?? "")
            \(pending.loggedAtTime.map { "- Time: \($0)" } ?? "")
            \(pending.servingSize.map { "- Serving: \($0)" } ?? "")

            If the user asks to adjust this (e.g., "add more calories", "make it 600 calories"), update the suggestMealLog with the modified values.
            """
        }

        return """
        You are Trai, a friendly fitness coach. Never refer to yourself as an AI, language model, or assistant. Be conversational and supportive.
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        Current date/time: \(currentDateTime)

        User's fitness context:
        - Goal: \(context.userGoal)
        - Daily calorie goal: \(context.dailyCalorieGoal) kcal
        - Daily protein goal: \(context.dailyProteinGoal)g
        - Today's progress: \(context.todaysCalories) kcal consumed, \(Int(context.todaysProtein))g protein
        \(pendingContext)

        Recent conversation:
        \(conversationHistory)

        User's message: \(userMessage)

        Respond helpfully. If the user mentions eating or wanting to log food (e.g., "I had a chicken salad", "log my breakfast"), include a suggestMealLog with your best nutritional estimate.

        IMPORTANT: You are SUGGESTING a meal to log - the user must confirm before it's saved. So say things like "Here's what I found" or "Want me to log this?" - NOT "I've logged this for you".

        If there's a pending suggestion and the user wants to modify it, return the UPDATED suggestMealLog with adjusted values.

        If the user mentions they ate at a specific time (e.g., "I had lunch at 2pm"), include loggedAtTime in HH:mm 24-hour format.
        If the user mentions a specific day other than today (e.g., "I had this yesterday" or "log this for April 10"), include loggedAtDate in YYYY-MM-DD format.
        Include a relevant emoji for the food (e.g., ☕ for coffee, 🥗 for salad, 🍳 for eggs).
        If the meal has multiple clear components, include a structured components array with the major items and their approximate macros.

        Keep your response brief and conversational (1-3 sentences).
        """
    }

    /// JSON schema for chat-based image analysis (may or may not be food)
    static var chatImageAnalysisSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "message": [
                    "type": "string",
                    "description": "Friendly conversational response about the image"
                ],
                "suggestMealLog": [
                    "type": "object",
                    "description": "Only include if the image shows food that the user likely wants to log",
                    "nullable": true,
                    "properties": [
                        "name": ["type": "string"],
                        "calories": ["type": "integer"],
                        "proteinGrams": ["type": "number"],
                        "carbsGrams": ["type": "number"],
                        "fatGrams": ["type": "number"],
                        "fiberGrams": ["type": "number", "nullable": true],
                        "sugarGrams": ["type": "number", "nullable": true],
                        "servingSize": ["type": "string", "nullable": true],
                        "mealKind": [
                            "type": "string",
                            "enum": ["food", "meal"],
                            "nullable": true
                        ],
                        "notes": [
                            "type": "string",
                            "nullable": true
                        ],
                        "confidence": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "nullable": true
                        ],
                        "emoji": [
                            "type": "string",
                            "description": "A single relevant emoji for this food (e.g., ☕, 🥗, 🍳, 🍕)"
                        ],
                        "loggedAtDate": [
                            "type": "string",
                            "description": "Date the meal was eaten in YYYY-MM-DD format. Only include if the user specified a day other than today.",
                            "nullable": true
                        ],
                        "loggedAtTime": [
                            "type": "string",
                            "description": "Time the meal was eaten in HH:mm format (24-hour). Only include if user specified a different time than now.",
                            "nullable": true
                        ],
                        "components": [
                            "type": "array",
                            "nullable": true,
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "string", "nullable": true],
                                    "displayName": ["type": "string"],
                                    "role": [
                                        "type": "string",
                                        "enum": ["protein", "carb", "fat", "vegetable", "fruit", "sauce", "drink", "mixed", "other"],
                                        "nullable": true
                                    ],
                                    "quantity": ["type": "number", "nullable": true],
                                    "unit": ["type": "string", "nullable": true],
                                    "calories": ["type": "integer"],
                                    "proteinGrams": ["type": "number"],
                                    "carbsGrams": ["type": "number"],
                                    "fatGrams": ["type": "number"],
                                    "fiberGrams": ["type": "number", "nullable": true],
                                    "sugarGrams": ["type": "number", "nullable": true],
                                    "confidence": [
                                        "type": "string",
                                        "enum": ["high", "medium", "low"],
                                        "nullable": true
                                    ]
                                ],
                                "required": ["displayName", "calories", "proteinGrams", "carbsGrams", "fatGrams"]
                            ]
                        ]
                    ],
                    "required": ["name", "calories", "proteinGrams", "carbsGrams", "fatGrams", "emoji"]
                ]
            ],
            "required": ["message"]
        ]
    }
}
