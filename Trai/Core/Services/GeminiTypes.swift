//
//  GeminiTypes.swift
//  Trai
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
    let fiberGrams: Double?
    let sugarGrams: Double?
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
struct SuggestedFoodEntry: Codable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
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

    init(id: String = UUID().uuidString, name: String, calories: Int, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double? = nil, sugarGrams: Double? = nil, servingSize: String?, emoji: String? = nil, loggedAtTime: String? = nil) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
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

// MARK: - Suggested Food Edit

/// Represents a proposed edit to an existing food entry (needs user confirmation)
struct SuggestedFoodEdit: Codable, Sendable, Identifiable {
    let entryId: UUID
    let name: String
    let emoji: String?
    let changes: [FieldChange]

    var id: UUID { entryId }

    struct FieldChange: Codable, Sendable, Identifiable {
        var id: String { field }
        let field: String
        let fieldKey: String  // Internal key for applying (e.g., "calories", "proteinGrams")
        let oldValue: String
        let newValue: String
        let newNumericValue: Double?  // For applying the change
        let newStringValue: String?  // For string changes
    }

    /// Display emoji or default
    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    /// Summary of changes for display
    var changesSummary: String {
        changes.map { "\($0.field): \($0.oldValue) → \($0.newValue)" }.joined(separator: ", ")
    }
}

// MARK: - Plan Update Suggestion

/// Plan update suggested by AI for user confirmation
struct PlanUpdateSuggestionEntry: Codable, Sendable, Identifiable {
    var id: String {
        "\(calories ?? 0)-\(proteinGrams ?? 0)-\(carbsGrams ?? 0)-\(fatGrams ?? 0)-\(goal ?? "")"
    }
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

// MARK: - Suggested Workout Entry

/// Workout suggested by AI for user confirmation before starting
struct SuggestedWorkoutEntry: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let workoutType: String
    let targetMuscleGroups: [String]
    let exercises: [SuggestedExercise]
    let durationMinutes: Int
    let rationale: String

    struct SuggestedExercise: Codable, Sendable, Identifiable {
        var id: UUID = UUID()
        let name: String
        let sets: Int
        let reps: Int
        let weightKg: Double?
    }

    /// Summary for display
    var exercisesSummary: String {
        let count = exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }

    /// Muscle groups summary
    var muscleGroupsSummary: String {
        targetMuscleGroups.map { $0.capitalized }.joined(separator: ", ")
    }
}

// MARK: - Suggested Workout Log

/// Completed workout log suggested by AI for user confirmation before saving
struct SuggestedWorkoutLog: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let name: String?  // Trai-generated workout name
    let workoutType: String
    let durationMinutes: Int?
    let exercises: [LoggedExercise]
    let notes: String?

    struct LoggedExercise: Codable, Sendable, Identifiable {
        var id: UUID = UUID()
        let name: String
        let sets: [SetData]

        struct SetData: Codable, Sendable, Identifiable {
            var id: UUID = UUID()
            let reps: Int
            let weightKg: Double?

            /// Formatted weight in user's preferred unit
            func formattedWeight(useLbs: Bool) -> String? {
                guard let weight = weightKg, weight > 0 else { return nil }
                if useLbs {
                    let lbs = weight * 2.20462
                    return "\(Int(lbs)) lbs"
                } else {
                    return "\(Int(weight)) kg"
                }
            }
        }

        /// Total sets count
        var setCount: Int { sets.count }

        /// Summary string for display (e.g., "3×10" or "12, 10, 8")
        var setsSummary: String {
            guard !sets.isEmpty else { return "" }
            let allSameReps = sets.dropFirst().allSatisfy { $0.reps == sets.first?.reps }
            if allSameReps, let firstReps = sets.first?.reps {
                return "\(sets.count)×\(firstReps)"
            } else {
                return sets.map { "\($0.reps)" }.joined(separator: ", ")
            }
        }

        /// Weight summary (uses max weight)
        var maxWeightKg: Double? {
            sets.compactMap { $0.weightKg }.max()
        }

        /// Formatted weight in user's preferred unit
        func formattedWeight(useLbs: Bool) -> String? {
            guard let weight = maxWeightKg, weight > 0 else { return nil }
            if useLbs {
                let lbs = weight * 2.20462
                return "\(Int(lbs)) lbs"
            } else {
                return "\(Int(weight)) kg"
            }
        }
    }

    /// Display name for the workout (uses Trai-generated name or falls back to type)
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return workoutType.capitalized
    }

    /// Total sets across all exercises
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.setCount }
    }

    /// Summary for display
    var summary: String {
        var parts: [String] = []
        if !exercises.isEmpty {
            parts.append("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
            parts.append("\(totalSets) sets")
        }
        if let duration = durationMinutes, duration > 0 {
            parts.append("\(duration) min")
        }
        return parts.isEmpty ? workoutType.capitalized : parts.joined(separator: " • ")
    }

    /// Whether this is a strength workout
    var isStrength: Bool {
        ["strength", "weights", "lifting"].contains(workoutType.lowercased())
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case invalidInput(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case accessDenied(String)
    case quotaExceeded(String)

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
        case .accessDenied(let message):
            return message
        case .quotaExceeded(let message):
            return message
        }
    }
}

extension Error {
    var isUserCancelledRequest: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var aiUserFacingMessage: String? {
        switch self {
        case let geminiError as GeminiError:
            switch geminiError {
            case .accessDenied(let message), .quotaExceeded(let message):
                return message
            default:
                return nil
            }
        case let backendError as BackendClientError:
            return backendError.localizedDescription
        default:
            return nil
        }
    }

    func aiUserFacingMessage(fallback: String) -> String {
        aiUserFacingMessage ?? fallback
    }
}
