//
//  GeminiTypes.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import Foundation

/// Response from Gemini API for food analysis
struct FoodAnalysis: Codable, Sendable {
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let servingSize: String?
    let confidence: String
    let notes: String?
    let emoji: String?

    /// Display emoji with fallback
    var displayEmoji: String {
        emoji ?? "🍽️"
    }
}

/// Result from chat-based food analysis (with optional meal logging)
struct ChatFoodAnalysisResult: Sendable {
    let message: String
    let suggestedFoodEntry: SuggestedFoodEntry?
}

/// Food entry suggested by AI for logging
struct SuggestedFoodEntry: Codable, Sendable {
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let servingSize: String?
    let emoji: String?  // Relevant emoji for the food (☕, 🥗, 🍳, etc.)
    let loggedAtTime: String?  // HH:mm format if user specified a time

    /// Parse the loggedAtTime into a Date (today at that time)
    var loggedAtDate: Date? {
        guard let timeString = loggedAtTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: timeString) else { return nil }

        // Combine today's date with the parsed time
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components)
    }

    /// Display emoji or default fork and knife
    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    init(name: String, calories: Int, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, servingSize: String?, emoji: String? = nil, loggedAtTime: String? = nil) {
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.servingSize = servingSize
        self.emoji = emoji
        self.loggedAtTime = loggedAtTime
    }
}

/// Context provided to AI for fitness-aware responses
struct FitnessContext: Sendable {
    let userGoal: String
    let dailyCalorieGoal: Int
    let dailyProteinGoal: Int
    let todaysCalories: Int
    let todaysProtein: Double
    let recentWorkouts: [String]
    let currentWeight: Double?
    let targetWeight: Double?

    init(
        userGoal: String,
        dailyCalorieGoal: Int,
        dailyProteinGoal: Int,
        todaysCalories: Int,
        todaysProtein: Double,
        recentWorkouts: [String] = [],
        currentWeight: Double? = nil,
        targetWeight: Double? = nil
    ) {
        self.userGoal = userGoal
        self.dailyCalorieGoal = dailyCalorieGoal
        self.dailyProteinGoal = dailyProteinGoal
        self.todaysCalories = todaysCalories
        self.todaysProtein = todaysProtein
        self.recentWorkouts = recentWorkouts
        self.currentWeight = currentWeight
        self.targetWeight = targetWeight
    }
}

// MARK: - Plan Update Suggestion

/// Plan update suggested by AI for user confirmation
struct PlanUpdateSuggestionEntry: Codable, Sendable {
    let calories: Int?
    let proteinGrams: Int?
    let carbsGrams: Int?
    let fatGrams: Int?
    let goal: String?
    let rationale: String?

    /// Whether this suggestion contains any changes
    var hasChanges: Bool {
        calories != nil || proteinGrams != nil || carbsGrams != nil ||
        fatGrams != nil || goal != nil
    }

    /// Formatted goal display name
    var goalDisplayName: String? {
        guard let goal else { return nil }
        // Convert raw goal string to display name
        switch goal.lowercased().replacing("_", with: "") {
        case "loseweight": return "Lose Weight"
        case "losefat": return "Lose Fat, Keep Muscle"
        case "buildmuscle": return "Build Muscle"
        case "recomposition", "bodyrecomposition": return "Body Recomposition"
        case "maintenance", "maintainweight": return "Maintain Weight"
        case "performance", "athleticperformance": return "Athletic Performance"
        case "health", "generalhealth": return "General Health"
        default: return goal.replacing("_", with: " ").capitalized
        }
    }

    /// Create from function executor result
    init(
        calories: Int? = nil,
        proteinGrams: Int? = nil,
        carbsGrams: Int? = nil,
        fatGrams: Int? = nil,
        goal: String? = nil,
        rationale: String? = nil
    ) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.goal = goal
        self.rationale = rationale
    }
}

// MARK: - Check-In Response

/// A suggested response option for check-in questions
struct CheckInResponseOption: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let emoji: String?

    init(id: String? = nil, label: String, emoji: String? = nil) {
        self.id = id ?? UUID().uuidString
        self.label = label
        self.emoji = emoji
    }

    var displayLabel: String {
        if let emoji {
            return "\(emoji) \(label)"
        }
        return label
    }
}

/// Structured response from AI during check-in with optional suggested responses
struct CheckInAIResponse: Codable, Sendable {
    let message: String
    let suggestedResponses: [CheckInResponseOption]?
    let isComplete: Bool?
    let summary: String?

    /// Whether this response has suggested responses for the user
    var hasSuggestedResponses: Bool {
        guard let responses = suggestedResponses else { return false }
        return !responses.isEmpty
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case invalidInput(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .parsingError:
            return "Failed to parse AI response"
        }
    }
}
