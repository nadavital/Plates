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
            getMuscleRecoveryStatus,
            suggestWorkout,
            startLiveWorkout,
            getWeightHistory,
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
                    ],
                    "fiber_grams": [
                        "type": "number",
                        "description": "New fiber in grams (optional)"
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
                        "description": "Specific date in YYYY-MM-DD format. Only provide if user asks about a specific date. Omit for today's log."
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

    /// Get recent workout history with optional date range
    static var getRecentWorkouts: [String: Any] {
        [
            "name": "get_recent_workouts",
            "description": "Get the user's workout history for a specific date or date range. Defaults to recent workouts if no date specified. Use when the user asks about their workout history, exercise patterns, training frequency, or past workouts like 'what workouts did I do last week'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of workouts to return (default: 10, ignored when date range is specified)"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Specific date in YYYY-MM-DD format (e.g., '2025-01-15'). When provided, returns workouts from this date."
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

    /// Log a workout session
    static var logWorkout: [String: Any] {
        [
            "name": "log_workout",
            "description": "Log a completed workout session for the user. Use when the user mentions finishing a workout or exercise. Ask for details about exercises, sets, reps, and weights if not provided. Always provide a descriptive workout name.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "A descriptive name for the workout (e.g., 'Morning Push Day', 'Leg Day', 'Upper Body Strength', 'Back & Biceps'). Generate a meaningful name based on the exercises."
                    ],
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
                                "name": [
                                    "type": "string",
                                    "description": "Name of the exercise"
                                ],
                                "sets": [
                                    "type": "array",
                                    "items": [
                                        "type": "object",
                                        "properties": [
                                            "reps": ["type": "integer", "description": "Number of reps in this set"],
                                            "weight_kg": ["type": "number", "description": "Weight used in kg (optional)"]
                                        ],
                                        "required": ["reps"]
                                    ],
                                    "description": "Array of sets with reps and optional weight for each"
                                ]
                            ],
                            "required": ["name", "sets"]
                        ],
                        "description": "List of exercises with detailed set information"
                    ]
                ],
                "required": ["name", "type"]
            ]
        ]
    }

    /// Get muscle recovery status
    static var getMuscleRecoveryStatus: [String: Any] {
        [
            "name": "get_muscle_recovery_status",
            "description": "Get the user's muscle group recovery status showing which muscles are ready to train, recovering, or tired. Use when the user asks what to work out, which muscles are ready, or wants workout suggestions based on recovery.",
            "parameters": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ]
    }

    /// Suggest a workout based on recovery and preferences
    static var suggestWorkout: [String: Any] {
        [
            "name": "suggest_workout",
            "description": "Generate a workout suggestion based on the user's muscle recovery status and preferences. Use when the user asks for a workout recommendation, what they should train today, or wants help planning their workout.",
            "parameters": [
                "type": "object",
                "properties": [
                    "workout_type": [
                        "type": "string",
                        "description": "Preferred workout type (optional - will auto-select if not specified)",
                        "enum": ["strength", "cardio", "mixed"]
                    ],
                    "target_muscle_groups": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Specific muscle groups to target (optional - e.g., ['chest', 'triceps'])"
                    ],
                    "duration_minutes": [
                        "type": "integer",
                        "description": "Target workout duration in minutes (default: 45)"
                    ],
                    "equipment": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Available equipment (e.g., ['dumbbells', 'barbell', 'cables'])"
                    ]
                ],
                "required": []
            ]
        ]
    }

    /// Start a live workout session
    static var startLiveWorkout: [String: Any] {
        [
            "name": "start_live_workout",
            "description": "Start a live workout tracking session for the user. Use when the user says they want to start a workout, begin training, or are ready to work out. This creates a new workout that they can track exercises in.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name for the workout (e.g., 'Push Day', 'Leg Day', 'Morning Cardio')"
                    ],
                    "workout_type": [
                        "type": "string",
                        "description": "Type of workout",
                        "enum": ["strength", "cardio", "mixed"]
                    ],
                    "target_muscle_groups": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Target muscle groups (e.g., ['chest', 'triceps', 'shoulders'])"
                    ],
                    "suggested_exercises": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string", "description": "Exercise name"],
                                "sets": ["type": "integer", "description": "Recommended sets"],
                                "reps": ["type": "integer", "description": "Recommended reps"],
                                "weight_kg": ["type": "number", "description": "Recommended weight in kg (optional)"]
                            ]
                        ],
                        "description": "Pre-populated exercises for the workout (optional)"
                    ]
                ],
                "required": ["name", "workout_type"]
            ]
        ]
    }

    // MARK: - Weight Functions

    /// Get weight history with optional date range
    static var getWeightHistory: [String: Any] {
        [
            "name": "get_weight_history",
            "description": "Get the user's weight history and trends. Defaults to recent entries if no date specified. Use when the user asks about their weight, weight progress, weight trends, or how much they've lost/gained.",
            "parameters": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of weight entries to return (default: 10, ignored when date range is specified)"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Specific date in YYYY-MM-DD format (e.g., '2025-01-15'). When provided, returns weight entries from this date."
                    ],
                    "days_back": [
                        "type": "integer",
                        "description": "Number of days back from today (e.g., 1 for yesterday, 30 for last month). Alternative to specifying a date."
                    ],
                    "range_days": [
                        "type": "integer",
                        "description": "Number of days to include in the range (default: 1 for single day, use 30 for monthly trend)"
                    ]
                ],
                "required": []
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
