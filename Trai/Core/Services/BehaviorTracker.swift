//
//  BehaviorTracker.swift
//  Trai
//
//  Single write path for app-wide behavior events.
//

import Foundation
import SwiftData

@MainActor
final class BehaviorTracker {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func record(
        actionKey: String,
        domain: BehaviorDomain,
        surface: BehaviorSurface,
        outcome: BehaviorOutcome = .performed,
        relatedEntityId: UUID? = nil,
        metadata: [String: String]? = nil,
        occurredAt: Date = .now,
        saveImmediately: Bool = true
    ) {
        guard !actionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let event = BehaviorEvent(
            actionKey: actionKey,
            domain: domain,
            surface: surface,
            outcome: outcome,
            occurredAt: occurredAt,
            relatedEntityId: relatedEntityId?.uuidString,
            metadataJSON: encodeMetadata(metadata)
        )

        modelContext.insert(event)
        if saveImmediately {
            try? modelContext.save()
        }
    }

    static func suggestionActionKey(from suggestionType: String) -> String {
        let normalized = suggestionType.lowercased()

        if normalized.contains("review") || normalized.contains("plan") {
            if normalized.contains("workout") {
                return BehaviorActionKey.reviewWorkoutPlan
            }
            return BehaviorActionKey.reviewNutritionPlan
        }
        if normalized.contains("profile") {
            return BehaviorActionKey.openProfile
        }
        if normalized.contains("recovery") {
            return BehaviorActionKey.openRecovery
        }
        if normalized.contains("weight") {
            return BehaviorActionKey.logWeight
        }
        if normalized.contains("workout") || normalized.contains("train") {
            return BehaviorActionKey.startWorkout
        }
        if normalized.contains("macro") {
            return BehaviorActionKey.openMacroDetail
        }
        if normalized.contains("calorie") {
            return BehaviorActionKey.openCalorieDetail
        }
        if normalized.contains("reminder") {
            return BehaviorActionKey.completeReminder
        }
        if normalized.contains("meal") || normalized.contains("food") || normalized.contains("protein") || normalized.contains("log_") {
            return BehaviorActionKey.logFood
        }

        return "engagement.suggestion.\(normalized.replacingOccurrences(of: " ", with: "_"))"
    }

    private func encodeMetadata(_ metadata: [String: String]?) -> String? {
        guard let metadata, !metadata.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(metadata),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
