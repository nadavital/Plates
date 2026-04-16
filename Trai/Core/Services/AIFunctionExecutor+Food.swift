//
//  AIFunctionExecutor+Food.swift
//  Trai
//
//  Food-related function execution
//

import Foundation
import SwiftData

extension AIFunctionExecutor {

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
            loggedAtDateString: args["logged_at_date"] as? String,
            loggedAtTime: args["logged_at_time"] as? String
        )

        return .suggestedFood(entry)
    }

    func executeEditFoodEntry(_ args: [String: Any]) -> ExecutionResult {
        let resolution = resolveFoodEntryForEdit(args)

        switch resolution {
        case .resolved(let entry):
            return buildFoodEditResult(args, entry: entry)

        case .clarification(let message):
            return .directMessage(message)

        case .error(let error):
            return .dataResponse(FunctionResult(
                name: "edit_food_entry",
                response: ["error": error]
            ))
        }
    }

    private func buildFoodEditResult(_ args: [String: Any], entry: FoodEntry) -> ExecutionResult {
        // Collect proposed changes WITHOUT applying them
        var fieldChanges: [SuggestedFoodEdit.FieldChange] = []

        let trimmedName = (
            args["name"] as? String ??
            args["title"] as? String ??
            args["mealTitle"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let newName = trimmedName, !newName.isEmpty, newName != entry.name {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Title",
                fieldKey: "name",
                oldValue: entry.name,
                newValue: newName,
                newNumericValue: nil,
                newStringValue: newName
            ))
        }

        let trimmedServingSize = (args["serving_size"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let newServingSize = trimmedServingSize, newServingSize != (entry.servingSize ?? "") {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Serving Size",
                fieldKey: "servingSize",
                oldValue: entry.servingSize ?? "Not set",
                newValue: newServingSize.isEmpty ? "Not set" : newServingSize,
                newNumericValue: nil,
                newStringValue: newServingSize
            ))
        }

        let mealTypeInput = (args["meal_type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        if let requestedMealType = mealTypeInput,
           FoodEntry.MealType(rawValue: requestedMealType) != nil,
           requestedMealType != entry.mealType {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Meal Type",
                fieldKey: "mealType",
                oldValue: entry.meal.displayName,
                newValue: FoodEntry.MealType(rawValue: requestedMealType)?.displayName ?? requestedMealType.capitalized,
                newNumericValue: nil,
                newStringValue: requestedMealType
            ))
        }

        let trimmedNotes = (args["notes"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let notes = trimmedNotes, notes != (entry.userDescription ?? "") {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Notes",
                fieldKey: "notes",
                oldValue: entry.userDescription ?? "Not set",
                newValue: notes.isEmpty ? "Not set" : notes,
                newNumericValue: nil,
                newStringValue: notes
            ))
        }

        let trimmedLoggedAtTime = (args["logged_at_time"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let loggedAtTime = trimmedLoggedAtTime, !loggedAtTime.isEmpty {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = "HH:mm"

            if let timeValue = timeFormatter.date(from: loggedAtTime) {
                let clockComponents = Calendar.current.dateComponents([.hour, .minute], from: timeValue)
                guard let hour = clockComponents.hour, let minute = clockComponents.minute else {
                    return .dataResponse(FunctionResult(
                        name: "edit_food_entry",
                        response: ["error": "Invalid logged_at_time format. Use HH:mm."]
                    ))
                }

                var components = Calendar.current.dateComponents([.year, .month, .day], from: entry.loggedAt)
                components.hour = hour
                components.minute = minute
                components.second = 0

                if Calendar.current.date(from: components) != nil {
                    let oldTimeValue = timeFormatter.string(from: entry.loggedAt)
                    if oldTimeValue != loggedAtTime {
                        fieldChanges.append(SuggestedFoodEdit.FieldChange(
                            field: "Logged Time",
                            fieldKey: "loggedAt",
                            oldValue: oldTimeValue,
                            newValue: loggedAtTime,
                            newNumericValue: nil,
                            newStringValue: loggedAtTime
                        ))
                    }
                }
            }
        }

        if let newCalories = args["calories"] as? Int, newCalories != entry.calories {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Calories",
                fieldKey: "calories",
                oldValue: "\(entry.calories)",
                newValue: "\(newCalories)",
                newNumericValue: Double(newCalories),
                newStringValue: nil
            ))
        }
        if let newProtein = args["protein_grams"] as? Double ?? (args["protein_grams"] as? Int).map(Double.init),
           Int(newProtein) != Int(entry.proteinGrams) {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Protein",
                fieldKey: "proteinGrams",
                oldValue: "\(Int(entry.proteinGrams))g",
                newValue: "\(Int(newProtein))g",
                newNumericValue: newProtein,
                newStringValue: nil
            ))
        }
        if let newCarbs = args["carbs_grams"] as? Double ?? (args["carbs_grams"] as? Int).map(Double.init),
           Int(newCarbs) != Int(entry.carbsGrams) {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Carbs",
                fieldKey: "carbsGrams",
                oldValue: "\(Int(entry.carbsGrams))g",
                newValue: "\(Int(newCarbs))g",
                newNumericValue: newCarbs,
                newStringValue: nil
            ))
        }
        if let newFat = args["fat_grams"] as? Double ?? (args["fat_grams"] as? Int).map(Double.init),
           Int(newFat) != Int(entry.fatGrams) {
            fieldChanges.append(SuggestedFoodEdit.FieldChange(
                field: "Fat",
                fieldKey: "fatGrams",
                oldValue: "\(Int(entry.fatGrams))g",
                newValue: "\(Int(newFat))g",
                newNumericValue: newFat,
                newStringValue: nil
            ))
        }
        if let newFiber = args["fiber_grams"] as? Double ?? (args["fiber_grams"] as? Int).map(Double.init) {
            let oldFiber = entry.fiberGrams ?? 0
            if Int(newFiber) != Int(oldFiber) {
                fieldChanges.append(SuggestedFoodEdit.FieldChange(
                    field: "Fiber",
                    fieldKey: "fiberGrams",
                    oldValue: "\(Int(oldFiber))g",
                    newValue: "\(Int(newFiber))g",
                    newNumericValue: newFiber,
                    newStringValue: nil
                ))
            }
        }

        // If there are changes, return a suggestion for user to confirm
        if !fieldChanges.isEmpty {
            let suggestion = SuggestedFoodEdit(
                entryId: entry.id,
                name: entry.name,
                emoji: entry.emoji,
                changes: fieldChanges
            )
            return .suggestedFoodEdit(suggestion)
        }

        // No actual changes needed
        return .dataResponse(FunctionResult(
            name: "edit_food_entry",
            response: [
                "success": true,
                "message": "No changes needed - values already match",
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

    private enum FoodEntryResolution {
        case resolved(FoodEntry)
        case clarification(String)
        case error(String)
    }

    private func resolveFoodEntryForEdit(_ args: [String: Any]) -> FoodEntryResolution {
        if let entryIdString = args["entry_id"] as? String {
            guard let entryId = UUID(uuidString: entryIdString) else {
                return .error("Invalid entry_id")
            }

            let descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.id == entryId }
            )

            guard let entry = try? modelContext.fetch(descriptor).first else {
                return .error("Food entry not found")
            }

            return .resolved(entry)
        }

        let targetName = (
            args["target_name"] as? String ??
            args["meal_name"] as? String ??
            args["entry_name"] as? String ??
            args["food_name"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let targetDateString = (
            args["target_logged_at_date"] as? String ??
            args["logged_at_date"] as? String ??
            args["date"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let targetTimeString = (
            args["target_logged_at_time"] as? String ??
            args["entry_time"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let targetMealType = (
            args["target_meal_type"] as? String ??
            args["entry_meal_type"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        if let targetDateString, !targetDateString.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard formatter.date(from: targetDateString) != nil else {
                return .error("Invalid target_logged_at_date format. Use YYYY-MM-DD.")
            }
        }

        if let targetTimeString, !targetTimeString.isEmpty,
           minutesSinceMidnight(from: targetTimeString) == nil {
            return .error("Invalid target_logged_at_time format. Use HH:mm.")
        }

        let hasNaturalReference =
            (targetName?.isEmpty == false) ||
            (targetDateString?.isEmpty == false) ||
            (targetTimeString?.isEmpty == false) ||
            (targetMealType?.isEmpty == false)

        guard hasNaturalReference else {
            return .error("Missing entry_id or target meal reference")
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let today = Date()
        let dateArgs: [String: Any]
        if let targetDateString, !targetDateString.isEmpty {
            dateArgs = ["date": targetDateString, "range_days": 1]
        } else {
            dateArgs = ["days_back": 0, "range_days": 1]
        }
        let (startDate, endDate, _) = determineDateRange(args: dateArgs, calendar: calendar, today: today)

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
            sortBy: [SortDescriptor(\.loggedAt)]
        )

        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        guard !allEntries.isEmpty else {
            return directEditErrorForMissingEntries(targetDateString: targetDateString)
        }

        let mealTypeFiltered: [FoodEntry]
        if let targetMealType,
           let requestedMealType = FoodEntry.MealType(rawValue: targetMealType) {
            mealTypeFiltered = allEntries.filter { $0.meal == requestedMealType }
        } else {
            mealTypeFiltered = allEntries
        }

        guard !mealTypeFiltered.isEmpty else {
            return .clarification("I couldn't find a matching logged meal with that meal type. Tell me the meal name or time and I'll update it.")
        }

        let strictNameMatches = filterEntriesByName(mealTypeFiltered, targetName: targetName)
        let hasAdditionalDisambiguator =
            (targetDateString?.isEmpty == false) ||
            (targetTimeString?.isEmpty == false) ||
            (targetMealType?.isEmpty == false)
        let nameFiltered = strictNameMatches.isEmpty && hasAdditionalDisambiguator
            ? mealTypeFiltered
            : strictNameMatches
        let timeFiltered = filterEntriesByTime(nameFiltered, targetTimeString: targetTimeString)

        if timeFiltered.count == 1 {
            return .resolved(timeFiltered[0])
        }

        let scored = scoreEntriesForEditResolution(
            entries: timeFiltered,
            targetName: targetName,
            targetTimeString: targetTimeString,
            targetMealType: targetMealType
        )

        guard let topMatch = scored.first else {
            return .clarification("I couldn't tell which logged meal you wanted to edit. Tell me the meal name, time, or day and I'll update it.")
        }

        let topMatches = scored.filter { $0.score == topMatch.score }
        if topMatches.count == 1,
           (scored.count == 1 || topMatch.score - scored[1].score >= 2) {
            return .resolved(topMatch.entry)
        }

        let options = Array(topMatches.prefix(3)).map { formatEntryReference($0.entry) }.joined(separator: ", ")
        return .clarification("I found multiple possible meals. Did you mean \(options)?")
    }

    private func filterEntriesByName(_ entries: [FoodEntry], targetName: String?) -> [FoodEntry] {
        guard let rawTargetName = targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTargetName.isEmpty else {
            return entries
        }

        let normalizedTarget = normalizedFoodReference(rawTargetName)
        let exactMatches = entries.filter { normalizedFoodReference($0.name) == normalizedTarget }
        if !exactMatches.isEmpty {
            return exactMatches
        }

        let tokenMatches = entries.filter {
            let entryName = normalizedFoodReference($0.name)
            return entryName.contains(normalizedTarget) || normalizedTarget.contains(entryName)
        }
        if !tokenMatches.isEmpty {
            return tokenMatches
        }

        return []
    }

    private func filterEntriesByTime(_ entries: [FoodEntry], targetTimeString: String?) -> [FoodEntry] {
        guard let targetTimeString = targetTimeString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetTimeString.isEmpty,
              let targetMinutes = minutesSinceMidnight(from: targetTimeString) else {
            return entries
        }

        let withinNinetyMinutes = entries.filter { entry in
            abs(minutesSinceMidnight(from: entry.loggedAt) - targetMinutes) <= 90
        }

        return withinNinetyMinutes
    }

    private func scoreEntriesForEditResolution(
        entries: [FoodEntry],
        targetName: String?,
        targetTimeString: String?,
        targetMealType: String?
    ) -> [(entry: FoodEntry, score: Int)] {
        let normalizedTargetName = targetName.map(normalizedFoodReference)
        let targetMinutes = targetTimeString.flatMap(minutesSinceMidnight(from:))

        return entries.map { entry in
            var score = 0

            if let normalizedTargetName, !normalizedTargetName.isEmpty {
                let entryName = normalizedFoodReference(entry.name)
                if entryName == normalizedTargetName {
                    score += 6
                } else if entryName.contains(normalizedTargetName) || normalizedTargetName.contains(entryName) {
                    score += 4
                }
            }

            if let targetMealType,
               let requestedMealType = FoodEntry.MealType(rawValue: targetMealType),
               entry.meal == requestedMealType {
                score += 2
            }

            if let targetMinutes {
                let delta = abs(minutesSinceMidnight(from: entry.loggedAt) - targetMinutes)
                switch delta {
                case 0...10:
                    score += 5
                case 11...30:
                    score += 4
                case 31...60:
                    score += 3
                case 61...90:
                    score += 2
                default:
                    break
                }
            }

            return (entry: entry, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.entry.loggedAt < rhs.entry.loggedAt
        }
    }

    private func normalizedFoodReference(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func minutesSinceMidnight(from timeString: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: timeString) else { return nil }
        return minutesSinceMidnight(from: date)
    }

    private func minutesSinceMidnight(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func formatEntryReference(_ entry: FoodEntry) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        return "\(timeFormatter.string(from: entry.loggedAt)) \(entry.name)"
    }

    private func directEditErrorForMissingEntries(targetDateString: String?) -> FoodEntryResolution {
        if let targetDateString, !targetDateString.isEmpty {
            return .clarification("I couldn't find any logged meals on \(targetDateString). Tell me a different day or the meal details and I'll help update it.")
        }
        return .clarification("I couldn't find any logged meals for today. Tell me the meal and day you want to edit and I'll help update it.")
    }

    func executeGetFoodLog(_ args: [String: Any]) -> ExecutionResult {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let today = Date()

        // Log the args for debugging
        let argsDescription = args.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        print("📊 get_food_log args: [\(argsDescription)]")

        // Convert period to days_back/range_days if provided
        var effectiveArgs = args
        if let period = args["period"] as? String {
            let periodConfig = periodToDateRange(period, calendar: calendar, today: today)
            effectiveArgs["days_back"] = periodConfig.daysBack
            effectiveArgs["range_days"] = periodConfig.rangeDays
        }

        // Determine date range based on parameters
        let (startDate, endDate, dateDescription) = determineDateRange(
            args: effectiveArgs,
            calendar: calendar,
            today: today
        )

        print("📊 Date range: \(startDate) to \(endDate) (\(dateDescription))")

        // Fetch entries for the date range
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
            sortBy: [SortDescriptor(\.loggedAt)]
        )

        let entries = (try? modelContext.fetch(descriptor)) ?? []
        print("📊 Found \(entries.count) entries")

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

    /// Converts a period string to days_back and range_days
    private func periodToDateRange(_ period: String, calendar: Calendar, today: Date) -> (daysBack: Int, rangeDays: Int) {
        switch period {
        case "today":
            return (0, 1)
        case "yesterday":
            return (1, 1)
        case "this_week":
            // Days since start of week (Sunday = 1 in US calendar)
            let weekday = calendar.component(.weekday, from: today)
            let daysSinceWeekStart = weekday - calendar.firstWeekday
            let adjustedDays = daysSinceWeekStart >= 0 ? daysSinceWeekStart : daysSinceWeekStart + 7
            return (adjustedDays, adjustedDays + 1)
        case "last_week":
            let weekday = calendar.component(.weekday, from: today)
            let daysSinceWeekStart = weekday - calendar.firstWeekday
            let adjustedDays = daysSinceWeekStart >= 0 ? daysSinceWeekStart : daysSinceWeekStart + 7
            return (adjustedDays + 7, 7)
        case "this_month":
            let day = calendar.component(.day, from: today)
            return (day - 1, day)
        case "last_month":
            // Get the first day of this month
            let components = calendar.dateComponents([.year, .month], from: today)
            guard let firstOfMonth = calendar.date(from: components),
                  let lastMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
                  let daysInLastMonth = calendar.range(of: .day, in: .month, for: lastMonth)?.count else {
                return (30, 30) // Fallback
            }
            let day = calendar.component(.day, from: today)
            return (day - 1 + daysInLastMonth, daysInLastMonth)
        case "past_3_days":
            // Last 3 days including today
            return (2, 3)
        case "past_7_days":
            // Last 7 days including today (full week)
            return (6, 7)
        case "past_14_days":
            // Last 14 days including today (two weeks)
            return (13, 14)
        default:
            return (0, 1) // Default to today
        }
    }
}
