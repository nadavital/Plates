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
        let sugar = args["sugar_grams"] as? Double ?? (args["sugar_grams"] as? Int).map(Double.init)
        let components = parseSuggestedFoodComponents(args["components"])

        let entry = SuggestedFoodEntry(
            name: name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            sugarGrams: sugar,
            servingSize: args["serving_size"] as? String,
            emoji: args["emoji"] as? String,
            loggedAtDateString: args["logged_at_date"] as? String,
            loggedAtTime: args["logged_at_time"] as? String,
            components: components,
            mealKind: args["meal_kind"] as? String,
            notes: args["notes"] as? String,
            confidence: args["confidence"] as? String,
            schemaVersion: 2
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

    func executeEditFoodComponents(_ args: [String: Any]) -> ExecutionResult {
        let resolution = resolveFoodEntryForEdit(args)

        switch resolution {
        case .resolved(let entry):
            return buildFoodComponentEditResult(args, entry: entry)

        case .clarification(let message):
            return .directMessage(message)

        case .error(let error):
            return .dataResponse(FunctionResult(
                name: "edit_food_components",
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
        if let newSugar = args["sugar_grams"] as? Double ?? (args["sugar_grams"] as? Int).map(Double.init) {
            let oldSugar = entry.sugarGrams ?? 0
            if Int(newSugar) != Int(oldSugar) {
                fieldChanges.append(SuggestedFoodEdit.FieldChange(
                    field: "Sugar",
                    fieldKey: "sugarGrams",
                    oldValue: "\(Int(oldSugar))g",
                    newValue: "\(Int(newSugar))g",
                    newNumericValue: newSugar,
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
                    "fat": entry.fatGrams,
                    "sugar": entry.sugarGrams as Any
                ]
            ]
        ))
    }

    private func buildFoodComponentEditResult(_ args: [String: Any], entry: FoodEntry) -> ExecutionResult {
        guard let rawOperations = args["operations"] as? [[String: Any]], !rawOperations.isEmpty else {
            return .dataResponse(FunctionResult(
                name: "edit_food_components",
                response: ["error": "Missing operations"]
            ))
        }

        entry.bootstrapLoggedComponentsIfNeeded()
        var workingComponents = entry.loggedComponents
        let beforeTotals = nutritionSnapshot(for: workingComponents)
        var previews: [SuggestedFoodComponentEdit.Operation] = []

        for (index, rawOperation) in rawOperations.enumerated() {
            let typeRaw = (rawOperation["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard let typeRaw,
                  let operationType = SuggestedFoodComponentEdit.Operation.OperationType(rawValue: typeRaw) else {
                return .dataResponse(FunctionResult(
                    name: "edit_food_components",
                    response: ["error": "Invalid operation type at index \(index)"]
                ))
            }

            switch operationType {
            case .remove:
                switch resolveLoggedComponent(in: workingComponents, operation: rawOperation) {
                case .clarification(let message):
                    return .directMessage(message)
                case .error(let error):
                    return .dataResponse(FunctionResult(name: "edit_food_components", response: ["error": error]))
                case .resolved(let matchIndex):
                    let component = workingComponents[matchIndex]
                    guard component.status != .removed || component.fractionOfOriginal > 0 else { continue }
                    workingComponents[matchIndex].status = .removed
                    workingComponents[matchIndex].fractionOfOriginal = 0
                    previews.append(SuggestedFoodComponentEdit.Operation(
                        id: "remove-\(index)-\(component.id)",
                        type: .remove,
                        componentId: component.id,
                        componentName: component.displayName,
                        fractionOfOriginal: 0,
                        componentPayload: nil,
                        summary: "Remove \(component.displayName)"
                    ))
                }

            case .restore:
                switch resolveLoggedComponent(in: workingComponents, operation: rawOperation) {
                case .clarification(let message):
                    return .directMessage(message)
                case .error(let error):
                    return .dataResponse(FunctionResult(name: "edit_food_components", response: ["error": error]))
                case .resolved(let matchIndex):
                    let component = workingComponents[matchIndex]
                    guard component.status != .active || component.fractionOfOriginal != 1 else { continue }
                    workingComponents[matchIndex].status = .active
                    workingComponents[matchIndex].fractionOfOriginal = max(component.fractionOfOriginal, 1)
                    previews.append(SuggestedFoodComponentEdit.Operation(
                        id: "restore-\(index)-\(component.id)",
                        type: .restore,
                        componentId: component.id,
                        componentName: component.displayName,
                        fractionOfOriginal: workingComponents[matchIndex].fractionOfOriginal,
                        componentPayload: nil,
                        summary: "Restore \(component.displayName)"
                    ))
                }

            case .setFraction:
                let fraction = rawOperation["fraction_of_original"] as? Double ??
                    (rawOperation["fraction_of_original"] as? Int).map(Double.init)
                guard let fraction, fraction >= 0 else {
                    return .dataResponse(FunctionResult(
                        name: "edit_food_components",
                        response: ["error": "set_fraction requires a non-negative fraction_of_original"]
                    ))
                }

                switch resolveLoggedComponent(in: workingComponents, operation: rawOperation) {
                case .clarification(let message):
                    return .directMessage(message)
                case .error(let error):
                    return .dataResponse(FunctionResult(name: "edit_food_components", response: ["error": error]))
                case .resolved(let matchIndex):
                    let component = workingComponents[matchIndex]
                    guard component.fractionOfOriginal != fraction || component.status != (fraction == 0 ? .removed : .active) else {
                        continue
                    }
                    workingComponents[matchIndex].fractionOfOriginal = fraction
                    workingComponents[matchIndex].status = fraction == 0 ? .removed : .active
                    previews.append(SuggestedFoodComponentEdit.Operation(
                        id: "fraction-\(index)-\(component.id)",
                        type: .setFraction,
                        componentId: component.id,
                        componentName: component.displayName,
                        fractionOfOriginal: fraction,
                        componentPayload: nil,
                        summary: "\(component.displayName) at \(Int((fraction * 100).rounded()))% of the original portion"
                    ))
                }

            case .add:
                guard let componentPayload = buildLoggedComponentPayload(from: rawOperation) else {
                    return .dataResponse(FunctionResult(
                        name: "edit_food_components",
                        response: ["error": "add requires display_name, calories, protein_grams, carbs_grams, and fat_grams"]
                    ))
                }
                workingComponents.append(componentPayload)
                previews.append(SuggestedFoodComponentEdit.Operation(
                    id: "add-\(index)-\(componentPayload.id)",
                    type: .add,
                    componentId: componentPayload.id,
                    componentName: componentPayload.displayName,
                    fractionOfOriginal: componentPayload.fractionOfOriginal,
                    componentPayload: componentPayload,
                    summary: "Add \(componentPayload.displayName)"
                ))

            case .update:
                switch resolveLoggedComponent(in: workingComponents, operation: rawOperation) {
                case .clarification(let message):
                    return .directMessage(message)
                case .error(let error):
                    return .dataResponse(FunctionResult(name: "edit_food_components", response: ["error": error]))
                case .resolved(let matchIndex):
                    let existing = workingComponents[matchIndex]
                    guard let updated = buildLoggedComponentPayload(from: rawOperation, existing: existing) else {
                        return .dataResponse(FunctionResult(
                            name: "edit_food_components",
                            response: ["error": "update requires a component reference plus fields to change"]
                        ))
                    }
                    guard updated != existing else { continue }
                    workingComponents[matchIndex] = updated
                    previews.append(SuggestedFoodComponentEdit.Operation(
                        id: "update-\(index)-\(updated.id)",
                        type: .update,
                        componentId: updated.id,
                        componentName: updated.displayName,
                        fractionOfOriginal: updated.fractionOfOriginal,
                        componentPayload: updated,
                        summary: "Update \(existing.displayName) to \(updated.displayName)"
                    ))
                }
            }
        }

        guard workingComponents != entry.loggedComponents else {
            return .dataResponse(FunctionResult(
                name: "edit_food_components",
                response: ["success": true, "message": "No component changes needed"]
            ))
        }

        let afterTotals = nutritionSnapshot(for: workingComponents)
        let suggestion = SuggestedFoodComponentEdit(
            entryId: entry.id,
            name: entry.name,
            emoji: entry.emoji,
            operations: previews,
            beforeTotals: beforeTotals,
            afterTotals: afterTotals
        )
        return .suggestedFoodComponentEdit(suggestion)
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
        let includeComponents = args["include_components"] as? Bool ?? false

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
            var payload: [String: Any] = [
                "id": entry.id.uuidString,
                "name": entry.name,
                "emoji": entry.displayEmoji,
                "calories": entry.calories,
                "protein": entry.proteinGrams,
                "carbs": entry.carbsGrams,
                "fat": entry.fatGrams,
                "fiber": entry.fiberGrams as Any,
                "sugar": entry.sugarGrams as Any,
                "serving_size": entry.servingSize as Any,
                "meal_type": entry.mealType,
                "date": dateFormatter.string(from: entry.loggedAt),
                "time": timeFormatter.string(from: entry.loggedAt)
            ]

            if includeComponents {
                entry.bootstrapLoggedComponentsIfNeeded()
                payload["has_structured_components"] = !entry.loggedComponents.isEmpty
                payload["component_count"] = entry.loggedComponents.count
                payload["components"] = entry.loggedComponents.map { component in
                    [
                        "id": component.id,
                        "original_component_id": component.originalComponentID as Any,
                        "display_name": component.displayName,
                        "role": component.role.rawValue,
                        "quantity": component.quantity as Any,
                        "unit": component.unit as Any,
                        "calories": Int(component.effectiveCalories.rounded()),
                        "protein_grams": component.effectiveProteinGrams,
                        "carbs_grams": component.effectiveCarbsGrams,
                        "fat_grams": component.effectiveFatGrams,
                        "fiber_grams": component.effectiveFiberGrams as Any,
                        "sugar_grams": component.effectiveSugarGrams as Any,
                        "fraction_of_original": component.fractionOfOriginal,
                        "status": component.status.rawValue,
                        "source": component.source.rawValue
                    ] as [String: Any]
                }
            }

            return payload
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

    private enum LoggedComponentResolution {
        case resolved(Int)
        case clarification(String)
        case error(String)
    }

    private func resolveLoggedComponent(in components: [LoggedFoodComponent], operation: [String: Any]) -> LoggedComponentResolution {
        if let componentId = (operation["component_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !componentId.isEmpty {
            if let index = components.firstIndex(where: { $0.id == componentId }) {
                return .resolved(index)
            }
            return .error("Component not found")
        }

        guard let componentName = (operation["component_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !componentName.isEmpty else {
            return .error("Missing component reference")
        }

        let normalizedTarget = normalizedFoodReference(componentName)
        let exactMatches = components.enumerated().filter { _, component in
            normalizedFoodReference(component.displayName) == normalizedTarget ||
            component.normalizedName == normalizedTarget
        }
        if exactMatches.count == 1, let match = exactMatches.first {
            return .resolved(match.offset)
        }

        let fuzzyMatches = components.enumerated().filter { _, component in
            let normalizedName = normalizedFoodReference(component.displayName)
            return normalizedName.contains(normalizedTarget) || normalizedTarget.contains(normalizedName)
        }
        if fuzzyMatches.count == 1, let match = fuzzyMatches.first {
            return .resolved(match.offset)
        }

        let matches = exactMatches.isEmpty ? fuzzyMatches : exactMatches
        guard !matches.isEmpty else {
            return .clarification("I couldn't find that component in the meal. Tell me the exact part you want to change and I'll update it.")
        }

        let options = matches.prefix(3).map { $0.element.displayName }.joined(separator: ", ")
        return .clarification("I found multiple possible meal components: \(options). Which one should I change?")
    }

    private func nutritionSnapshot(for components: [LoggedFoodComponent]) -> SuggestedFoodComponentEdit.NutritionSnapshot {
        let activeComponents = components.filter(\.isActive)
        let calories = Int(activeComponents.reduce(0.0) { $0 + $1.effectiveCalories }.rounded())
        let protein = activeComponents.reduce(0.0) { $0 + $1.effectiveProteinGrams }
        let carbs = activeComponents.reduce(0.0) { $0 + $1.effectiveCarbsGrams }
        let fat = activeComponents.reduce(0.0) { $0 + $1.effectiveFatGrams }
        let fiber = activeComponents.reduce(0.0) { $0 + ($1.effectiveFiberGrams ?? 0) }
        let sugar = activeComponents.reduce(0.0) { $0 + ($1.effectiveSugarGrams ?? 0) }

        return SuggestedFoodComponentEdit.NutritionSnapshot(
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber > 0 ? fiber : nil,
            sugarGrams: sugar > 0 ? sugar : nil
        )
    }

    private func parseSuggestedFoodComponents(_ value: Any?) -> [SuggestedFoodComponent] {
        guard let rawComponents = value as? [[String: Any]] else { return [] }
        return rawComponents.compactMap { rawComponent in
            guard let displayName = rawComponent["display_name"] as? String ?? rawComponent["displayName"] as? String,
                  let calories = rawComponent["calories"] as? Int,
                  let protein = rawComponent["protein_grams"] as? Double ?? (rawComponent["protein_grams"] as? Int).map(Double.init),
                  let carbs = rawComponent["carbs_grams"] as? Double ?? (rawComponent["carbs_grams"] as? Int).map(Double.init),
                  let fat = rawComponent["fat_grams"] as? Double ?? (rawComponent["fat_grams"] as? Int).map(Double.init) else {
                return nil
            }

            return SuggestedFoodComponent(
                id: rawComponent["id"] as? String ?? UUID().uuidString,
                displayName: displayName,
                role: rawComponent["role"] as? String,
                quantity: rawComponent["quantity"] as? Double ?? (rawComponent["quantity"] as? Int).map(Double.init),
                unit: rawComponent["unit"] as? String,
                calories: calories,
                proteinGrams: protein,
                carbsGrams: carbs,
                fatGrams: fat,
                fiberGrams: rawComponent["fiber_grams"] as? Double ?? (rawComponent["fiber_grams"] as? Int).map(Double.init),
                sugarGrams: rawComponent["sugar_grams"] as? Double ?? (rawComponent["sugar_grams"] as? Int).map(Double.init),
                confidence: rawComponent["confidence"] as? String
            )
        }
    }

    private func buildLoggedComponentPayload(from rawOperation: [String: Any], existing: LoggedFoodComponent? = nil) -> LoggedFoodComponent? {
        let displayName = (rawOperation["display_name"] as? String ?? existing?.displayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let displayName, !displayName.isEmpty else { return nil }

        let calories = rawOperation["calories"] as? Int ?? existing?.calories
        let protein = rawOperation["protein_grams"] as? Double ?? (rawOperation["protein_grams"] as? Int).map(Double.init) ?? existing?.proteinGrams
        let carbs = rawOperation["carbs_grams"] as? Double ?? (rawOperation["carbs_grams"] as? Int).map(Double.init) ?? existing?.carbsGrams
        let fat = rawOperation["fat_grams"] as? Double ?? (rawOperation["fat_grams"] as? Int).map(Double.init) ?? existing?.fatGrams

        guard let calories, let protein, let carbs, let fat else { return nil }

        let normalizedName = normalizedFoodReference(displayName)
        let explicitId = (rawOperation["component_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let componentId = explicitId?.isEmpty == false
            ? explicitId!
            : existing?.id ?? "\(normalizedName)-\(UUID().uuidString.lowercased())"
        let fraction = rawOperation["fraction_of_original"] as? Double ??
            (rawOperation["fraction_of_original"] as? Int).map(Double.init) ??
            existing?.fractionOfOriginal ?? 1

        return LoggedFoodComponent(
            id: componentId,
            originalComponentID: existing?.originalComponentID ?? componentId,
            displayName: displayName,
            normalizedName: normalizedName,
            role: FoodComponentRole(rawValue: (rawOperation["role"] as? String)?.lowercased() ?? "") ?? existing?.role ?? .other,
            quantity: rawOperation["quantity"] as? Double ?? (rawOperation["quantity"] as? Int).map(Double.init) ?? existing?.quantity,
            unit: rawOperation["unit"] as? String ?? existing?.unit,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: rawOperation["fiber_grams"] as? Double ?? (rawOperation["fiber_grams"] as? Int).map(Double.init) ?? existing?.fiberGrams,
            sugarGrams: rawOperation["sugar_grams"] as? Double ?? (rawOperation["sugar_grams"] as? Int).map(Double.init) ?? existing?.sugarGrams,
            preparation: existing?.preparation,
            confidence: FoodAnalysisConfidence(rawValue: (rawOperation["confidence"] as? String)?.lowercased() ?? "") ?? existing?.confidence,
            source: existing?.source ?? .user,
            fractionOfOriginal: max(fraction, 0),
            status: max(fraction, 0) == 0 ? .removed : (existing?.status ?? .active)
        )
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
