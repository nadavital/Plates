//
//  GeminiWorkoutPlanPrompts.swift
//  Trai
//
//  Workout plan generation and refinement prompts
//

import Foundation

// MARK: - Workout Plan Generation

extension GeminiPromptBuilder {

    static func buildWorkoutPlanGenerationPrompt(
        request: WorkoutPlanGenerationRequest,
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a certified personal trainer creating a personalized workout plan. Never mention being an AI or assistant.
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        USER PROFILE:
        - Name: \(request.name)
        - Age: \(request.age) years old
        - Gender: \(request.gender.displayName)
        - Primary Goal: \(request.goal.displayName) - \(request.goal.description)
        - Activity Level: \(request.activityLevel.displayName)

        WORKOUT PREFERENCES:
        - Training Type: \(request.workoutType.displayName) - \(request.workoutType.description)\(request.customWorkoutType.map { " (Custom: \($0))" } ?? "")
        """

        // Show all selected workout types if multiple were chosen
        if let selected = request.selectedWorkoutTypes, selected.count > 1 {
            let typeNames = selected.map { $0.displayName }.joined(separator: ", ")
            prompt += "\n- Selected Training Types: \(typeNames)"
        }

        prompt += """

        - Available Days Per Week: \(request.availableDays.map { "\($0)" } ?? "Flexible")
        - Time Per Session: \(request.timePerWorkout) minutes
        - Equipment Access: \(request.equipmentAccess?.displayName ?? "Not specified")\(request.customEquipment.map { " (Custom: \($0))" } ?? "")
        - Experience Level: \(request.experienceLevel?.displayName ?? "Not specified")\(request.customExperience.map { " (Custom: \($0))" } ?? "")
        """

        // Preferred split
        if let split = request.preferredSplit {
            if split == .letTraiDecide {
                prompt += "\n- Preferred Split: Let Trai decide the best split"
            } else {
                prompt += "\n- Preferred Split: \(split.displayName) - \(split.description)"
            }
        }

        // Cardio types
        if let cardio = request.cardioTypes, !cardio.isEmpty {
            let cardioNames = cardio.map { $0.displayName }.joined(separator: ", ")
            prompt += "\n- Cardio Preferences: \(cardioNames)"
        }

        // Specific goals
        if let goals = request.specificGoals, !goals.isEmpty {
            prompt += "\n- Specific Goals: \(goals.joined(separator: ", "))"
        }

        // Weak points
        if let weak = request.weakPoints, !weak.isEmpty {
            prompt += "\n- Areas to Focus On: \(weak.joined(separator: ", "))"
        }

        // Injuries
        if let injuries = request.injuries, !injuries.isEmpty {
            prompt += "\n- Injuries/Limitations: \(injuries)"
        }

        // Preferences
        if let prefs = request.preferences, !prefs.isEmpty {
            prompt += "\n- Additional Preferences: \(prefs)"
        }

        prompt += """


        RECOMMENDED SPLIT: \(request.recommendedSplit.displayName)
        (Based on \(request.availableDays.map { "\($0)" } ?? "flexible") days/week, \(request.workoutType.displayName), and \(request.experienceLevel?.rawValue ?? "intermediate") experience)

        INSTRUCTIONS:
        Create a personalized \(request.workoutType.displayName.lowercased()) plan with:
        1. Choose an appropriate split type for their schedule, training type, and experience
        2. Design workout templates with specific exercises matching their training type
        3. Include 4-8 exercises per workout template
        4. Specify sets and rep ranges appropriate for their goal and training type
        5. Include a progression strategy appropriate for their experience level
        6. Add practical guidelines for warm-up, rest periods, and recovery
        7. Address any specific goals, weak points, or injuries mentioned

        EXERCISE SELECTION RULES:
        - For full gym: Use barbells, dumbbells, cables, and machines
        - For home advanced: Use barbells, dumbbells, and bodyweight
        - For home basic: Use dumbbells, resistance bands, and bodyweight
        - For bodyweight only: Use bodyweight exercises only

        TRAINING TYPE CONSIDERATIONS:
        - Strength: Focus on compound lifts with lower reps (3-6)
        - Cardio: Include running, cycling, or other endurance work as dedicated sessions
        - HIIT: Design high-intensity interval circuits
        - Flexibility: Include yoga poses, stretches, mobility work
        - Mixed: MUST include BOTH strength training AND cardio sessions in the same plan
        """

        // Add specific cardio instruction when user selected cardio
        if request.includesCardio {
            let cardioInfo: String
            if let types = request.cardioTypes, !types.isEmpty {
                cardioInfo = types.map { $0.displayName }.joined(separator: ", ")
            } else {
                cardioInfo = "running, cycling, or their preferred cardio"
            }
            prompt += """

        CRITICAL - CARDIO IS REQUIRED:
        The user explicitly wants cardio in their plan. You MUST:
        1. Include at least 1-2 DEDICATED cardio workout templates (not just "add cardio after lifting")
        2. Name these templates clearly (e.g., "Cardio Day", "HIIT Session", "Running Day")
        3. Include cardio-specific exercises like: Running, Cycling, Rowing, Jump Rope, Burpees, Mountain Climbers
        4. For mixed plans, balance strength days with cardio days
        Preferred cardio activities: \(cardioInfo)
        DO NOT create a plan with only strength training - cardio sessions are REQUIRED.
        """
        }

        prompt += """

        Be specific to this person's profile. Create a plan they can actually follow.
        """

        return prompt
    }

    static var workoutPlanSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "splitType": [
                    "type": "string",
                    "enum": ["pushPullLegs", "upperLower", "fullBody", "bodyPartSplit", "custom"]
                ],
                "daysPerWeek": ["type": "integer"],
                "templates": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "name": ["type": "string"],
                            "targetMuscleGroups": [
                                "type": "array",
                                "items": ["type": "string"]
                            ],
                            "exercises": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "id": ["type": "string"],
                                        "exerciseName": ["type": "string"],
                                        "muscleGroup": ["type": "string"],
                                        "defaultSets": ["type": "integer"],
                                        "defaultReps": ["type": "integer"],
                                        "repRange": ["type": "string", "nullable": true],
                                        "restSeconds": ["type": "integer", "nullable": true],
                                        "notes": ["type": "string", "nullable": true],
                                        "order": ["type": "integer"]
                                    ],
                                    "required": ["id", "exerciseName", "muscleGroup", "defaultSets", "defaultReps", "order"]
                                ]
                            ],
                            "estimatedDurationMinutes": ["type": "integer"],
                            "order": ["type": "integer"],
                            "notes": ["type": "string", "nullable": true]
                        ],
                        "required": ["id", "name", "targetMuscleGroups", "exercises", "estimatedDurationMinutes", "order"]
                    ]
                ],
                "rationale": ["type": "string"],
                "guidelines": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "progressionStrategy": [
                    "type": "object",
                    "properties": [
                        "type": [
                            "type": "string",
                            "enum": ["linearProgression", "doubleProgression", "periodized"]
                        ],
                        "weightIncrementKg": ["type": "number"],
                        "repsTrigger": ["type": "integer", "nullable": true],
                        "description": ["type": "string"]
                    ],
                    "required": ["type", "weightIncrementKg", "description"]
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ]
            ],
            "required": ["splitType", "daysPerWeek", "templates", "rationale", "guidelines", "progressionStrategy"]
        ]
    }
}

// MARK: - Workout Plan Refinement

extension GeminiPromptBuilder {

    static func buildWorkoutPlanRefinementPrompt(
        currentPlan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest,
        userMessage: String,
        conversationHistory: [WorkoutPlanChatMessage],
        tone: TraiCoachTone = .sharedPreference
    ) -> String {
        var prompt = """
        You are Trai, a friendly personal trainer chatting with the user about their workout plan. Never refer to yourself as an AI or assistant. This is a casual chat, so keep responses SHORT and conversational (1-3 sentences max).
        Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)

