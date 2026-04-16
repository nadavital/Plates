//
//  AIService.swift
//  Trai
//
//  Core AI backend service - types, configuration, and API helpers
//  Extensions: AIService+Food.swift, AIService+Chat.swift,
//              AIService+FunctionCalling.swift, AIService+Plan.swift
//

import Foundation
import CryptoKit
import os.log
import SwiftData
import SwiftUI

/// Service for interacting with Trai's backend AI proxy
@MainActor @Observable
final class AIService {
    private struct AIProxyErrorPayload: Decodable {
        let error: String?
        let message: String?
    }

    let appAccountService = AppAccountService.shared
    let accountSessionService = AccountSessionService.shared
    let backendClient = TraiBackendClient.shared
    let monetizationService = MonetizationService.shared

    private let logger = Logger(subsystem: "com.plates.app", category: "AIService")

    /// Enable verbose console logging for debugging
    var debugLoggingEnabled = {
#if DEBUG
        true
#else
        false
#endif
    }()

    var isLoading = false
    var lastError: String?
    private struct ActiveAIRequest {
        let id: UUID
        let feature: AIFeature
    }
    private var activeAIRequests: [ActiveAIRequest] = []

    struct AIRequestTicket {
        let id: UUID
        let feature: AIFeature
    }

    // MARK: - Debug Logging

    func log(_ message: String, type: OSLogType = .debug) {
        logger.log(level: type, "\(message)")
        if debugLoggingEnabled {
            let prefix: String
            switch type {
            case .error: prefix = "❌ [AI ERROR]"
            case .fault: prefix = "💥 [AI FAULT]"
            case .info: prefix = "ℹ️ [AI]"
            default: prefix = "🤖 [AI]"
            }
            print("\(prefix) \(message)")
        }
    }

    func logPrompt(_ prompt: String) {
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
        log("📤 PROMPT SENT:", type: .info)
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
        print(prompt)
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
    }

