//
//  AIWorkoutPlanPrompts.swift
//  Trai
//
//  Workout plan generation and refinement prompts
//

import Foundation

// MARK: - Workout Plan Generation

extension AIPromptBuilder {

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
        - Preferred Session Duration: \(request.timePerWorkout.map { "\($0) minutes" } ?? "Not fixed - choose what fits best")
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

        if let context = request.conversationContext, !context.isEmpty {
            prompt += "\n- Intake Notes:"
            for entry in context {
                prompt += "\n  - \(entry)"
            }
        }

        let directives = request.generationDirectives
        if !directives.isEmpty {
            prompt += "\n\nGENERATION DIRECTIVES (override generic training type labels):"
            for directive in directives {
                prompt += "\n- \(directive)"
            }
        }

        prompt += """


        INSTRUCTIONS:
        Create a personalized \(request.workoutType.displayName.lowercased()) plan with:
        1. You have full control over the structure. Do NOT force a standard gym split unless it genuinely fits the user.
        2. Custom, activity-first, hybrid, skill-based, and nontraditional weekly structures are all valid.
        3. Respect the user's selected weekly schedule. If Available Days Per Week is a number, return exactly that many workout templates and set daysPerWeek to that same number. Only choose a different session count when Available Days Per Week is Flexible.
        4. Design workout templates with exercises OR activities that match the user's actual preferences, equipment, and constraints.
        5. Build every template from ordered blocks. Block kind describes what the work is: warmup, strength, cardio, conditioning, skill, mobility, recovery, sportPractice, cooldown, or custom. Block role describes how it fits: main, warmup, accessory, finisher, cooldown, or custom.
        6. Include 4-8 exercises inside strength blocks when it is an exercise-based session. For activity-based sessions, use blocks with duration, intensity, target, and detail instead of forcing fake sets/reps.
        7. Specify sets, reps, intervals, pace guidance, duration, intensity, or effort targets appropriate for each block.
        8. Include a modalityProgression that matches the plan. Do not force a lifting progression for cardio, mobility, climbing, sport, or hybrid plans.
        9. Add practical guidelines for warm-up, rest periods, recovery, and any important safety considerations.
        10. Address any specific goals, weak points, injuries, and conversation notes mentioned.
        11. Use nutrition targets, onboarding notes, existing workout goals, and remembered context when they are provided. For example, match volume and conditioning to calorie goals, protein targets, recovery constraints, and the user's stated training history.
        12. If Intake Notes include "Personalization brief (highest priority)", treat that as the main customization input. If it contains labels like "Split direction", "Training outcome", or "Workout details", use them directly: the split direction should determine the weekly structure, the training outcome should drive exercise selection/progression/goals, and workout details should determine priority muscles, included movements, avoided movements, and recovery spacing. Do not merely mention these notes in the rationale.
        13. If the personalization brief says one modality should only support another modality, honor that exactly. For example, if the user asks for cardio only at the end of one strength session each week, create strength-focused templates and add one short cardio block with role finisher or accessory. Do NOT create a dedicated cardio day in that case.
        14. If the personalization brief includes a strength split direction, follow it. Do not return a full-body split when the user asked for upper/lower, push/pull/legs, body-part focus, or a named priority-muscle structure.
        15. If the user selected strength but did not give a split direction, choose the simplest structure that fits the schedule and goal. A 2-3 day full-body plan is valid only when it is genuinely the best fit or the user chose it.
        16. If the user says supportive cardio should happen once, on one day, or on a named day only, include exactly one cardio or conditioning block with role accessory or finisher in the entire plan and place it there. Do not duplicate it on a second day.
        17. Make mixed/support work visible in the template name or focusAreas when it materially changes the day, e.g. "Legs + Conditioning" or focusAreas including "Cardio support".
        18. Do not use "Finisher" as the default label for supportive cardio. Use "finisher" only when the person explicitly asks for work at the end of the workout; otherwise name the block by its actual purpose, such as endurance support, conditioning, intervals, zone 2, or recovery.
        19. Return a planIntent that explicitly summarizes the primary focus, supporting focuses, session allocation, honored user inputs, and anything intentionally avoided.
        20. Write rationale, notes, and planIntent text as Trai speaking directly to the person using the app. Use "you" and "your"; do not refer to them as "the user".
        21. For EVERY workout template, set:
           - sessionType: one of strength, cardio, hiit, climbing, yoga, pilates, flexibility, mobility, mixed, recovery, custom
           - focusAreas: short labels describing the session focus (e.g. ["Push", "Chest"], ["Yoga Flow", "Recovery"], ["Climbing", "Technique"])
           - notes: one short explanation of why this day belongs in your week
           - blocks: ordered training blocks that describe the actual session
           - exercises belong inside the relevant blocks only; do not duplicate block exercises at the template level
        22. Keep the JSON compact. Use short one-sentence notes/detail fields and avoid repeating the same coaching text in multiple places.

        EXERCISE SELECTION RULES:
        - For full gym: Use barbells, dumbbells, cables, and machines
        - For home advanced: Use barbells, dumbbells, and bodyweight
        - For home basic: Use dumbbells, resistance bands, and bodyweight
        - For bodyweight only: Use bodyweight exercises only

        TRAINING TYPE CONSIDERATIONS:
        - Strength: Focus on appropriate strength or hypertrophy work for their goal, not just generic powerlifting templates
        - Cardio: Include cardio according to the user's stated role: dedicated sessions only when cardio is a leading goal; finishers/accessory work when it supports another focus
        - HIIT: Design high-intensity interval circuits only if they fit the user's goal and recovery capacity
        - Flexibility: Include yoga, mobility, or recovery-focused sessions when requested
        - Mixed: Blend the requested modalities in a sustainable week, but do not assume it must look like a classic gym split

        FINAL SELF-CHECK BEFORE RETURNING JSON:
        - Does the plan follow every answer in the personalization brief?
        - Does the session allocation match the user's requested days and modality balance?
        - Are supportive modalities integrated as support rather than promoted to standalone days?
        - Are blocks specific enough that the app can show and start the plan without losing the user's intent?
        If any answer is no, revise the plan before returning it.
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

        CARDIO INTEGRATION:
        The user selected cardio, but the personalization brief and intake notes decide how cardio belongs in the week.
        1. If the user asked for cardio as a finisher, accessory, warmup, or conditioning add-on, include it inside the requested strength/mixed template instead of creating a standalone cardio day.
        2. If the user asked for dedicated endurance, running, cycling, race prep, or cardio as the leading focus, include dedicated cardio templates.
        3. If the user's answer gives a specific frequency or placement, follow that placement exactly.
        4. For mixed plans, balance strength and cardio according to the user's stated priority, not by automatically splitting the week into separate modality days.
        5. If the user asks for one cardio support block or says "only" for a day, return exactly one cardio block with role finisher or accessory in the whole plan.
        Preferred cardio activities: \(cardioInfo)
        Do not ignore cardio, but do not turn supportive cardio into a full cardio day.
        """
        }

        prompt += """

        Be specific to this person's profile. Create a plan they can actually follow.
        """

        return prompt
    }

    static var workoutPlanSchema: [String: Any] {
        let exerciseSchema: [String: Any] = [
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

        let blockSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "kind": [
                    "type": "string",
                    "enum": ["warmup", "strength", "cardio", "conditioning", "skill", "mobility", "recovery", "sportPractice", "cooldown", "custom"]
                ],
                "role": [
                    "type": "string",
                    "enum": ["main", "warmup", "accessory", "finisher", "cooldown", "custom"]
                ],
                "title": ["type": "string"],
                "detail": ["type": "string"],
                "exercises": [
                    "type": "array",
                    "items": exerciseSchema
                ],
                "durationMinutes": ["type": "integer", "nullable": true],
                "intensity": ["type": "string", "nullable": true],
                "target": ["type": "string", "nullable": true],
                "order": ["type": "integer"],
                "notes": ["type": "string", "nullable": true]
            ],
            "required": ["id", "kind", "role", "title", "detail", "exercises", "order"]
        ]

        return [
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
                            "sessionType": [
                                "type": "string",
                                "enum": ["strength", "cardio", "hiit", "climbing", "yoga", "pilates", "flexibility", "mobility", "mixed", "recovery", "custom"]
                            ],
                            "focusAreas": [
                                "type": "array",
                                "items": ["type": "string"]
                            ],
                            "targetMuscleGroups": [
                                "type": "array",
                                "items": ["type": "string"]
                            ],
                            "blocks": [
                                "type": "array",
                                "items": blockSchema
                            ],
                            "estimatedDurationMinutes": ["type": "integer"],
                            "order": ["type": "integer"],
                            "notes": ["type": "string", "nullable": true]
                        ],
                        "required": ["id", "name", "sessionType", "focusAreas", "targetMuscleGroups", "blocks", "estimatedDurationMinutes", "order", "notes"]
                    ]
                ],
                "planIntent": [
                    "type": "object",
                    "properties": [
                        "primaryFocus": ["type": "string"],
                        "supportingFocuses": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "sessionAllocation": ["type": "string"],
                        "honoredInputs": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "avoided": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "summary": ["type": "string"]
                    ],
                    "required": ["primaryFocus", "supportingFocuses", "sessionAllocation", "honoredInputs", "avoided", "summary"]
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
                "modalityProgression": [
                    "type": "object",
                    "properties": [
                        "focus": [
                            "type": "string",
                            "enum": ["strength", "volume", "endurance", "skill", "mobility", "consistency", "mixed"]
                        ],
                        "weeklyProgression": ["type": "string"],
                        "targets": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "string"],
                                    "label": ["type": "string"],
                                    "metric": ["type": "string"],
                                    "direction": ["type": "string"]
                                ],
                                "required": ["id", "label", "metric", "direction"]
                            ]
                        ]
                    ],
                    "required": ["focus", "weeklyProgression", "targets"]
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ]
            ],
            "required": ["splitType", "daysPerWeek", "templates", "planIntent", "rationale", "guidelines", "progressionStrategy", "modalityProgression"]
        ]
    }

    static var workoutGoalSuggestionSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "rationale": ["type": "string"],
                "goalKindRaw": [
                    "type": "string",
                    "enum": WorkoutGoal.GoalKind.allCases.map(\.rawValue)
                ],
                "linkedWorkoutTypeRaw": [
                    "type": "string",
                    "enum": WorkoutMode.allCases.map(\.rawValue),
                    "nullable": true
                ],
                "linkedActivityName": [
                    "type": "string",
                    "nullable": true
                ],
                "linkedActivityKindRaw": [
                    "type": "string",
                    "enum": ["warmup", "strength", "cardio", "conditioning", "skill", "mobility", "recovery", "sportPractice", "cooldown", "custom"],
                    "nullable": true
                ],
                "linkedActivityRoleRaw": [
                    "type": "string",
                    "enum": ["main", "warmup", "accessory", "finisher", "cooldown", "custom"],
                    "nullable": true
                ],
                "targetValue": [
                    "type": "number",
                    "nullable": true
                ],
                "targetUnit": [
                    "type": "string",
                    "nullable": true
                ],
                "periodUnitRaw": [
                    "type": "string",
                    "enum": WorkoutGoal.PeriodUnit.allCases.map(\.rawValue),
                    "nullable": true
                ],
                "periodCount": [
                    "type": "integer",
                    "nullable": true
                ],
                "successCriteria": [
                    "type": "string"
                ],
                "notes": [
                    "type": "string",
                    "nullable": true
                ],
                "targetDateISO8601": [
                    "type": "string",
                    "nullable": true
                ],
                "checkInCadenceDays": [
                    "type": "integer",
                    "nullable": true
                ]
            ],
            "required": ["title", "rationale", "goalKindRaw", "targetValue", "targetUnit", "periodUnitRaw", "periodCount", "successCriteria"]
        ]
    }

    static var workoutPlanWithGoalSuggestionsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "plan": workoutPlanSchema,
                "goalSuggestions": [
                    "type": "array",
                    "maxItems": 2,
                    "items": workoutGoalSuggestionSchema
                ]
            ],
            "required": ["plan", "goalSuggestions"]
        ]
    }
}

