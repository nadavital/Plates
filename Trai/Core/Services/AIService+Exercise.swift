//
//  AIService+Exercise.swift
//  Trai
//
//  AI-powered exercise analysis for custom exercise creation
//

import Foundation
import os.log

// MARK: - Exercise Analysis Types

struct ExerciseAnalysis: Codable {
    let category: String       // "strength", "cardio", "flexibility"
    let muscleGroup: String?   // Primary muscle group (nil for cardio/flexibility)
    let secondaryMuscles: [String]?  // Secondary muscles worked
    let description: String    // Brief description of the exercise
    let tips: String?          // Optional form tips
}

/// Result from identifying exercise equipment from a photo
struct ExercisePhotoAnalysis: Codable {
    let equipmentName: String       // Name of the machine/equipment
    let suggestedExercises: [SuggestedExercise]  // Exercises you can do with it
    let description: String         // What this equipment is
    let tips: String?               // Setup or usage tips

    struct SuggestedExercise: Codable, Identifiable {
        var id: String { name }
        let name: String
        let muscleGroup: String
        let howTo: String?          // Brief instruction
    }
}

// MARK: - AIService Exercise Extension

extension AIService {
    /// Analyze an exercise name to determine its category, target muscles, and description
    func analyzeExercise(name: String) async throws -> ExerciseAnalysis {
        log("Analyzing exercise: \(name)", type: .info)
        return try await performAIRequest(for: .exerciseAnalysis) {
            let prompt = """
            Analyze this exercise and provide details about it.

            Exercise name: "\(name)"

            Determine:
            1. Category: Is it primarily "strength", "cardio", or "flexibility"?
            2. Primary muscle group (for strength exercises): chest, back, shoulders, biceps, triceps, legs, core, or fullBody
            3. Secondary muscles worked (if any)
            4. A brief 1-sentence description of the exercise
            5. Optional quick form tip

            If you don't recognize the exercise, make your best educated guess based on the name.
            """

            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "category": [
                        "type": "string",
                        "enum": ["strength", "cardio", "flexibility"]
                    ],
                    "muscleGroup": [
                        "type": "string",
                        "enum": ["chest", "back", "shoulders", "biceps", "triceps", "legs", "core", "fullBody"],
                        "nullable": true
                    ],
                    "secondaryMuscles": [
                        "type": "array",
                        "items": ["type": "string"],
                        "nullable": true
                    ],
                    "description": [
                        "type": "string"
                    ],
                    "tips": [
                        "type": "string",
                        "nullable": true
                    ]
                ],
                "required": ["category", "description"]
            ]

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: schema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .minimal
                )
            )

            logPrompt(prompt)

            let response = try await makeRequest(request: request)
            logResponse(response)

            guard let data = response.data(using: .utf8) else {
                throw AIServiceError.invalidResponse
            }

            let analysis = try JSONDecoder().decode(ExerciseAnalysis.self, from: data)
            log("Exercise analyzed: \(analysis.category), muscle: \(analysis.muscleGroup ?? "none")", type: .info)

            return analysis
        }
    }

    /// Identify gym equipment/machine from a photo and suggest exercises
    /// - Parameters:
    ///   - imageData: JPEG image data of the equipment
    ///   - existingExerciseNames: Names of exercises already in the user's library (for matching)
    func analyzeExercisePhoto(imageData: Data, existingExerciseNames: [String] = []) async throws -> ExercisePhotoAnalysis {
        log("Analyzing exercise equipment photo", type: .info)
        return try await performAIRequest(for: .exercisePhotoAnalysis) {
            let existingExercisesContext: String
            if !existingExerciseNames.isEmpty {
                let exerciseList = existingExerciseNames.joined(separator: ", ")
                existingExercisesContext = """

                IMPORTANT: The user already has these exercises in their library:
                \(exerciseList)

                When suggesting exercises, use the EXACT name from this list if the exercise matches (even if you'd name it slightly differently). Only suggest a new name if none of the existing exercises match.
                """
            } else {
                existingExercisesContext = ""
            }

            let prompt = """
            Look at this image related to gym equipment or an exercise machine.

            The image may show:
            - the full machine
            - part of the machine
            - an instruction placard or diagram
            - a brand/model label
            - close-up text describing how the machine is used

            Identify:
            1. What equipment or machine this is (e.g., "Lat Pulldown Machine", "Cable Crossover", "Leg Press")
            2. What exercises can be done with it (list 2-4 main exercises)
            3. A brief description of what the equipment is for
            4. Any setup tips or key things to know
            \(existingExercisesContext)
            IMPORTANT:
            - Use any visible text, diagrams, labels, or setup instructions in the image to help identify the equipment.
            - Prioritize what is clearly visible in the image over guessing.
            - Do NOT invent hidden attachments, stations, exercise variants, or machine names that are not supported by the visible image.
            - If the image only shows a partial view or descriptive signage, use the visible clues but keep the answer generic if needed instead of forcing a highly specific machine name.
            - Be specific when similar machines exist, but only when the image supports that level of certainty.
            - If brand/model text is clearly visible on the machine, include that in equipmentName (e.g., "Life Fitness Seated Row Machine").
            - If the image is too unclear to confidently identify gym equipment, return:
              equipmentName: "Unclear gym equipment"
              suggestedExercises: []
              description: "The image does not clearly show identifiable gym equipment."
              tips: "Retake the photo with the full machine, placard, or visible labels."
            - If the image is not gym equipment, do not force it into a gym machine category. Use a generic visible label, keep suggestedExercises empty unless they are clearly supported by the object shown, and explain the uncertainty in description or tips.
            """

            let preparedImageData = AIImagePayloadPreparer.prepareJPEGData(from: imageData) ?? imageData
            logImagePayloadSummary(preparedImageData, label: "Exercise photo analysis image")

            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "equipmentName": [
                        "type": "string",
                        "description": "Name of the machine or equipment"
                    ],
                    "suggestedExercises": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"],
                                "muscleGroup": [
                                    "type": "string",
                                    "enum": ["chest", "back", "shoulders", "biceps", "triceps", "legs", "core", "fullBody"]
                                ],
                                "howTo": [
                                    "type": "string",
                                    "nullable": true
                                ]
                            ],
                            "required": ["name", "muscleGroup"]
                        ]
                    ],
                    "description": [
                        "type": "string",
                        "description": "Brief description of what this equipment is for"
                    ],
                    "tips": [
                        "type": "string",
                        "nullable": true
                    ]
                ],
                "required": ["equipmentName", "suggestedExercises", "description"]
            ]

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalMessage(
                        role: .user,
                        parts: [
                            .text(prompt),
                            AIBackendPayloadBuilder.imagePart(preparedImageData)
                        ]
                    )
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: schema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .minimal,
                    imageResolution: .high
                )
            )

            logPrompt(prompt)

            let response = try await makeRequest(request: request)
            logResponse(response)

            guard let data = response.data(using: .utf8) else {
                throw AIServiceError.invalidResponse
            }

            let analysis = try JSONDecoder().decode(ExercisePhotoAnalysis.self, from: data)
            log("Equipment identified: \(analysis.equipmentName) with \(analysis.suggestedExercises.count) exercises", type: .info)

            return analysis
        }
    }
}
