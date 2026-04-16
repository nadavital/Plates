//
//  AIService+PlanPipeline.swift
//  Trai
//
//  Shared internal pipeline helpers for AI plan generation/refinement
//

import Foundation
import os

extension AIService {
    struct PlanPipelineRefinementEnvelope<Plan: Decodable>: Decodable {
        let responseType: String
        let message: String
        let proposedPlan: Plan?
        let updatedPlan: Plan?
    }

    func executePlanGenerationPipeline<Plan: Decodable>(
        prompt: String,
        schema: [String: Any],
        decodeFailureLabel: String
    ) async throws -> Plan {
        let request = AIBackendPayloadBuilder.canonicalRequest(
            messages: [
                AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
            ],
            output: AIBackendPayloadBuilder.canonicalOutput(
                kind: .jsonSchema,
                schema: schema
            ),
            generation: AIBackendPayloadBuilder.canonicalGeneration(
                reasoningLevel: .medium
            )
        )

        let responseText = try await makeRequest(request: request)
        logResponse(responseText)
        return try parsePlanPayload(
            from: responseText,
            decodeFailureLabel: decodeFailureLabel
        )
    }

    func executePlanRefinementPipeline<Plan: Decodable>(
        prompt: String,
        schema: [String: Any]
    ) async throws -> PlanPipelineRefinementEnvelope<Plan> {
        let request = AIBackendPayloadBuilder.canonicalRequest(
            messages: [
                AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: prompt)
            ],
            output: AIBackendPayloadBuilder.canonicalOutput(
                kind: .jsonSchema,
                schema: schema
            ),
            generation: AIBackendPayloadBuilder.canonicalGeneration(
                reasoningLevel: .low
            )
        )

        let responseText = try await makeRequest(request: request)
        logResponse(responseText)
        return try parsePlanRefinementEnvelope(from: responseText)
    }

    func cleanJSONResponse(_ text: String) -> String {
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

    private func parsePlanPayload<Plan: Decodable>(
        from text: String,
        decodeFailureLabel: String
    ) throws -> Plan {
        let cleanText = cleanJSONResponse(text)

        log("📋 Cleaned JSON:", type: .debug)
        if debugLoggingEnabled {
            print(cleanText)
        }

        guard let data = cleanText.data(using: .utf8) else {
            log("⚠️ Failed to convert response to UTF8 data for \(decodeFailureLabel)", type: .error)
            throw AIServiceError.parsingError
        }

        do {
            return try JSONDecoder().decode(Plan.self, from: data)
        } catch let decodingError {
            log("⚠️ \(decodeFailureLabel) JSON decoding failed: \(decodingError)", type: .error)
            if let decodingError = decodingError as? DecodingError {
                logPlanPipelineDecodingError(decodingError)
            }
            throw AIServiceError.parsingError
        }
    }

    private func parsePlanRefinementEnvelope<Plan: Decodable>(
        from text: String
    ) throws -> PlanPipelineRefinementEnvelope<Plan> {
        let cleanText = cleanJSONResponse(text)

        guard let data = cleanText.data(using: .utf8) else {
            throw AIServiceError.parsingError
        }

        return try JSONDecoder().decode(PlanPipelineRefinementEnvelope<Plan>.self, from: data)
    }

    private func logPlanPipelineDecodingError(_ error: DecodingError) {
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
