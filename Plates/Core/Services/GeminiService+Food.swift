//
//  GeminiService+Food.swift
//  Plates
//
//  Food analysis and workout suggestion methods
//

import Foundation
import os

extension GeminiService {

    // MARK: - Food Analysis

    /// Analyze food from an image and/or text description
    func analyzeFoodImage(_ imageData: Data?, description: String?) async throws -> FoodAnalysis {
        guard imageData != nil || description != nil else {
            throw GeminiError.invalidInput("Please provide an image or description of the food")
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var parts: [[String: Any]] = []

        let prompt = GeminiPromptBuilder.buildFoodAnalysisPrompt(description: description)
        parts.append(["text": prompt])

        if let imageData {
            let base64Image = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        var config = buildGenerationConfig(
            thinkingLevel: .medium,
            maxTokens: 2048,
            jsonSchema: GeminiPromptBuilder.foodAnalysisSchema
        )
        config["mediaResolution"] = "MEDIA_RESOLUTION_HIGH"

        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": config
        ]

        let responseText = try await makeRequest(body: requestBody)
        return try parseFoodAnalysis(from: responseText)
    }

    /// Analyze food image in chat context - returns message and optionally logs meal
    func analyzeFoodImageWithChat(
        _ imageData: Data?,
        userMessage: String,
        context: FitnessContext
    ) async throws -> ChatFoodAnalysisResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var parts: [[String: Any]] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        let currentDateTime = dateFormatter.string(from: Date())

        let prompt = GeminiPromptBuilder.buildImageChatPrompt(
            userMessage: userMessage,
            context: context,
            currentDateTime: currentDateTime
        )

        parts.append(["text": prompt])

        if let imageData {
            let base64Image = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        var config = buildGenerationConfig(
            thinkingLevel: .medium,
            jsonSchema: GeminiPromptBuilder.chatImageAnalysisSchema
        )
        config["mediaResolution"] = "MEDIA_RESOLUTION_HIGH"

        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": config
        ]

        let responseText = try await makeRequest(body: requestBody)
        return try parseChatFoodAnalysis(from: responseText)
    }

    // MARK: - Food Refinement

    /// Refine a food analysis based on user correction
    func refineFoodAnalysis(
        correction: String,
        currentSuggestion: SuggestedFoodEntry,
        imageData: Data?
    ) async throws -> SuggestedFoodEntry {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var parts: [[String: Any]] = []

        let fiberStr = currentSuggestion.fiberGrams.map { "- Fiber: \(Int($0))g" } ?? ""
        let prompt = """
        The user is correcting a food analysis. Here's the current estimate:
        - Name: \(currentSuggestion.name)
        - Calories: \(currentSuggestion.calories) kcal
        - Protein: \(Int(currentSuggestion.proteinGrams))g
        - Carbs: \(Int(currentSuggestion.carbsGrams))g
        - Fat: \(Int(currentSuggestion.fatGrams))g
        \(fiberStr)
        \(currentSuggestion.servingSize.map { "- Serving: \($0)" } ?? "")

        User's correction: "\(correction)"

        Please provide an UPDATED food analysis based on their correction. If they say it's a different food, update all values accordingly. If they mention adjusting a specific value, update just that. Keep unmentioned values reasonable for the (potentially new) food. Include fiber if relevant.
        """

        parts.append(["text": prompt])

        if let imageData {
            let base64Image = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Updated name of the food"],
                "calories": ["type": "integer", "description": "Updated calories"],
                "proteinGrams": ["type": "number", "description": "Updated protein in grams"],
                "carbsGrams": ["type": "number", "description": "Updated carbs in grams"],
                "fatGrams": ["type": "number", "description": "Updated fat in grams"],
                "fiberGrams": ["type": "number", "description": "Updated fiber in grams", "nullable": true],
                "servingSize": ["type": "string", "description": "Updated serving size", "nullable": true],
                "emoji": ["type": "string", "description": "Updated emoji for this food"]
            ],
            "required": ["name", "calories", "proteinGrams", "carbsGrams", "fatGrams", "emoji"]
        ]