        RESPONSE TYPES - Choose ONE:
        1. "message" - For questions, clarifications, or asking follow-ups. Use this MOST of the time.
        2. "proposePlan" - When you want to SUGGEST changes to the plan. The user will see a preview and can accept/reject.
        3. "planUpdate" - ONLY use when you are 100% certain this matches what the user wants.

        CURRENT USER PROFILE:
        - Name: \(request.name)
        - Age: \(request.age) years old
        - Goal: \(request.goal.displayName)
        - Experience: \(request.experienceLevel?.displayName ?? "Not specified")
        - Available Days: \(request.availableDays.map { "\($0)" } ?? "Flexible")/week
        - Equipment: \(request.equipmentAccess?.displayName ?? "Not specified")
        - Training Type: \(request.workoutType.displayName)\(request.selectedWorkoutTypes.map { " (Selected: \($0.map { $0.displayName }.joined(separator: ", ")))" } ?? "")
        """

        // Add conversation context from onboarding
        if let goals = request.specificGoals, !goals.isEmpty {
            prompt += "\n- Their Goals: \(goals.joined(separator: ", "))"
        }
        if let weak = request.weakPoints, !weak.isEmpty {
            prompt += "\n- Areas to Focus: \(weak.joined(separator: ", "))"
        }
        if let injuries = request.injuries, !injuries.isEmpty {
            prompt += "\n- Injuries/Limitations: \(injuries)"
        }
        if let prefs = request.preferences, !prefs.isEmpty {
            prompt += "\n- Preferences: \(prefs)"
        }
        if let cardio = request.cardioTypes, !cardio.isEmpty {
            prompt += "\n- Cardio Preferences: \(cardio.map { $0.displayName }.joined(separator: ", "))"
        }

        prompt += """

