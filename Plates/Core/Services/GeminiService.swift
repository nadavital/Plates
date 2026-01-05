//
//  GeminiService.swift
//  Plates
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

    private let logger = Logger(subsystem: "com.plates.app", category: "GeminiService")

    /// Enable verbose console logging for debugging
    var debugLoggingEnabled = true

    var isLoading = false
    var lastError: String?

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

    // MARK: - API Helpers

    /// Build generation config with thinking level and optional schema
    func buildGenerationConfig(
        thinkingLevel: ThinkingLevel,
        maxTokens: Int = 1024,
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
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(Secrets.geminiAPIKey)")!

        log("🌐 Making request to Gemini API...", type: .info)
        log("   Model: \(model)", type: .debug)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(Secrets.geminiAPIKey)")!

        log("🌐 Making streaming request to Gemini API...", type: .info)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