    func logResponse(_ response: String) {
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
        log("📥 RESPONSE RECEIVED:", type: .info)
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
        print(response)
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: .info)
    }

    func logImagePayloadSummary(_ imageData: Data?, label: String) {
        guard debugLoggingEnabled else { return }

        guard let imageData else {
            log("📷 \(label): no image attached", type: .info)
            return
        }

        let digest = SHA256.hash(data: imageData)
        let digestPrefix = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let estimatedBase64Characters = ((imageData.count + 2) / 3) * 4

        log(
            "📷 \(label): \(imageData.count) bytes, base64≈\(estimatedBase64Characters) chars, sha256=\(digestPrefix)…",
            type: .info
        )
    }

    func beginAIRequest(for feature: AIFeature) throws -> AIRequestTicket {
        let decision = monetizationService.accessDecision(for: feature)
        guard decision.isAllowed else {
            let message = decision.reason ?? "This AI feature is not available right now."
            lastError = message
            if message.localizedCaseInsensitiveContains("limit") {
                throw AIServiceError.quotaExceeded(message)
            }
            throw AIServiceError.accessDenied(message)
        }

        let ticket = AIRequestTicket(id: UUID(), feature: feature)
        activeAIRequests.append(ActiveAIRequest(id: ticket.id, feature: feature))
        lastError = nil
        return ticket
    }

    func completeAIRequest(_ ticket: AIRequestTicket) {
        guard removeAIRequest(id: ticket.id) != nil else { return }
    }

    func cancelAIRequest(_ ticket: AIRequestTicket) {
        _ = removeAIRequest(id: ticket.id)
    }

    private func removeAIRequest(id: UUID) -> ActiveAIRequest? {
        guard let index = activeAIRequests.lastIndex(where: { $0.id == id }) else {
            return nil
        }
        return activeAIRequests.remove(at: index)
    }

    private func hasActiveAIRequest(_ ticket: AIRequestTicket) -> Bool {
        activeAIRequests.contains(where: { $0.id == ticket.id })
    }

    func performAIRequest<T>(
        for feature: AIFeature,
        operation: () async throws -> T
    ) async throws -> T {
        let ticket = try beginAIRequest(for: feature)

        do {
            let result = try await operation()
            if hasActiveAIRequest(ticket) {
                monetizationService.recordSuccessfulAIRequest(feature)
                completeAIRequest(ticket)
            }
            return result
        } catch {
            cancelAIRequest(ticket)
            throw error
        }
    }

    func serviceURL(
        action: String,
        streaming: Bool
    ) throws -> URL {
        guard accountSessionService.isAuthenticated else {
            let message = "Sign in is required before using server-backed AI features."
            lastError = message
            throw AIServiceError.accessDenied(message)
        }

        do {
            return try backendClient.proxyURL(
                action: action,
                streaming: streaming,
                environment: appAccountService.backendEnvironment,
                customBackendBaseURL: appAccountService.currentSnapshot.customBackendBaseURL
            )
        } catch {
            lastError = error.localizedDescription
            throw AIServiceError.accessDenied(error.localizedDescription)
        }
    }

    private func ensureBackendSessionIfNeeded() async throws {
        guard accountSessionService.isAuthenticated else {
            let message = "Sign in is required before using server-backed AI features."
            lastError = message
            throw AIServiceError.accessDenied(message)
        }

        let needsRefresh = accountSessionService.isSessionNearExpiry || accountSessionService.accessToken == nil
        guard needsRefresh else { return }

        let refreshed = await accountSessionService.refreshSessionIfNeeded()
        guard !refreshed else { return }

        if let expiresAt = accountSessionService.sessionSnapshot?.expiresAt,
           expiresAt > Date(),
           accountSessionService.accessToken != nil {
            log("Using existing backend session after refresh attempt failed", type: .info)
            return
        }

        let message = accountSessionService.lastErrorMessage ?? "Your account session expired. Please sign in again."
        lastError = message
        throw AIServiceError.accessDenied(message)
    }

    func configureRequest(_ request: inout URLRequest) async throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        try await ensureBackendSessionIfNeeded()

        guard let accessToken = accountSessionService.accessToken else {
            let message = "Your account session is missing. Please sign in again."
            lastError = message
            throw AIServiceError.accessDenied(message)
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appAccountService.appAccountToken, forHTTPHeaderField: "X-Trai-App-Account-Token")
        request.setValue(activeAIRequests.last?.feature.rawValue ?? AIFeature.coachChat.rawValue, forHTTPHeaderField: "X-Trai-AI-Feature")
        #if DEBUG
        if appAccountService.debugAIProviderOverride != .automatic {
            request.setValue(
                appAccountService.debugAIProviderOverride.rawValue,
                forHTTPHeaderField: "X-Trai-AI-Provider-Override"
            )
        }
        #endif
    }

    // MARK: - API Helpers

    /// Build AI backend generation config with optional structured output hints.
    func buildGenerationConfig(
        thinkingLevel: AIReasoningLevel,
        maxTokens: Int = 16384,
        jsonSchema: [String: Any]? = nil,
        imageResolution: AIImageResolution? = nil
    ) -> [String: Any] {
        AIBackendPayloadBuilder.generationConfig(
            reasoningLevel: thinkingLevel,
            maxTokens: maxTokens,
            jsonSchema: jsonSchema,
            imageResolution: imageResolution
        )
    }

    func makeRequest(request: TraiAIRequest) async throws -> String {
        try await makeRequest(body: AIBackendPayloadBuilder.requestBody(from: request))
    }

    func makeRequest(body: [String: Any]) async throws -> String {
        let url = try serviceURL(action: "generateContent", streaming: false)

        log("🌐 Making request to Trai AI backend...", type: .info)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try await configureRequest(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)

        log("⏱️ Response received in \(String(format: "%.2f", elapsed))s", type: .info)

        guard let httpResponse = response as? HTTPURLResponse else {
            log("Invalid response type", type: .error)
            throw AIServiceError.invalidResponse
        }

        log("📡 HTTP Status: \(httpResponse.statusCode)", type: httpResponse.statusCode == 200 ? .info : .error)

        guard httpResponse.statusCode == 200 else {
            let userError = parseAIProxyError(statusCode: httpResponse.statusCode, data: data)
            log("API Error Response: \(userError.localizedDescription)", type: .error)
            lastError = userError.localizedDescription
            throw userError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            log("Failed to parse API response structure", type: .error)
            if let rawJson = String(data: data, encoding: .utf8) {
                log("Raw response: \(rawJson.prefix(500))...", type: .debug)
            }
            throw AIServiceError.invalidResponse
        }

        log("✅ Successfully extracted response text (\(text.count) characters)", type: .info)
        return text
    }

    func makeStreamingRequest(request: TraiAIRequest, onChunk: @escaping (String) -> Void) async throws {
        try await makeStreamingRequest(body: AIBackendPayloadBuilder.requestBody(from: request), onChunk: onChunk)
    }

    func makeStreamingRequest(body: [String: Any], onChunk: @escaping (String) -> Void) async throws {
        let url = try serviceURL(action: "streamGenerateContent", streaming: true)

        log("🌐 Making streaming request to Trai AI backend...", type: .info)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try await configureRequest(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let userError = parseAIProxyError(
                statusCode: httpResponse.statusCode,
                data: data,
                fallbackMessage: "Streaming request failed"
            )
            lastError = userError.localizedDescription
            throw userError
        }

        // Parse SSE stream
        var buffer = ""
        for try await line in bytes.lines {
            // SSE format: "data: {json}"
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                // Skip empty data or [DONE] marker
                if jsonString.isEmpty || jsonString == "[DONE]" {
                    continue
                }

                // Parse the JSON chunk
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    buffer += text
                    log("📨 Stream chunk: +\(text.count) chars (total: \(buffer.count))", type: .debug)
                    await MainActor.run {
                        onChunk(buffer)
                    }
                }
            }
        }

        log("✅ Streaming complete (\(buffer.count) characters)", type: .info)
    }

    func parseAIProxyError(
        statusCode: Int,
        data: Data,
        fallbackMessage: String? = nil
    ) -> AIServiceError {
        let payload = try? JSONDecoder().decode(AIProxyErrorPayload.self, from: data)
        let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = payload?.message
            ?? rawMessage.flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackMessage
            ?? "Unknown backend error."
        let errorCode = payload?.error?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if statusCode == 401 {
            return .accessDenied(message)
        }

        if let errorCode, errorCode.hasPrefix("quota_exhausted") {
            return .quotaExceeded(message)
        }

        if let errorCode, errorCode.hasPrefix("ai_rate_limited") {
            return .accessDenied(message)
        }

        if statusCode == 403 {
            return .accessDenied(message)
        }

        return .apiError(statusCode: statusCode, message: message)
    }
}
