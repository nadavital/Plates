//
//  GeminiChatPrompts.swift
//  Plates
//
//  Chat-related prompts and schemas for structured output
//

import Foundation

// MARK: - Chat Image Analysis

extension GeminiPromptBuilder {

    /// Build prompt for image-based chat (analyzing photos)
    static func buildImageChatPrompt(
        userMessage: String,
        context: FitnessContext,
        currentDateTime: String
    ) -> String {
        """
        You are Trai, a friendly fitness coach. Never refer to yourself as an AI, Gemini, or assistant. The user is sharing an image with you.

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
        IMPORTANT: You are SUGGESTING a meal to log - the user must confirm before it's saved. So say things like "Here's what I found" or "Want me to log this?" - NOT "I've logged this for you".
        If the user mentions they ate at a specific time, include loggedAtTime in HH:mm 24-hour format.
        Include a relevant emoji for the food (e.g., ☕ for coffee, 🥗 for salad, 🍳 for eggs).

        Keep your message brief (1-2 sentences).
        """
    }

    /// Build prompt for text-based chat (may suggest meals from descriptions)
    static func buildTextChatPrompt(
        userMessage: String,
        context: FitnessContext,
        currentDateTime: String,
        conversationHistory: String,
        pendingSuggestion: SuggestedFoodEntry? = nil
    ) -> String {
        var pendingContext = ""
        if let pending = pendingSuggestion {
            pendingContext = """

            PENDING MEAL SUGGESTION (not yet logged):
            - Name: \(pending.name)
            - Calories: \(pending.calories) kcal
            - Protein: \(Int(pending.proteinGrams))g, Carbs: \(Int(pending.carbsGrams))g, Fat: \(Int(pending.fatGrams))g
            \(pending.servingSize.map { "- Serving: \($0)" } ?? "")

            If the user asks to adjust this (e.g., "add more calories", "make it 600 calories"), update the suggestMealLog with the modified values.
            """
        }

        return """
        You are Trai, a friendly fitness coach. Never refer to yourself as an AI, Gemini, or assistant. Be conversational and supportive.

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
        Include a relevant emoji for the food (e.g., ☕ for coffee, 🥗 for salad, 🍳 for eggs).

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
                        "servingSize": ["type": "string", "nullable": true],
                        "emoji": [
                            "type": "string",
                            "description": "A single relevant emoji for this food (e.g., ☕, 🥗, 🍳, 🍕)"
                        ],
                        "loggedAtTime": [
                            "type": "string",
                            "description": "Time the meal was eaten in HH:mm format (24-hour). Only include if user specified a different time than now.",
                            "nullable": true
                        ]
                    ],
                    "required": ["name", "calories", "proteinGrams", "carbsGrams", "fatGrams", "emoji"]
                ]
            ],
            "required": ["message"]
        ]
    }
}
