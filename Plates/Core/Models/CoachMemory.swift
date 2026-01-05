//
//  CoachMemory.swift
//  Plates
//
//  AI coach memory system - stores facts and preferences about the user
//

import Foundation
import SwiftData

/// Category for coach memories
enum MemoryCategory: String, Codable, CaseIterable {
    case preference = "preference"       // "Likes chicken", "Prefers morning workouts"
    case restriction = "restriction"     // "Allergic to peanuts", "Can't do squats"
    case habit = "habit"                 // "Usually skips breakfast", "Works out 3x/week"
    case goal = "goal"                   // "Training for marathon", "Wants to hit 180lbs"
    case context = "context"             // "Works night shifts", "Has a home gym"
    case feedback = "feedback"           // "Found portion sizes too large"

    var displayName: String {
        switch self {
        case .preference: return "Preference"
        case .restriction: return "Restriction"
        case .habit: return "Habit"
        case .goal: return "Goal"
        case .context: return "Context"
        case .feedback: return "Feedback"
        }
    }

    var icon: String {
        switch self {
        case .preference: return "heart.fill"
        case .restriction: return "xmark.circle.fill"
        case .habit: return "repeat"
        case .goal: return "target"
        case .context: return "person.fill"
        case .feedback: return "quote.bubble.fill"
        }
    }
}

/// Topic area for coach memories
enum MemoryTopic: String, Codable, CaseIterable {
    case food = "food"
    case workout = "workout"
    case schedule = "schedule"
    case general = "general"

    var displayName: String {
        switch self {
        case .food: return "Food & Nutrition"
        case .workout: return "Workouts"
        case .schedule: return "Schedule"
        case .general: return "General"
        }
    }
}

/// Persistent memory stored by the AI coach
@Model
final class CoachMemory {
    var id: UUID = UUID()

    /// The memory content (e.g., "User doesn't like fish", "Prefers high-protein breakfast")
    var content: String = ""

    /// Category of memory (preference, restriction, habit, etc.)
    var categoryRaw: String = MemoryCategory.preference.rawValue

    /// Topic area (food, workout, schedule, general)
    var topicRaw: String = MemoryTopic.general.rawValue

    /// When the memory was created
    var createdAt: Date = Date()

    /// Where the memory came from (chat, check-in, onboarding)
    var source: String = "chat"

    /// Whether this memory is still active/relevant
    var isActive: Bool = true

    /// Importance score (1-5) for prioritizing in prompts
    var importance: Int = 3

    // MARK: - Computed Properties

    var category: MemoryCategory {
        get { MemoryCategory(rawValue: categoryRaw) ?? .preference }
        set { categoryRaw = newValue.rawValue }
    }

    var topic: MemoryTopic {
        get { MemoryTopic(rawValue: topicRaw) ?? .general }
        set { topicRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        content: String,
        category: MemoryCategory = .preference,
        topic: MemoryTopic = .general,
        source: String = "chat",
        importance: Int = 3
    ) {
        self.id = UUID()
        self.content = content
        self.categoryRaw = category.rawValue
        self.topicRaw = topic.rawValue
        self.createdAt = Date()
        self.source = source
        self.isActive = true
        self.importance = min(5, max(1, importance))
    }

    /// Format for inclusion in AI prompt
    var promptFormat: String {
        "[\(category.displayName)] \(content)"
    }
}

// MARK: - Memory Formatting

extension Array where Element == CoachMemory {
    /// Format memories for inclusion in AI system prompt
    func formatForPrompt() -> String {
        guard !isEmpty else { return "" }

        // Group by topic
        let grouped = Dictionary(grouping: self) { $0.topic }

        var sections: [String] = []

        for topic in MemoryTopic.allCases {
            guard let memories = grouped[topic], !memories.isEmpty else { continue }

            // Sort by importance (highest first) then by date (newest first)
            let sorted = memories.sorted { m1, m2 in
                if m1.importance != m2.importance {
                    return m1.importance > m2.importance
                }
                return m1.createdAt > m2.createdAt
            }

            let items = sorted.map { "• \($0.content)" }.joined(separator: "\n")
            sections.append("\(topic.displayName):\n\(items)")
        }

        return sections.joined(separator: "\n\n")
    }
}
