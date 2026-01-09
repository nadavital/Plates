//
//  GeminiService+WorkoutPlan.swift
//  Plates
//
//  Workout plan generation and refinement
//

import Foundation
import os

extension GeminiService {

    // MARK: - Workout Plan Refinement Response

    struct WorkoutPlanRefinementResponse {
        let responseType: ResponseType
        let message: String
        let proposedPlan: WorkoutPlan?
        let updatedPlan: WorkoutPlan?

        enum ResponseType: String {
            case message
            case proposePlan
            case planUpdate
        }
    }

    // MARK: - Workout Plan Generation

    /// Generate a personalized workout plan
    func generateWorkoutPlan(request: WorkoutPlanGenerationRequest) async throws -> WorkoutPlan {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        log("🏋️ Starting workout plan generation for: \(request.name)", type: .info)
        log("📊 User data - Age: \(request.age), Goal: \(request.goal.rawValue)", type: .info)
        log("🎯 Workout prefs - Days: \(request.availableDays.map { "\($0)" } ?? "flexible"), Experience: \(request.experienceLevel?.rawValue ?? "unspecified"), Equipment: \(request.equipmentAccess?.rawValue ?? "unspecified")", type: .info)

        let prompt = GeminiPromptBuilder.buildWorkoutPlanGenerationPrompt(request: request)
        logPrompt(prompt)

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .medium,
                maxTokens: 4096,
                jsonSchema: GeminiPromptBuilder.workoutPlanSchema
            )
        ]

        do {
            let responseText = try await makeRequest(body: requestBody)
            logResponse(responseText)
            let plan = try parseWorkoutPlan(from: responseText, fallbackRequest: request)
            log("✅ Successfully parsed workout plan - Split: \(plan.splitType.displayName), Templates: \(plan.templates.count)", type: .info)
            return plan
        } catch {
            log("Failed to generate workout plan: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    // MARK: - Workout Plan Refinement (Chat)

    /// Refine/discuss the workout plan through chat
    func refineWorkoutPlan(
        currentPlan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest,
        userMessage: String,
        conversationHistory: [WorkoutPlanChatMessage]
    ) async throws -> WorkoutPlanRefinementResponse {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        log("💬 Workout plan refinement request: \(userMessage)", type: .info)

        let prompt = GeminiPromptBuilder.buildWorkoutPlanRefinementPrompt(
            currentPlan: currentPlan,
            request: request,
            userMessage: userMessage,
            conversationHistory: conversationHistory
        )
        logPrompt(prompt)

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": buildGenerationConfig(
                thinkingLevel: .low,
                maxTokens: 4096,
                jsonSchema: GeminiPromptBuilder.workoutPlanRefinementSchema
            )
        ]

        do {
            let responseText = try await makeRequest(body: requestBody)
            logResponse(responseText)
            return try parseWorkoutPlanRefinementResponse(from: responseText)
        } catch {
            log("Failed to refine workout plan: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    // MARK: - Parsing

    private func parseWorkoutPlanRefinementResponse(from text: String) throws -> WorkoutPlanRefinementResponse {
        let cleanText = cleanJSONResponse(text)

        guard let data = cleanText.data(using: .utf8) else {
            throw GeminiError.parsingError
        }

        struct RefinementJSON: Codable {
            let responseType: String
            let message: String
            let proposedPlan: WorkoutPlan?
            let updatedPlan: WorkoutPlan?
        }

        let decoded = try JSONDecoder().decode(RefinementJSON.self, from: data)
        let responseType = WorkoutPlanRefinementResponse.ResponseType(rawValue: decoded.responseType) ?? .message

        return WorkoutPlanRefinementResponse(
            responseType: responseType,
            message: decoded.message,
            proposedPlan: decoded.proposedPlan,
            updatedPlan: decoded.updatedPlan
        )
    }

    private func parseWorkoutPlan(from text: String, fallbackRequest: WorkoutPlanGenerationRequest) throws -> WorkoutPlan {
        log("🔄 Parsing workout plan response...", type: .info)

        let cleanText = cleanJSONResponse(text)

        log("📋 Cleaned JSON:", type: .debug)
        if debugLoggingEnabled {
            print(cleanText)
        }

        guard let data = cleanText.data(using: .utf8) else {
            log("⚠️ Failed to convert response to UTF8 data, using fallback plan", type: .error)
            let fallback = WorkoutPlan.createDefault(from: fallbackRequest)
            log("📦 Fallback workout plan created - Split: \(fallback.splitType.displayName)", type: .info)
            return fallback
        }

        do {
            let plan = try JSONDecoder().decode(WorkoutPlan.self, from: data)
            log("✅ Workout plan JSON decoded successfully!", type: .info)
            return plan
        } catch let decodingError {
            log("⚠️ Workout plan JSON decoding failed: \(decodingError)", type: .error)
            if let decodingError = decodingError as? DecodingError {
                logWorkoutPlanDecodingError(decodingError)
            }
            let fallback = WorkoutPlan.createDefault(from: fallbackRequest)
            log("📦 Using fallback workout plan - Split: \(fallback.splitType.displayName)", type: .info)
            return fallback
        }
    }

    private func cleanJSONResponse(_ text: String) -> String {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = String(cleanText.dropFirst(7))
        } else if cleanText.hasPrefix("```") {
            cleanText = String(cleanText.dropFirst(3))
        }
        if cleanText.hasSuffix("```") {
            cleanText = String(cleanText.dropLast(3))
        }
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logWorkoutPlanDecodingError(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            log("   Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", type: .error)
        case .typeMismatch(let type, let context):
            log("   Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", type: .error)
        case .valueNotFound(let type, let context):
            log("   Value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", type: .error)
        case .dataCorrupted(let context):
            log("   Data corrupted: \(context.debugDescription)", type: .error)
        @unknown default:
            break
        }
    }
}