        CURRENT PLAN:
        - Split: \(currentPlan.splitType.displayName)
        - Days/Week: \(currentPlan.daysPerWeek)
        - Workouts: \(currentPlan.templates.map { $0.name }.joined(separator: ", "))

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
        - IMPORTANT: If they ask a QUESTION about the plan (e.g., "why did you pick this split?", "what muscles does this work?"), just ANSWER the question using "message" type - don't propose changes!
        - Only use "proposePlan" when they EXPLICITLY ask for changes (e.g., "add more leg exercises", "I want 4 days instead")
        - Ask follow-up questions to understand what they want before making changes
        - If they ask to change exercises, ask which ones or for what muscle group
        - If they want more/fewer days, ask about their schedule
        - Keep the selected coach tone consistent with the rest of the app
        """

        return prompt
    }

    static var workoutPlanRefinementSchema: [String: Any] {
        let templateSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "targetMuscleGroups": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "exercises": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "exerciseName": ["type": "string"],
                            "muscleGroup": ["type": "string"],
                            "defaultSets": ["type": "integer"],
                            "defaultReps": ["type": "integer"],
                            "repRange": ["type": "string", "nullable": true],
                            "restSeconds": ["type": "integer", "nullable": true],
                            "notes": ["type": "string", "nullable": true],
                            "order": ["type": "integer"]
                        ],
                        "required": ["id", "exerciseName", "muscleGroup", "defaultSets", "defaultReps", "order"]
                    ]
                ],
                "estimatedDurationMinutes": ["type": "integer"],
                "order": ["type": "integer"],
                "notes": ["type": "string", "nullable": true]
            ],
            "required": ["id", "name", "targetMuscleGroups", "exercises", "estimatedDurationMinutes", "order"]
        ]

        let planSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "splitType": [
                    "type": "string",
                    "enum": ["pushPullLegs", "upperLower", "fullBody", "bodyPartSplit", "custom"]
                ],
                "daysPerWeek": ["type": "integer"],
                "templates": [
                    "type": "array",
                    "items": templateSchema
                ],
                "rationale": ["type": "string"],
                "guidelines": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "progressionStrategy": [
                    "type": "object",
                    "properties": [
                        "type": [
                            "type": "string",
                            "enum": ["linearProgression", "doubleProgression", "periodized"]
                        ],
                        "weightIncrementKg": ["type": "number"],
                        "repsTrigger": ["type": "integer", "nullable": true],
                        "description": ["type": "string"]
                    ],
                    "required": ["type", "weightIncrementKg", "description"]
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ]
            ],
            "required": ["splitType", "daysPerWeek", "templates", "rationale", "guidelines", "progressionStrategy"]
        ]

        return [
            "type": "object",
            "properties": [
                "responseType": [
                    "type": "string",
                    "enum": ["message", "proposePlan", "planUpdate"]
                ],
                "message": ["type": "string"],
                "proposedPlan": planSchema,
                "updatedPlan": planSchema
            ],
            "required": ["responseType", "message"]
        ]
    }
}
