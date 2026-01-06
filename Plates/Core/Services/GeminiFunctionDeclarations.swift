//
//  GeminiFunctionDeclarations.swift
//  Plates
//
//  Function declarations (tools) for Gemini function calling API
//

import Foundation

/// Function declarations for Gemini API function calling
enum GeminiFunctionDeclarations {

    // MARK: - All Chat Functions

    /// All function declarations for chat interactions
    static var chatFunctions: [[String: Any]] {
        [
            suggestFoodLog,
            editFoodEntry,
            getTodaysFoodLog,
            getUserPlan,
            updateUserPlan,
            getRecentWorkouts,
            logWorkout,
            saveMemory,
            deleteMemory
        ]
    }

    // MARK: - Food Functions

    /// Suggest a food entry for the user to confirm before logging
    static var suggestFoodLog: [String: Any] {
        [
            "name": "suggest_food_log",
            "description": "Suggest a food entry for the user to log. The user must confirm before it's added to their diary. Use this when the user mentions eating something or shares a food photo. Always provide accurate nutritional estimates.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the food or meal (e.g., 'Chicken Caesar Salad', 'Black Coffee')"
                    ],
                    "calories": [
                        "type": "integer",
                        "description": "Total calories"
                    ],
                    "protein_grams": [
                        "type": "number",
                        "description": "Protein in grams"
                    ],
                    "carbs_grams": [
                        "type": "number",
                        "description": "Carbohydrates in grams"
                    ],
                    "fat_grams": [
                        "type": "number",
                        "description": "Fat in grams"
                    ],
                    "fiber_grams": [
                        "type": "number",
                        "description": "Dietary fiber in grams"
                    ],
                    "serving_size": [
                        "type": "string",
                        "description": "Serving size description (e.g., '1 large bowl', '16 oz')"
                    ],
                    "emoji": [
                        "type": "string",
                        "description": "A single relevant food emoji (e.g., ☕, 🥗, 🍳, 🍕)"
                    ],
                    "logged_at_time": [
                        "type": "string",
                        "description": "Time to log the meal in HH:mm 24-hour format, if the user specified a time (e.g., '14:30' for 2:30 PM)"
                    ]
                ],
                "required": ["name", "calories", "protein_grams", "carbs_grams", "fat_grams", "emoji"]
            ]
        ]
    }

    /// Edit an existing food entry
    static var editFoodEntry: [String: Any] {
        [
            "name": "edit_food_entry",
            "description": "Edit an existing food entry in the user's diary. Use when the user asks to modify a logged meal's details.",
            "parameters": [
                "type": "object",
                "properties": [
                    "entry_id": [
                        "type": "string",
                        "description": "The UUID of the food entry to edit"
                    ],
                    "name": [
                        "type": "string",
                        "description": "New name for the food (optional)"
                    ],
                    "calories": [
                        "type": "integer",
                        "description": "New calorie count (optional)"
                    ],
                    "protein_grams": [
                        "type": "number",
                        "description": "New protein in grams (optional)"
                    ],
                    "carbs_grams": [
                        "type": "number",
                        "description": "New carbs in grams (optional)"
                    ],
                    "fat_grams": [
                        "type": "number",
                        "description": "New fat in grams (optional)"
                    ]
                ],
                "required": ["entry_id"]
            ]
        ]
    }

    /// Get food log with optional date range
    static var getTodaysFoodLog: [String: Any] {
        [
            "name": "get_food_log",
            "description": "Get the user's food log for a specific date or date range. Defaults to today if no date specified. Use when the user asks what they've eaten, their progress, remaining calories/macros, or nutrition status. Also use when they ask about past days like 'what did I eat yesterday' or 'show me last week'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "Specific date in YYYY-MM-DD format (e.g., '2025-01-15'). Defaults to today if not provided."
                    ],
                    "days_back": [
                        "type": "integer",
                        "description": "Number of days back from today (e.g., 1 for yesterday, 7 for last week). Alternative to specifying a date."
                    ],
                    "range_days": [
                        "type": "integer",
                        "description": "Number of days to include in the range (default: 1 for single day, use 7 for a week summary)"
                    ]
                ],
                "required": []
            ]
        ]
    }

    // MARK: - Plan/Goal Functions

    /// Get the user's current nutrition plan and goals
    static var getUserPlan: [String: Any] {
        [
            "name": "get_user_plan",
            "description": "Get the user's current nutrition plan, including their goal, daily calorie/macro targets, and plan rationale. Use when the user asks about their goals, targets, or plan details.",
            "parameters": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ]
    }

    /// Propose updates to the user's plan/goals
    static var updateUserPlan: [String: Any] {
        [
            "name": "update_user_plan",
            "description": "Propose changes to the user's nutrition plan or goals. The user must confirm before changes are applied. Use when the user wants to adjust their calorie/macro targets or change their goal. You must provide at least one value to change, plus a rationale explaining why.",
            "parameters": [
                "type": "object",
                "properties": [
                    "calories": [
                        "type": "integer",
                        "description": "New daily calorie target (e.g., 2000)"
                    ],
                    "protein_grams": [
                        "type": "integer",
                        "description": "New daily protein target in grams (e.g., 150)"
                    ],
                    "carbs_grams": [
                        "type": "integer",
                        "description": "New daily carbs target in grams (e.g., 200)"
                    ],
                    "fat_grams": [
                        "type": "integer",
                        "description": "New daily fat target in grams (e.g., 65)"
                    ],
                    "goal": [
                        "type": "string",
                        "description": "New fitness goal",
                        "enum": ["lose_weight", "lose_fat", "build_muscle", "body_recomposition", "maintain_weight", "athletic_performance", "general_health"]
                    ],
                    "rationale": [
                        "type": "string",
                        "description": "Brief explanation of why these changes are recommended"
                    ]
                ],
                "required": ["rationale"]
            ]
        ]
    }

    // MARK: - Workout Functions

    /// Get recent workout history
    static var getRecentWorkouts: [String: Any] {
        [
            "name": "get_recent_workouts",
            "description": "Get the user's recent workout history. Use when the user asks about their workout history, exercise patterns, or training frequency.",
            "parameters": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of workouts to return (default: 5)"
                    ]
                ],
                "required": []
            ]
        ]
    }

    /// Log a workout session
    static var logWorkout: [String: Any] {
        [
            "name": "log_workout",
            "description": "Log a workout session for the user. Use when the user mentions completing a workout or exercise.",
            "parameters": [
                "type": "object",
                "properties": [
                    "type": [
                        "type": "string",
                        "description": "Type of workout",
                        "enum": ["strength", "cardio", "hiit", "yoga", "running", "cycling", "swimming", "walking", "sports", "other"]
                    ],
                    "duration_minutes": [
                        "type": "integer",
                        "description": "Duration of the workout in minutes"
                    ],
                    "notes": [
                        "type": "string",
                        "description": "Optional notes about the workout"
                    ],
                    "exercises": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"],
                                "sets": ["type": "integer"],
                                "reps": ["type": "integer"],
                                "weight_kg": ["type": "number"]
                            ]
                        ],
                        "description": "List of exercises performed (for strength training)"
                    ]
                ],
                "required": ["type"]
            ]
        ]
    }

    // MARK: - Memory Functions

    /// Save a memory/fact about the user
    static var saveMemory: [String: Any] {
        [
            "name": "save_memory",
            "description": "Save an important fact, preference, or piece of information about the user to remember for future conversations. Use this proactively when you learn something valuable like: food preferences ('doesn't like fish'), dietary restrictions ('allergic to nuts'), habits ('usually skips breakfast'), goals ('training for a marathon'), schedule constraints ('works night shifts'), or feedback ('found portions too large'). This helps you act as a personalized coach who knows the user.",
            "parameters": [
                "type": "object",
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "The fact or preference to remember (e.g., 'Doesn't like eating fish', 'Prefers high-protein breakfasts', 'Has a nut allergy')"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Type of memory",
                        "enum": ["preference", "restriction", "habit", "goal", "context", "feedback"]
                    ],
                    "topic": [
                        "type": "string",
                        "description": "Topic area this relates to",
                        "enum": ["food", "workout", "schedule", "general"]
                    ],
                    "importance": [
                        "type": "integer",
                        "description": "How important this is to remember (1-5, where 5 is critical like allergies)"
                    ]
                ],
                "required": ["content", "category", "topic"]
            ]
        ]
    }

    /// Delete/deactivate a memory
    static var deleteMemory: [String: Any] {
        [
            "name": "delete_memory",
            "description": "Delete or update a memory when the user indicates something is no longer true or has changed. For example, if a user previously said they don't like fish but now says they've started eating it.",
            "parameters": [
                "type": "object",
                "properties": [
                    "memory_content": [
                        "type": "string",
                        "description": "The memory content to find and delete (partial match is okay)"
                    ],
                    "reason": [
                        "type": "string",
                        "description": "Brief reason for deletion (e.g., 'User now eats fish')"
                    ]
                ],
                "required": ["memory_content"]
            ]
        ]
    }
}
