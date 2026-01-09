//
//  GeminiWorkoutPlanPrompts.swift
//  Plates
//
//  Workout plan generation and refinement prompts
//

import Foundation

// MARK: - Workout Plan Generation

extension GeminiPromptBuilder {

    static func buildWorkoutPlanGenerationPrompt(request: WorkoutPlanGenerationRequest) -> String {
        var prompt = """
        You are Trai, a certified personal trainer creating a personalized workout plan. Never mention being an AI or assistant.

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
        - Cardio: Include running, cycling, or other endurance work
        - HIIT: Design high-intensity interval circuits
        - Flexibility: Include yoga poses, stretches, mobility work
        - Mixed: Balance strength, cardio, and mobility
        """

        // Add specific cardio instruction when user selected cardio
        if request.includesCardio {
            let cardioInfo: String
            if let types = request.cardioTypes, !types.isEmpty {
                cardioInfo = types.map { $0.displayName }.joined(separator: ", ")
            } else {
                cardioInfo = "their preference"
            }
            prompt += """

        IMPORTANT - CARDIO REQUIREMENT:
        The user wants cardio included in their plan. You MUST include at least one dedicated cardio session (or cardio component) in the weekly plan. Consider \(cardioInfo) as the preferred cardio activities.
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
        conversationHistory: [WorkoutPlanChatMessage]
    ) -> String {
        var prompt = """
        You are Trai, a friendly personal trainer chatting with the user about their workout plan. Never refer to yourself as an AI or assistant. This is a casual chat, so keep responses SHORT and conversational (1-3 sentences max).

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
        - Ask follow-up questions to understand what they want
        - If they ask to change exercises, ask which ones or for what muscle group
        - If they want more/fewer days, ask about their schedule
        - Only use "proposePlan" when you have enough info to make a good suggestion
        - Be friendly and encouraging, like a helpful coach texting back and forth
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