// MARK: - Workout Plan Refinement

extension AIPromptBuilder {

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
        1. "message" - For questions, clarifications, or one short follow-up when absolutely needed.
        2. "proposePlan" - When you want to SUGGEST changes to the plan. Prefer this when the user direction is already clear.
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
        if let context = request.conversationContext, !context.isEmpty {
            prompt += "\n- Relevant context:"
            for entry in context {
                prompt += "\n  - \(entry)"
            }
        }
        if let cardio = request.cardioTypes, !cardio.isEmpty {
            prompt += "\n- Cardio Preferences: \(cardio.map { $0.displayName }.joined(separator: ", "))"
        }
        if let duration = request.timePerWorkout {
            prompt += "\n- Current Plan Session Duration: \(duration) minutes"
        }

        prompt += """

        CURRENT PLAN:
        - Split: \(currentPlan.splitType.displayName)
        - Days/Week: \(currentPlan.daysPerWeek)
        - Workouts: \(currentPlan.templates.map { $0.name }.joined(separator: ", "))
        \(currentPlan.planIntent.map { "- Intent: \($0.summary)\n- Session allocation: \($0.sessionAllocation)" } ?? "")
        - Session details:
        \(currentPlan.templates.map { template in
            let blocks = template.displayBlocks.map { block in
                "\(block.kind.displayName): \(block.title)\(block.durationMinutes.map { " \($0)m" } ?? "")"
            }.joined(separator: " | ")
            return "  - \(template.name): \(blocks)"
        }.joined(separator: "\n"))

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
        - Use "proposePlan" whenever they clearly want a change, even if they did not specify every detail
        - Ask AT MOST one short follow-up only when missing information would materially change the plan
        - If they ask to change exercises or schedule directionally, make a reasonable proposal instead of starting a long clarification chain
        - Preserve and update planIntent, modalityProgression, and template blocks whenever a plan changes
        - Use blocks for modality-specific work: cardio, mobility flows, climbing/sport practice, conditioning, and recovery should not be flattened into fake strength exercises. Use role to describe whether a block is main work, a warmup, an accessory, a finisher, or a cooldown.
        - If the user says a support modality should happen once, only once, or on a named day only, include exactly one matching support block and place it on that day. Do not duplicate it elsewhere.
        - Make support work visible in the changed template name or focusAreas when it materially changes the day, so the plan card can show it without requiring a details sheet.
        - Keep the selected coach tone consistent with the rest of the app
        """

