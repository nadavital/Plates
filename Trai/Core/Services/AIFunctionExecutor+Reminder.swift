//
//  AIFunctionExecutor+Reminder.swift
//  Trai
//
//  Executes reminder-related function calls
//

import Foundation

extension AIFunctionExecutor {

    // MARK: - Create Reminder

    func executeCreateReminder(_ args: [String: Any]) -> ExecutionResult {
        // Parse required arguments
        guard let title = args["title"] as? String,
              let hour = args["hour"] as? Int,
              let minute = args["minute"] as? Int else {
            return .dataResponse(FunctionResult(
                name: "create_reminder",
                response: ["error": "Missing required parameters: title, hour, minute"]
            ))
        }

        // Validate hour and minute
        guard hour >= 0, hour <= 23 else {
            return .dataResponse(FunctionResult(
                name: "create_reminder",
                response: ["error": "Invalid hour: must be 0-23"]
            ))
        }

        guard minute >= 0, minute <= 59 else {
            return .dataResponse(FunctionResult(
                name: "create_reminder",
                response: ["error": "Invalid minute: must be 0-59"]
            ))
        }

        // Parse optional arguments
        let body = args["body"] as? String ?? ""
        let repeatDays = args["repeat_days"] as? String ?? ""

        // Create suggestion for user confirmation
        let suggestion = SuggestedReminder(
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            repeatDays: repeatDays
        )

        return .suggestedReminder(suggestion)
    }
}
