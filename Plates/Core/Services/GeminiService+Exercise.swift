//
//  GeminiService+Exercise.swift
//  Plates
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

// MARK: - GeminiService Exercise Extension

extension GeminiService {
    /// Analyze an exercise name to determine its category, target muscles, and description
    func analyzeExercise(name: String) async throws -> ExerciseAnalysis {
        log("Analyzing exercise: \(name)", type: .info)

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

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .minimal,
                maxTokens: 512,
                jsonSchema: schema
            )
        ]

        logPrompt(prompt)

        let response = try await makeRequest(body: body)
        logResponse(response)

        // Parse JSON response
        guard let data = response.data(using: .utf8) else {
            throw GeminiError.invalidResponse
        }

        let analysis = try JSONDecoder().decode(ExerciseAnalysis.self, from: data)
        log("Exercise analyzed: \(analysis.category), muscle: \(analysis.muscleGroup ?? "none")", type: .info)

        return analysis
    }

    /// Identify gym equipment/machine from a photo and suggest exercises
    func analyzeExercisePhoto(imageData: Data) async throws -> ExercisePhotoAnalysis {
        log("Analyzing exercise equipment photo", type: .info)

        let prompt = """
        Look at this image of gym equipment or exercise machine.

        Identify:
        1. What equipment or machine this is (e.g., "Lat Pulldown Machine", "Cable Crossover", "Leg Press")
        2. What exercises can be done with it (list 2-4 main exercises)
        3. A brief description of what the equipment is for
        4. Any setup tips or key things to know

        If this isn't gym equipment, still try to identify what it is and suggest any exercises that could be done with it.
        """

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

        let base64Image = imageData.base64EncodedString()
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                        [
                            "inlineData": [
                                "mimeType": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .minimal,
                maxTokens: 1024,
                jsonSchema: schema
            )
        ]

        logPrompt(prompt)

        let response = try await makeRequest(body: body)
        logResponse(response)

        // Parse JSON response
        guard let data = response.data(using: .utf8) else {
            throw GeminiError.invalidResponse
        }

        let analysis = try JSONDecoder().decode(ExercisePhotoAnalysis.self, from: data)
        log("Equipment identified: \(analysis.equipmentName) with \(analysis.suggestedExercises.count) exercises", type: .info)

        return analysis
    }
}