        var config = buildGenerationConfig(
            thinkingLevel: .low,
            maxTokens: 1024,
            jsonSchema: schema
        )
        if imageData != nil {
            config["mediaResolution"] = "MEDIA_RESOLUTION_HIGH"
        }

        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": config
        ]

        let responseText = try await makeRequest(body: requestBody)
        return try parseRefinedFoodAnalysis(from: responseText)
    }

    private func parseRefinedFoodAnalysis(from text: String) throws -> SuggestedFoodEntry {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = String(cleanText.dropFirst(7))
        } else if cleanText.hasPrefix("```") {
            cleanText = String(cleanText.dropFirst(3))
        }
        if cleanText.hasSuffix("```") {
            cleanText = String(cleanText.dropLast(3))
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonPattern = #"\{[\s\S]*\}"#
        if let range = cleanText.range(of: jsonPattern, options: .regularExpression) {
            cleanText = String(cleanText[range])
        }

        guard let data = cleanText.data(using: .utf8) else {
            throw GeminiError.parsingError
        }

        struct RefinedFood: Codable {
            let name: String
            let calories: Int
            let proteinGrams: Double
            let carbsGrams: Double
            let fatGrams: Double
            let fiberGrams: Double?
            let servingSize: String?
            let emoji: String?
        }

        let decoded = try JSONDecoder().decode(RefinedFood.self, from: data)
        return SuggestedFoodEntry(
            name: decoded.name,
            calories: decoded.calories,
            proteinGrams: decoded.proteinGrams,
            carbsGrams: decoded.carbsGrams,
            fatGrams: decoded.fatGrams,
            fiberGrams: decoded.fiberGrams,
            servingSize: decoded.servingSize,
            emoji: decoded.emoji
        )
    }

    func parseChatFoodAnalysis(from text: String) throws -> ChatFoodAnalysisResult {
        log("📝 Raw chat response (\(text.count) chars): \(text.prefix(300))...", type: .info)

        guard let data = text.data(using: .utf8) else {
            log("⚠️ Failed to convert response to data", type: .error)
            return ChatFoodAnalysisResult(message: text, suggestedFoodEntry: nil)
        }

        struct ChatResponse: Codable {
            let message: String
            let suggestMealLog: SuggestMealLogData?

            struct SuggestMealLogData: Codable {
                let name: String
                let calories: Int
                let proteinGrams: Double
                let carbsGrams: Double
                let fatGrams: Double
                let fiberGrams: Double?
                let servingSize: String?
                let emoji: String?
                let loggedAtTime: String?
            }
        }

        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            log("✅ Successfully parsed chat response", type: .info)

            var foodEntry: SuggestedFoodEntry?
            if let meal = decoded.suggestMealLog {
                foodEntry = SuggestedFoodEntry(
                    name: meal.name,
                    calories: meal.calories,
                    proteinGrams: meal.proteinGrams,
                    carbsGrams: meal.carbsGrams,
                    fatGrams: meal.fatGrams,
                    fiberGrams: meal.fiberGrams,
                    servingSize: meal.servingSize,
                    emoji: meal.emoji,
                    loggedAtTime: meal.loggedAtTime
                )
                let emoji = meal.emoji ?? "🍽️"
                var logMessage = "\(emoji) AI suggests logging: \(meal.name) - \(meal.calories) kcal"
                if let time = meal.loggedAtTime {
                    logMessage += " at \(time)"
                }
                log(logMessage, type: .info)
            } else {
                log("ℹ️ No meal suggestion in response", type: .info)
            }

            return ChatFoodAnalysisResult(message: decoded.message, suggestedFoodEntry: foodEntry)
        } catch {
            log("❌ JSON parsing error: \(error)", type: .error)
            if let decodingError = error as? DecodingError {
                logDecodingError(decodingError)
            }
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChatFoodAnalysisResult(message: cleanText, suggestedFoodEntry: nil)
        }
    }

    func parseFoodAnalysis(from text: String) throws -> FoodAnalysis {
        log("📝 Raw food analysis response: \(text.prefix(500))...", type: .info)

        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = String(cleanText.dropFirst(7))
        } else if cleanText.hasPrefix("```") {
            cleanText = String(cleanText.dropFirst(3))
        }
        if cleanText.hasSuffix("```") {
            cleanText = String(cleanText.dropLast(3))
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonPattern = #"\{[\s\S]*\}"#
        if let range = cleanText.range(of: jsonPattern, options: .regularExpression) {
            cleanText = String(cleanText[range])
        }

        guard let data = cleanText.data(using: .utf8) else {
            log("❌ Failed to convert text to data", type: .error)
            throw GeminiError.parsingError
        }

        do {
            let result = try JSONDecoder().decode(FoodAnalysis.self, from: data)
            log("✅ Successfully parsed food analysis: \(result.name)", type: .info)
            return result
        } catch {
            log("❌ JSON decode error: \(error)", type: .error)
            log("📄 JSON text was: \(cleanText.prefix(300))", type: .debug)
            throw GeminiError.parsingError
        }
    }

    private func logDecodingError(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, _):
            log("   Missing key: '\(key.stringValue)'", type: .error)
        case .typeMismatch(let type, let context):
            log("   Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", type: .error)
        case .valueNotFound(let type, _):
            log("   Value not found: \(type)", type: .error)
        case .dataCorrupted(let context):
            log("   Data corrupted: \(context.debugDescription)", type: .error)
        @unknown default:
            break
        }
    }

    // MARK: - Workout Suggestions

    /// Get workout suggestions based on history and goals
    func suggestWorkout(
        history: [WorkoutSession],
        goal: String,
        availableTime: Int? = nil
    ) async throws -> String {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let prompt = GeminiPromptBuilder.buildWorkoutSuggestionPrompt(
            history: history,
            goal: goal,
            availableTime: availableTime
        )

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(thinkingLevel: .medium, maxTokens: 2048)
        ]

        return try await makeRequest(body: requestBody)
    }
}
