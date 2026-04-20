//
//  AIService+Food.swift
//  Trai
//
//  Food analysis and workout suggestion methods
//

import Foundation
import os

extension AIService {

    // MARK: - Food Analysis

    /// Analyze food from an image and/or text description
    func analyzeFoodImage(_ imageData: Data?, description: String?) async throws -> FoodAnalysis {
        guard imageData != nil || description != nil else {
            throw AIServiceError.invalidInput("Please provide an image or description of the food")
        }

        if AppLaunchArguments.shouldUseMockFoodAIResponses {
            return mockFoodAnalysis(description: description)
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .foodPhotoAnalysis) {
            var parts: [TraiAIPart] = []

            let prompt = AIPromptBuilder.buildFoodAnalysisPrompt(description: description)
            parts.append(.text(prompt))

            if let imageData {
                logImagePayloadSummary(imageData, label: "Food analysis image")
                parts.append(AIBackendPayloadBuilder.imagePart(imageData))
            }

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalMessage(role: .user, parts: parts)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: AIPromptBuilder.foodAnalysisSchema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .low,
                    imageResolution: .high
                )
            )

            let responseText = try await makeRequest(request: request)
            return try parseFoodAnalysis(from: responseText)
        }
    }

    /// Analyze food image in chat context - returns message and optionally logs meal
    func analyzeFoodImageWithChat(
        _ imageData: Data?,
        userMessage: String,
        context: FitnessContext,
        tone: TraiCoachTone = .sharedPreference
    ) async throws -> ChatFoodAnalysisResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .foodPhotoAnalysis) {
            var parts: [TraiAIPart] = []

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
            let currentDateTime = dateFormatter.string(from: Date())

            let prompt = AIPromptBuilder.buildImageChatPrompt(
                userMessage: userMessage,
                context: context,
                currentDateTime: currentDateTime,
                tone: tone
            )

            parts.append(.text(prompt))

            if let imageData {
                logImagePayloadSummary(imageData, label: "Food chat image")
                parts.append(AIBackendPayloadBuilder.imagePart(imageData))
            }

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalMessage(role: .user, parts: parts)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: AIPromptBuilder.chatImageAnalysisSchema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .low,
                    imageResolution: .high
                )
            )

            let responseText = try await makeRequest(request: request)
            return try parseChatFoodAnalysis(from: responseText)
        }
    }

    // MARK: - Food Refinement

    /// Refine a food analysis based on user correction
    func refineFoodAnalysis(
        correction: String,
        currentSuggestion: SuggestedFoodEntry,
        imageData: Data?
    ) async throws -> SuggestedFoodEntry {
        if AppLaunchArguments.shouldUseMockFoodAIResponses {
            return mockRefinedFoodSuggestion(
                correction: correction,
                currentSuggestion: currentSuggestion
            )
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .foodRefinement) {
            var parts: [TraiAIPart] = []

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

            parts.append(.text(prompt))

            if let imageData {
                logImagePayloadSummary(imageData, label: "Food refinement image")
                parts.append(AIBackendPayloadBuilder.imagePart(imageData))
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

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalMessage(role: .user, parts: parts)
                ],
                output: AIBackendPayloadBuilder.canonicalOutput(
                    kind: .jsonSchema,
                    schema: schema
                ),
                generation: AIBackendPayloadBuilder.canonicalGeneration(
                    reasoningLevel: .low,
                    imageResolution: imageData == nil ? nil : .high
                )
            )

            let responseText = try await makeRequest(request: request)
            return try parseRefinedFoodAnalysis(from: responseText, preserving: currentSuggestion)
        }
    }

    private func parseRefinedFoodAnalysis(
        from text: String,
        preserving originalSuggestion: SuggestedFoodEntry?
    ) throws -> SuggestedFoodEntry {
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
            throw AIServiceError.parsingError
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
            emoji: decoded.emoji,
            loggedAtDateString: originalSuggestion?.loggedAtDateString,
            loggedAtTime: originalSuggestion?.loggedAtTime,
            components: originalSuggestion?.components ?? [],
            mealKind: originalSuggestion?.mealKind,
            notes: originalSuggestion?.notes,
            confidence: originalSuggestion?.confidence,
            schemaVersion: originalSuggestion?.schemaVersion ?? 1
        )
    }

    private func mockFoodAnalysis(description: String?) -> FoodAnalysis {
        let trimmedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = trimmedDescription?.isEmpty == false ? trimmedDescription! : "UI Test Meal"

        return FoodAnalysis(
            name: normalizedDescription.capitalized,
            calories: 430,
            proteinGrams: 28,
            carbsGrams: 42,
            fatGrams: 14,
            fiberGrams: 6,
            sugarGrams: 8,
            servingSize: "1 serving",
            confidence: "high",
            notes: "Mocked food analysis for UI testing",
            emoji: "🥗",
            components: nil,
            mealKind: nil
        )
    }

    private func mockRefinedFoodSuggestion(
        correction: String,
        currentSuggestion: SuggestedFoodEntry
    ) -> SuggestedFoodEntry {
        let lowercaseCorrection = correction.lowercased()
        let calorieAdjustment: Int
        if lowercaseCorrection.contains("100") {
            calorieAdjustment = 100
        } else if lowercaseCorrection.contains("50") {
            calorieAdjustment = 50
        } else {
            calorieAdjustment = 35
        }

        let updatedName: String
        if lowercaseCorrection.contains("wrap") {
            updatedName = "Chicken Wrap"
        } else if lowercaseCorrection.contains("salad") {
            updatedName = "Protein Salad"
        } else {
            updatedName = "\(currentSuggestion.name) Adjusted"
        }

        return SuggestedFoodEntry(
            name: updatedName,
            calories: currentSuggestion.calories + calorieAdjustment,
            proteinGrams: currentSuggestion.proteinGrams + 3,
            carbsGrams: currentSuggestion.carbsGrams + 4,
            fatGrams: currentSuggestion.fatGrams + 1,
            fiberGrams: (currentSuggestion.fiberGrams ?? 0) + 1,
            sugarGrams: currentSuggestion.sugarGrams,
            servingSize: currentSuggestion.servingSize,
            emoji: currentSuggestion.emoji ?? "🥗",
            loggedAtDateString: currentSuggestion.loggedAtDateString,
            loggedAtTime: currentSuggestion.loggedAtTime,
            components: currentSuggestion.components,
            mealKind: currentSuggestion.mealKind,
            notes: currentSuggestion.notes,
            confidence: currentSuggestion.confidence,
            schemaVersion: currentSuggestion.schemaVersion
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
                let sugarGrams: Double?
                let servingSize: String?
                let emoji: String?
                let loggedAtDate: String?
                let loggedAtTime: String?
                let components: [FoodAnalysisComponent]?
                let mealKind: String?
                let notes: String?
                let confidence: String?
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
                    sugarGrams: meal.sugarGrams,
                    servingSize: meal.servingSize,
                    emoji: meal.emoji,
                    loggedAtDateString: meal.loggedAtDate,
                    loggedAtTime: meal.loggedAtTime,
                    components: meal.components?.map(SuggestedFoodComponent.init(component:)) ?? [],
                    mealKind: meal.mealKind,
                    notes: meal.notes,
                    confidence: meal.confidence,
                    schemaVersion: 2
                )
                let emoji = meal.emoji ?? "🍽️"
                var logMessage = "\(emoji) AI suggests logging: \(meal.name) - \(meal.calories) kcal"
                if let date = meal.loggedAtDate {
                    logMessage += " on \(date)"
                }
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
            throw AIServiceError.parsingError
        }

        do {
            let result = try JSONDecoder().decode(FoodAnalysis.self, from: data)
            if result.shouldBeRejectedForLogging {
                let reason = result.rejectionReason ?? "unknown reason"
                log("⚠️ Rejecting food analysis as too unclear for logging: \(result.name) (\(reason))", type: .error)
                throw AIServiceError.invalidInput("Couldn't get a reliable food estimate from that image. Try a clearer photo or add a short description.")
            }
            log("✅ Successfully parsed food analysis: \(result.name)", type: .info)
            return result
        } catch {
            log("❌ JSON decode error: \(error)", type: .error)
            log("📄 JSON text was: \(cleanText.prefix(300))", type: .debug)
            if let decodingError = error as? DecodingError {
                logDecodingError(decodingError)
            }
            if let aiServiceError = error as? AIServiceError {
                throw aiServiceError
            }
            throw AIServiceError.parsingError
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
        return try await performAIRequest(for: .coachChat) {
            let prompt = AIPromptBuilder.buildWorkoutSuggestionPrompt(
                history: history,
                goal: goal,
                availableTime: availableTime
            )

            let request = AIBackendPayloadBuilder.canonicalRequest(
                messages: [
                    AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
                ],
                generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .medium)
            )

            return try await makeRequest(request: request)
        }
    }
}
