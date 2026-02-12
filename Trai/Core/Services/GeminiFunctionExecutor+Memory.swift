//
//  GeminiFunctionExecutor+Memory.swift
//  Trai
//
//  Memory-related function execution for AI coach
//

import Foundation
import SwiftData

extension GeminiFunctionExecutor {

    // MARK: - Memory Functions

    /// Save a new memory about the user
    func executeSaveMemory(_ args: [String: Any]) -> ExecutionResult {
        // Don't save memories in incognito mode
        if isIncognitoMode {
            return .dataResponse(FunctionResult(
                name: "save_memory",
                response: [
                    "success": false,
                    "reason": "Memory not saved - incognito mode is active"
                ]
            ))
        }

        guard let content = args["content"] as? String,
              let categoryRaw = args["category"] as? String,
              let topicRaw = args["topic"] as? String else {
            return .dataResponse(FunctionResult(
                name: "save_memory",
                response: ["error": "Missing required parameters (content, category, topic)"]
            ))
        }

        let category = MemoryCategory(rawValue: categoryRaw) ?? .preference
        let topic = MemoryTopic(rawValue: topicRaw) ?? .general
        let importance = args["importance"] as? Int ?? 3

        // Check for duplicate or similar memories
        let searchContent = content.lowercased()
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive }
        )

        let existingMemories = (try? modelContext.fetch(descriptor)) ?? []

        // Simple duplicate check - if content is very similar, don't add
        let isDuplicate = existingMemories.contains { memory in
            let existingLower = memory.content.lowercased()
            return existingLower == searchContent ||
                   existingLower.contains(searchContent) ||
                   searchContent.contains(existingLower)
        }

        if isDuplicate {
            return .dataResponse(FunctionResult(
                name: "save_memory",
                response: [
                    "success": false,
                    "reason": "Similar memory already exists"
                ]
            ))
        }

        // Create the new memory
        let memory = CoachMemory(
            content: content,
            category: category,
            topic: topic,
            source: "chat",
            importance: importance
        )

        modelContext.insert(memory)
        try? modelContext.save()

        return .dataResponse(FunctionResult(
            name: "save_memory",
            response: [
                "success": true,
                "memory_id": memory.id.uuidString,
                "content": content,
                "category": category.displayName,
                "topic": topic.displayName
            ]
        ))
    }

    /// Delete/deactivate a memory
    func executeDeleteMemory(_ args: [String: Any]) -> ExecutionResult {
        guard let searchContent = args["memory_content"] as? String else {
            return .dataResponse(FunctionResult(
                name: "delete_memory",
                response: ["error": "Missing required parameter: memory_content"]
            ))
        }

        let reason = args["reason"] as? String

        // Find matching memories
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive }
        )

        let memories = (try? modelContext.fetch(descriptor)) ?? []

        // Find memories that match (case-insensitive partial match)
        let searchLower = searchContent.lowercased()
        let matchingMemories = memories.filter { memory in
            memory.content.lowercased().contains(searchLower)
        }

        guard !matchingMemories.isEmpty else {
            return .dataResponse(FunctionResult(
                name: "delete_memory",
                response: [
                    "success": false,
                    "reason": "No matching memory found"
                ]
            ))
        }

        // Deactivate all matching memories
        var deletedContents: [String] = []
        for memory in matchingMemories {
            memory.isActive = false
            deletedContents.append(memory.content)
        }

        try? modelContext.save()

        return .dataResponse(FunctionResult(
            name: "delete_memory",
            response: [
                "success": true,
                "deleted_count": matchingMemories.count,
                "deleted_memories": deletedContents,
                "reason": reason ?? "User requested deletion"
            ]
        ))
    }

    /// Save temporary short-term context as an expiring CoachSignal
    func executeSaveShortTermContext(_ args: [String: Any]) -> ExecutionResult {
        if isIncognitoMode {
            return .dataResponse(FunctionResult(
                name: "save_short_term_context",
                response: [
                    "success": false,
                    "reason": "Short-term context not saved - incognito mode is active"
                ]
            ))
        }

        guard let content = args["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .dataResponse(FunctionResult(
                name: "save_short_term_context",
                response: ["error": "Missing required parameter: content"]
            ))
        }

        let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let domainRaw = (args["domain"] as? String) ?? CoachSignalDomain.general.rawValue
        let domain = CoachSignalDomain(rawValue: domainRaw) ?? .general
        let severity = args["severity"] as? Double ?? 0.45
        let confidence = args["confidence"] as? Double ?? 0.7
        let hoursToLive = args["hours_to_live"] as? Double ?? 48.0

        let signalService = CoachSignalService(modelContext: modelContext)
        let signal = signalService.addSignal(
            title: (title?.isEmpty == false ? title : nil) ?? defaultSignalTitle(for: domain),
            detail: content,
            source: .chat,
            domain: domain,
            severity: severity,
            confidence: confidence,
            expiresAfter: max(1.0, hoursToLive) * 60 * 60
        )

        return .dataResponse(FunctionResult(
            name: "save_short_term_context",
            response: [
                "success": true,
                "signal_id": signal.id.uuidString,
                "domain": signal.domain.rawValue,
                "title": signal.title
            ]
        ))
    }

    /// Resolve temporary short-term context signals by domain and/or content match
    func executeClearShortTermContext(_ args: [String: Any]) -> ExecutionResult {
        let domainRaw = args["domain"] as? String
        let domainFilter = domainRaw.flatMap(CoachSignalDomain.init(rawValue:))
        let contentMatch = (args["content_match"] as? String)?.lowercased()
        let reason = args["reason"] as? String

        let signalService = CoachSignalService(modelContext: modelContext)
        let activeSignals = signalService.activeSignals(now: .now)

        let matchingSignals = activeSignals.filter { signal in
            let matchesDomain = domainFilter == nil || signal.domain == domainFilter
            let matchesContent: Bool
            if let contentMatch {
                matchesContent = signal.title.lowercased().contains(contentMatch) ||
                    signal.detail.lowercased().contains(contentMatch)
            } else {
                matchesContent = true
            }
            return matchesDomain && matchesContent
        }

        guard !matchingSignals.isEmpty else {
            return .dataResponse(FunctionResult(
                name: "clear_short_term_context",
                response: [
                    "success": false,
                    "reason": "No matching short-term context found"
                ]
            ))
        }

        for signal in matchingSignals {
            signal.markResolved(note: reason ?? "Cleared by chat tool")
        }
        try? modelContext.save()

        return .dataResponse(FunctionResult(
            name: "clear_short_term_context",
            response: [
                "success": true,
                "cleared_count": matchingSignals.count
            ]
        ))
    }

    /// Get all active memories (helper for building prompts)
    func getActiveMemories() -> [CoachMemory] {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive },
            sortBy: [
                SortDescriptor(\.importance, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func defaultSignalTitle(for domain: CoachSignalDomain) -> String {
        switch domain {
        case .pain: "Pain signal"
        case .schedule: "Schedule constraint"
        case .sleep: "Sleep signal"
        case .stress: "Stress signal"
        case .recovery: "Recovery signal"
        case .readiness: "Readiness signal"
        case .nutrition: "Nutrition signal"
        case .general: "Temporary context"
        }
    }
}
