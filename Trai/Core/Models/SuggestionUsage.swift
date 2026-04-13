//
//  SuggestionUsage.swift
//  Trai
//
//  Tracks user engagement with chat suggestions for personalization
//

import Foundation
import SwiftData

/// Tracks how often a user taps specific suggestion types and when
@Model
final class SuggestionUsage {
    var id: UUID = UUID()

    /// The type identifier for this suggestion (e.g., "log_breakfast", "start_workout")
    var suggestionType: String = ""

    /// Total number of times this suggestion has been tapped
    var tapCount: Int = 0

    /// When this suggestion was last tapped
    var lastTapped: Date?

    /// JSON-encoded dictionary of [hour (0-23): tap count] for time-based learning
    /// Stored as JSON since SwiftData doesn't support [Int: Int] directly
    var hourlyTapsData: Data?

    init(suggestionType: String) {
        self.suggestionType = suggestionType
        self.tapCount = 0
        self.lastTapped = nil
        self.hourlyTapsData = nil
    }

    /// Get hourly taps dictionary
    var hourlyTaps: [Int: Int] {
        get {
            guard let data = hourlyTapsData else { return [:] }
            // Decode from JSON - keys are stored as strings
            guard let stringDict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            // Convert string keys back to Int
            var result: [Int: Int] = [:]
            for (key, value) in stringDict {
                if let intKey = Int(key) {
                    result[intKey] = value
                }
            }
            return result
        }
        set {
            // Convert Int keys to strings for JSON encoding
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
            hourlyTapsData = try? JSONEncoder().encode(stringDict)
        }
    }

    /// Record a tap at the current hour
    func recordTap() {
        tapCount += 1
        lastTapped = Date()

        let currentHour = Calendar.current.component(.hour, from: Date())
        var taps = hourlyTaps
        taps[currentHour, default: 0] += 1
        hourlyTaps = taps
    }

    /// Check if this suggestion is frequently used at a specific hour
    func tapsAt(hour: Int) -> Int {
        hourlyTaps[hour] ?? 0
    }
}

// MARK: - Suggestion Types

/// Standard suggestion type identifiers for tracking
enum SuggestionType {
    static let logBreakfast = "log_breakfast"
    static let logLunch = "log_lunch"
    static let logDinner = "log_dinner"
    static let logSnack = "log_snack"
    static let snapMeal = "snap_meal"
    static let startWorkout = "start_workout"
    static let timeTrain = "time_to_train"
    static let checkRecovery = "muscle_recovery"
    static let checkProgress = "my_progress"
    static let onTrack = "on_track"
    static let mealIdeas = "meal_ideas"
    static let healthySnacks = "healthy_snacks"
    static let logWeight = "log_weight"
    static let reviewPlan = "review_plan"
    static let reviewLastSession = "review_last_session"
    static let caloriesLeft = "calories_left"
    static let proteinToGo = "protein_to_go"
    static let myPRs = "my_prs"
    static let restDayTips = "rest_day_tips"
    static let waterIntake = "water_intake"
    static let dailyActivity = "daily_activity"
}
