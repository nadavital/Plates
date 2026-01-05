//
//  WeeklyCheckIn.swift
//  Plates
//
//  Model for tracking weekly check-in history and AI insights
//

import Foundation
import SwiftData

/// Represents a weekly check-in session with the AI coach
@Model
final class WeeklyCheckIn {
    var id: UUID = UUID()
    var checkInDate: Date = Date()
    var weekNumber: Int = 0

    // MARK: - Weekly Snapshot (at check-in time)

    /// Total calories consumed during the week
    var totalCaloriesConsumed: Int = 0

    /// Average daily calories
    var averageDailyCalories: Int = 0

    /// Total protein consumed (grams)
    var totalProteinGrams: Double = 0

    /// Number of days with food logged
    var daysTracked: Int = 0

    /// Workouts completed during the week
    var workoutsCompleted: Int = 0

    /// Weight at start of week (kg)
    var startingWeightKg: Double?

    /// Weight at end of week (kg)
    var endingWeightKg: Double?

    /// Calorie goal during this week
    var calorieGoal: Int = 0

    /// Calorie adherence percentage (0-1)
    var calorieAdherence: Double = 0

    // MARK: - AI-Generated Content

    /// AI summary of the week's progress
    var aiSummary: String = ""

    /// AI insights and observations
    var aiInsights: String = ""

    /// AI recommendations for next week
    var aiRecommendations: String = ""

    // MARK: - Plan Changes

    /// Whether plan was adjusted during this check-in
    var planChangesApplied: Bool = false

    /// Previous calorie goal (before change)
    var previousCalories: Int?

    /// New calorie goal (after change)
    var newCalories: Int?

    /// Previous protein goal
    var previousProtein: Int?

    /// New protein goal
    var newProtein: Int?

    /// Rationale for plan changes
    var changeRationale: String?

    // MARK: - Chat Session Link

    /// Session ID linking to the chat conversation
    var chatSessionId: UUID?

    // MARK: - User Reflection

    /// User's energy level (1-5)
    var userEnergyLevel: Int?

    /// What went well this week
    var userWentWell: String?

    /// Challenges faced this week
    var userChallenges: String?

    /// Focus area for next week
    var userFocusNextWeek: String?

    // MARK: - Status

    /// Whether the check-in is complete
    var isCompleted: Bool = false

    /// When the check-in was completed
    var completedAt: Date?

    init() {}

    // MARK: - Computed Properties

    /// Weight change during the week
    var weightChange: Double? {
        guard let start = startingWeightKg, let end = endingWeightKg else { return nil }
        return end - start
    }

    /// Formatted weight change string
    var weightChangeFormatted: String? {
        guard let change = weightChange else { return nil }
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change)) kg"
    }

    /// Week description (e.g., "Week of Dec 22")
    var weekDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: checkInDate))"
    }
}
