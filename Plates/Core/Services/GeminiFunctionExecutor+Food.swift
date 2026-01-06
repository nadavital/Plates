//
//  GeminiFunctionExecutor+Food.swift
//  Plates
//
//  Food-related function execution
//

import Foundation
import SwiftData

extension GeminiFunctionExecutor {

    // MARK: - Food Functions

    func executeSuggestFoodLog(_ args: [String: Any]) -> ExecutionResult {
        guard let name = args["name"] as? String,
              let calories = args["calories"] as? Int,
              let protein = args["protein_grams"] as? Double ?? (args["protein_grams"] as? Int).map(Double.init),
              let carbs = args["carbs_grams"] as? Double ?? (args["carbs_grams"] as? Int).map(Double.init),
              let fat = args["fat_grams"] as? Double ?? (args["fat_grams"] as? Int).map(Double.init) else {
            return .dataResponse(FunctionResult(
                name: "suggest_food_log",
                response: ["error": "Missing required parameters"]
            ))
        }

        let fiber = args["fiber_grams"] as? Double ?? (args["fiber_grams"] as? Int).map(Double.init)

        let entry = SuggestedFoodEntry(
            name: name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            servingSize: args["serving_size"] as? String,
            emoji: args["emoji"] as? String,
            loggedAtTime: args["logged_at_time"] as? String
        )

        return .suggestedFood(entry)
    }

