//
//  GeminiService.swift
//  Trai
//
//  Core Gemini API service - types, configuration, and API helpers
//  Extensions: GeminiService+Food.swift, GeminiService+Chat.swift,
//              GeminiService+FunctionCalling.swift, GeminiService+Plan.swift
//

import Foundation
import os.log
import SwiftData
import SwiftUI

/// Thinking level for Gemini 3 models - controls reasoning depth
enum ThinkingLevel: String {
    case minimal = "minimal"  // Fastest, for simple classification/greetings
    case low = "low"          // Quick responses, math adjustments
    case medium = "medium"    // Balanced, for advice and analysis
}

/// Service for interacting with Google's Gemini API
@MainActor @Observable
final class GeminiService {
    let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    let model = "gemini-3-flash-preview"
    let appAccountService = AppAccountService.shared
    let accountSessionService = AccountSessionService.shared
    let backendClient = TraiBackendClient.shared
    let monetizationService = MonetizationService.shared

    private let logger = Logger(subsystem: "com.plates.app", category: "GeminiService")

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
            case .error: prefix = "❌ [Gemini ERROR]"
            case .fault: prefix = "💥 [Gemini FAULT]"
            case .info: prefix = "ℹ️ [Gemini]"
            default: prefix = "🤖 [Gemini]"
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

    func beginAIRequest(for feature: AIFeature) throws -> AIRequestTicket {
        let decision = monetizationService.accessDecision(for: feature)
        guard decision.isAllowed else {
            let message = decision.reason ?? "This AI feature is not available right now."
            lastError = message
            if message.localizedCaseInsensitiveContains("limit") {
                throw GeminiError.quotaExceeded(message)
            }
            throw GeminiError.accessDenied(message)
        }

        let ticket = AIRequestTicket(id: UUID(), feature: feature)
        activeAIRequests.append(ActiveAIRequest(id: ticket.id, feature: feature))
        lastError = nil
        return ticket
    }

    func completeAIRequest(_ ticket: AIRequestTicket) {
        guard removeAIRequest(id: ticket.id) != nil else { return }

        // Backend-proxied requests are already metered server-side and reflected
        // in the next synced quota snapshot.
        guard monetizationService.aiTransportMode == .directGemini else { return }
        monetizationService.recordSuccessfulAIRequest(ticket.feature)
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
        switch monetizationService.aiTransportMode {
        case .directGemini:
            let path = streaming
                ? "\(baseURL)/models/\(model):\(action)?alt=sse&key=\(Secrets.geminiAPIKey)"
                : "\(baseURL)/models/\(model):\(action)?key=\(Secrets.geminiAPIKey)"
            guard let url = URL(string: path) else {
                throw GeminiError.invalidResponse
            }
            return url
        case .backendProxy:
            guard accountSessionService.isAuthenticated else {
                let message = "Sign in is required before using server-backed AI features."
                lastError = message
                throw GeminiError.accessDenied(message)
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
                throw GeminiError.accessDenied(error.localizedDescription)
            }
        }
    }

    private func ensureBackendSessionIfNeeded() async throws {
        guard monetizationService.aiTransportMode == .backendProxy else { return }

        guard accountSessionService.isAuthenticated else {
            let message = "Sign in is required before using server-backed AI features."
            lastError = message
            throw GeminiError.accessDenied(message)
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
        throw GeminiError.accessDenied(message)
    }

    func configureRequest(_ request: inout URLRequest) async throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard monetizationService.aiTransportMode == .backendProxy else { return }

        try await ensureBackendSessionIfNeeded()

        guard let accessToken = accountSessionService.accessToken else {
            let message = "Your account session is missing. Please sign in again."
            lastError = message
            throw GeminiError.accessDenied(message)
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appAccountService.appAccountToken, forHTTPHeaderField: "X-Trai-App-Account-Token")
        request.setValue(activeAIRequests.last?.feature.rawValue ?? AIFeature.coachChat.rawValue, forHTTPHeaderField: "X-Trai-AI-Feature")
    }

    // MARK: - API Helpers

    /// Build generation config with thinking level and optional schema
    /// Note: maxTokens defaults to 16384 to avoid truncation issues
    func buildGenerationConfig(
        thinkingLevel: ThinkingLevel,
        maxTokens: Int = 16384,
        jsonSchema: [String: Any]? = nil
    ) -> [String: Any] {
        var config: [String: Any] = [
            "temperature": 1.0,  // Recommended for Gemini 3
            "topP": 0.95,
            "maxOutputTokens": maxTokens,
            "thinkingConfig": [
                "thinkingLevel": thinkingLevel.rawValue.uppercased()
            ]
        ]

        if let schema = jsonSchema {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = schema
        }

        return config
    }

    func makeRequest(body: [String: Any]) async throws -> String {
        let url = try serviceURL(action: "generateContent", streaming: false)

        log("🌐 Making request to Gemini API...", type: .info)
        log("   Model: \(model)", type: .debug)

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
            throw GeminiError.invalidResponse
        }

        log("📡 HTTP Status: \(httpResponse.statusCode)", type: httpResponse.statusCode == 200 ? .info : .error)

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("API Error Response: \(errorBody)", type: .error)
            lastError = "API Error: \(httpResponse.statusCode)"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
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
            throw GeminiError.invalidResponse
        }

        log("✅ Successfully extracted response text (\(text.count) characters)", type: .info)
        return text
    }

    func makeStreamingRequest(body: [String: Any], onChunk: @escaping (String) -> Void) async throws {
        let url = try serviceURL(action: "streamGenerateContent", streaming: true)

        log("🌐 Making streaming request to Gemini API...", type: .info)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try await configureRequest(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            lastError = "API Error: \(httpResponse.statusCode)"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: "Streaming request failed")
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
}
