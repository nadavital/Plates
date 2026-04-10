//
//  AIFunctionExecutor+Activity.swift
//  Trai
//
//  Activity data function execution
//

import Foundation

extension AIFunctionExecutor {

    // MARK: - Activity Summary

    func executeGetActivitySummary() -> ExecutionResult {
        // Build response with activity metrics
        var response: [String: Any] = [
            "steps": activityData.steps,
            "active_calories": activityData.activeCalories,
            "exercise_minutes": activityData.exerciseMinutes
        ]

        // Add helpful context
        let stepsGoal = 10000  // Standard daily goal
        let caloriesGoal = 500 // Typical active calorie goal
        let exerciseGoal = 30  // WHO recommendation

        response["steps_goal"] = stepsGoal
        response["steps_progress"] = Double(activityData.steps) / Double(stepsGoal) * 100

        response["calories_goal"] = caloriesGoal
        response["calories_progress"] = Double(activityData.activeCalories) / Double(caloriesGoal) * 100

        response["exercise_goal_minutes"] = exerciseGoal
        response["exercise_progress"] = Double(activityData.exerciseMinutes) / Double(exerciseGoal) * 100

        // Add summary text for easy reference
        var summaryParts: [String] = []
        summaryParts.append("Steps: \(activityData.steps.formatted()) / \(stepsGoal.formatted())")
        summaryParts.append("Active calories: \(activityData.activeCalories) cal")
        summaryParts.append("Exercise: \(activityData.exerciseMinutes) min")

        response["summary"] = summaryParts.joined(separator: ", ")

        // Add data source note
        if activityData.steps == 0 && activityData.activeCalories == 0 {
            response["note"] = "No activity data available. This may be because HealthKit permissions were not granted or there's no data recorded yet today."
        }

        return .dataResponse(FunctionResult(
            name: "get_activity_summary",
            response: response
        ))
    }
}