    func executeEditFoodEntry(_ args: [String: Any]) -> ExecutionResult {
        guard let entryIdString = args["entry_id"] as? String,
              let entryId = UUID(uuidString: entryIdString) else {
            return .dataResponse(FunctionResult(
                name: "edit_food_entry",
                response: ["error": "Invalid or missing entry_id"]
            ))
        }

        // Find the entry
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.id == entryId }
        )

        guard let entry = try? modelContext.fetch(descriptor).first else {
            return .dataResponse(FunctionResult(
                name: "edit_food_entry",
                response: ["error": "Food entry not found"]
            ))
        }

        // Apply updates
        var changes: [String] = []

        if let newName = args["name"] as? String {
            entry.name = newName
            changes.append("name")
        }
        if let newCalories = args["calories"] as? Int {
            entry.calories = newCalories
            changes.append("calories")
        }
        if let newProtein = args["protein_grams"] as? Double ?? (args["protein_grams"] as? Int).map(Double.init) {
            entry.proteinGrams = newProtein
            changes.append("protein")
        }
        if let newCarbs = args["carbs_grams"] as? Double ?? (args["carbs_grams"] as? Int).map(Double.init) {
            entry.carbsGrams = newCarbs
            changes.append("carbs")
        }
        if let newFat = args["fat_grams"] as? Double ?? (args["fat_grams"] as? Int).map(Double.init) {
            entry.fatGrams = newFat
            changes.append("fat")
        }

        try? modelContext.save()

        return .dataResponse(FunctionResult(
            name: "edit_food_entry",
            response: [
                "success": true,
                "updated_fields": changes,
                "entry": [
                    "id": entry.id.uuidString,
                    "name": entry.name,
                    "calories": entry.calories,
                    "protein": entry.proteinGrams,
                    "carbs": entry.carbsGrams,
                    "fat": entry.fatGrams
                ]
            ]
        ))
    }

    func executeGetFoodLog(_ args: [String: Any]) -> ExecutionResult {
        let calendar = Calendar.current
        let today = Date()

        // Determine date range based on parameters
        let (startDate, endDate, dateDescription) = determineDateRange(
            args: args,
            calendar: calendar,
            today: today
        )

        // Fetch entries for the date range
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
            sortBy: [SortDescriptor(\.loggedAt)]
        )

        let entries = (try? modelContext.fetch(descriptor)) ?? []

        // Calculate totals
        let totalCalories = entries.reduce(0) { $0 + $1.calories }
        let totalProtein = entries.reduce(0.0) { $0 + $1.proteinGrams }
        let totalCarbs = entries.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat = entries.reduce(0.0) { $0 + $1.fatGrams }

        // Get targets from profile
        let targetCalories = userProfile?.dailyCalorieGoal ?? 2000
        let targetProtein = userProfile?.dailyProteinGoal ?? 150
        let targetCarbs = userProfile?.dailyCarbsGoal ?? 200
        let targetFat = userProfile?.dailyFatGoal ?? 65

        // Format entries with date for multi-day ranges
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let formattedEntries = entries.map { entry -> [String: Any] in
            return [
                "id": entry.id.uuidString,
                "name": entry.name,
                "emoji": entry.displayEmoji,
                "calories": entry.calories,
                "protein": entry.proteinGrams,
                "carbs": entry.carbsGrams,
                "fat": entry.fatGrams,
                "date": dateFormatter.string(from: entry.loggedAt),
                "time": timeFormatter.string(from: entry.loggedAt)
            ]
        }

        // Calculate number of days in range
        let dayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1

        return .dataResponse(FunctionResult(
            name: "get_food_log",
            response: [
                "date_range": dateDescription,
                "day_count": dayCount,
                "entries": formattedEntries,
                "totals": [
                    "calories": totalCalories,
                    "protein": Int(totalProtein),
                    "carbs": Int(totalCarbs),
                    "fat": Int(totalFat)
                ],
                "daily_averages": dayCount > 1 ? [
                    "calories": totalCalories / dayCount,
                    "protein": Int(totalProtein) / dayCount,
                    "carbs": Int(totalCarbs) / dayCount,
                    "fat": Int(totalFat) / dayCount
                ] : nil as [String: Int]?,
                "targets": [
                    "calories": targetCalories,
                    "protein": targetProtein,
                    "carbs": targetCarbs,
                    "fat": targetFat
                ],
                "remaining": dayCount == 1 ? [
                    "calories": targetCalories - totalCalories,
                    "protein": targetProtein - Int(totalProtein),
                    "carbs": targetCarbs - Int(totalCarbs),
                    "fat": targetFat - Int(totalFat)
                ] : nil as [String: Int]?,
                "entry_count": entries.count
            ]
        ))
    }

    /// Determines the date range based on function arguments
    private func determineDateRange(
        args: [String: Any],
        calendar: Calendar,
        today: Date
    ) -> (startDate: Date, endDate: Date, description: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Option 1: Specific date provided
        if let dateString = args["date"] as? String,
           let specificDate = dateFormatter.date(from: dateString) {
            let startOfDay = calendar.startOfDay(for: specificDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            if rangeDays == 1 {
                return (startOfDay, endOfRange, dateString)
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(dateString) to \(endDateString)")
            }
        }

        // Option 2: Days back from today
        if let daysBack = args["days_back"] as? Int {
            let targetDate = calendar.date(byAdding: .day, value: -daysBack, to: today)!
            let startOfDay = calendar.startOfDay(for: targetDate)
            let rangeDays = (args["range_days"] as? Int) ?? 1
            let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

            let startDateString = dateFormatter.string(from: startOfDay)
            if rangeDays == 1 {
                let dayName = daysBack == 1 ? "yesterday" : "\(daysBack) days ago"
                return (startOfDay, endOfRange, "\(startDateString) (\(dayName))")
            } else {
                let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
                return (startOfDay, endOfRange, "\(startDateString) to \(endDateString)")
            }
        }

        // Default: Today
        let startOfDay = calendar.startOfDay(for: today)
        let rangeDays = (args["range_days"] as? Int) ?? 1
        let endOfRange = calendar.date(byAdding: .day, value: rangeDays, to: startOfDay)!

        if rangeDays == 1 {
            return (startOfDay, endOfRange, "today")
        } else {
            let endDateString = dateFormatter.string(from: calendar.date(byAdding: .day, value: rangeDays - 1, to: startOfDay)!)
            return (startOfDay, endOfRange, "today to \(endDateString)")
        }
    }
}
