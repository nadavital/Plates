//
//  GeminiFunctionExecutor+Memory.swift
//  Plates
//
//  Memory-related function execution for AI coach
//

import Foundation
import SwiftData

extension GeminiFunctionExecutor {

    // MARK: - Memory Functions

    /// Save a new memory about the user
    func executeSaveMemory(_ args: [String: Any]) -> ExecutionResult {
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
}