        return prompt
    }

    static var workoutPlanRefinementSchema: [String: Any] {
        let exerciseSchema: [String: Any] = [
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

        let blockSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "kind": [
                    "type": "string",
                    "enum": ["warmup", "strength", "cardio", "conditioning", "skill", "mobility", "recovery", "sportPractice", "cooldown", "custom"]
                ],
                "role": [
                    "type": "string",
                    "enum": ["main", "warmup", "accessory", "finisher", "cooldown", "custom"]
                ],
                "title": ["type": "string"],
                "detail": ["type": "string"],
                "exercises": [
                    "type": "array",
                    "items": exerciseSchema
                ],
                "durationMinutes": ["type": "integer", "nullable": true],
                "intensity": ["type": "string", "nullable": true],
                "target": ["type": "string", "nullable": true],
                "order": ["type": "integer"],
                "notes": ["type": "string", "nullable": true]
            ],
            "required": ["id", "kind", "role", "title", "detail", "exercises", "order"]
        ]

        let templateSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "sessionType": [
                    "type": "string",
                    "enum": ["strength", "cardio", "hiit", "climbing", "yoga", "pilates", "flexibility", "mobility", "mixed", "recovery", "custom"]
                ],
                "focusAreas": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "targetMuscleGroups": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "blocks": [
                    "type": "array",
                    "items": blockSchema
                ],
                "estimatedDurationMinutes": ["type": "integer"],
                "order": ["type": "integer"],
                "notes": ["type": "string", "nullable": true]
            ],
            "required": ["id", "name", "sessionType", "focusAreas", "targetMuscleGroups", "blocks", "estimatedDurationMinutes", "order", "notes"]
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
                "planIntent": [
                    "type": "object",
                    "properties": [
                        "primaryFocus": ["type": "string"],
                        "supportingFocuses": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "sessionAllocation": ["type": "string"],
                        "honoredInputs": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "avoided": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "summary": ["type": "string"]
                    ],
                    "required": ["primaryFocus", "supportingFocuses", "sessionAllocation", "honoredInputs", "avoided", "summary"]
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
                "modalityProgression": [
                    "type": "object",
                    "properties": [
                        "focus": [
                            "type": "string",
                            "enum": ["strength", "volume", "endurance", "skill", "mobility", "consistency", "mixed"]
                        ],
                        "weeklyProgression": ["type": "string"],
                        "targets": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "string"],
                                    "label": ["type": "string"],
                                    "metric": ["type": "string"],
                                    "direction": ["type": "string"]
                                ],
                                "required": ["id", "label", "metric", "direction"]
                            ]
                        ]
                    ],
                    "required": ["focus", "weeklyProgression", "targets"]
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "nullable": true
                ]
            ],
            "required": ["splitType", "daysPerWeek", "templates", "planIntent", "rationale", "guidelines", "progressionStrategy", "modalityProgression"]
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
