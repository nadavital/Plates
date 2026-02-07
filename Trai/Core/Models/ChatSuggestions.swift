//
//  ChatSuggestions.swift
//  Trai
//
//  Shared suggestion models used across chat, persistence, and Gemini tool execution.
//

import Foundation

struct SuggestedReminder: Codable, Sendable {
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let repeatDays: String  // Comma-separated or empty for daily

    /// Formatted time string (e.g., "9:00 AM")
    var formattedTime: String {
        let components = DateComponents(hour: hour, minute: minute)
        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Formatted repeat schedule description
    var scheduleDescription: String {
        if repeatDays.isEmpty {
            return "Every day"
        }

        let daysSet = Set(repeatDays.split(separator: ",").compactMap { Int($0) })
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = daysSet.sorted().compactMap { dayNames.indices.contains($0) ? dayNames[$0] : nil }

        if daysSet.count == 7 {
            return "Every day"
        } else if daysSet == Set([2, 3, 4, 5, 6]) {
            return "Weekdays"
        } else if daysSet == Set([1, 7]) {
            return "Weekends"
        } else {
            return days.joined(separator: ", ")
        }
    }
}

struct PlanUpdateSuggestion: Codable, Sendable {
    let calories: Int?
    let proteinGrams: Int?
    let carbsGrams: Int?
    let fatGrams: Int?
    let goal: String?
    let rationale: String?
}
