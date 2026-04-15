//
//  AIFunctionExecutor+PlanWorkout.swift
//  Trai
//
//  Plan and workout function execution
//

import Foundation
import SwiftData

extension AIFunctionExecutor {

    // MARK: - Plan Functions

    func executeGetUserPlan() -> ExecutionResult {
        guard let profile = userProfile else {
            return .dataResponse(FunctionResult(
                name: "get_user_plan",
                response: ["error": "No user profile found"]
            ))
        }

        return .dataResponse(FunctionResult(
            name: "get_user_plan",
            response: [
                "goal": profile.goal.rawValue,
                "daily_targets": [
                    "calories": profile.dailyCalorieGoal,
                    "protein": profile.dailyProteinGoal,
                    "carbs": profile.dailyCarbsGoal,
                    "fat": profile.dailyFatGoal
                ],
                "activity_level": profile.activityLevel,
                "current_weight_kg": profile.currentWeightKg ?? 0,
                "target_weight_kg": profile.targetWeightKg ?? 0
            ]
        ))
    }

    func executeUpdateUserPlan(_ args: [String: Any]) -> ExecutionResult {
        let suggestion = PlanUpdateSuggestion(
            calories: args["calories"] as? Int,
            proteinGrams: args["protein_grams"] as? Int,
            carbsGrams: args["carbs_grams"] as? Int,
            fatGrams: args["fat_grams"] as? Int,
            goal: args["goal"] as? String,
            rationale: args["rationale"] as? String
        )

        return .suggestedPlanUpdate(suggestion)
    }

    // MARK: - Workout Functions

    func executeGetRecentWorkouts(_ args: [String: Any]) -> ExecutionResult {
        let calendar = Calendar.current
        let today = Date()
        let limit = args["limit"] as? Int ?? 10

        // Check if date range is specified
        let hasDateRange = args["date"] != nil || args["days_back"] != nil || args["range_days"] != nil

        var workoutSessions: [WorkoutSession] = []
        var liveWorkouts: [LiveWorkout] = []
        var dateDescription = "recent"

        if hasDateRange {
            let (startDate, endDate, description) = determineWorkoutDateRange(
                args: args,
                calendar: calendar,
                today: today
            )
            dateDescription = description

            // Fetch WorkoutSession entries
            let sessionDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            workoutSessions = (try? modelContext.fetch(sessionDescriptor)) ?? []

            // Fetch completed LiveWorkout entries (tracked in-app)
            let liveDescriptor = FetchDescriptor<LiveWorkout>(
                predicate: #Predicate { $0.completedAt != nil && $0.startedAt >= startDate && $0.startedAt < endDate },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            liveWorkouts = (try? modelContext.fetch(liveDescriptor)) ?? []
        } else {
            // Default: get recent workouts with limit
            let sessionDescriptor = FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            workoutSessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
            workoutSessions = Array(workoutSessions.prefix(limit))

            // Fetch completed LiveWorkouts
            let liveDescriptor = FetchDescriptor<LiveWorkout>(
                predicate: #Predicate { $0.completedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            liveWorkouts = (try? modelContext.fetch(liveDescriptor)) ?? []
            liveWorkouts = Array(liveWorkouts.prefix(limit))
        }

        let mergedHealthKitIDs = Set(liveWorkouts.compactMap(\.mergedHealthKitWorkoutID))
        if !mergedHealthKitIDs.isEmpty {
            workoutSessions = workoutSessions.filter { workout in
                guard let healthKitWorkoutID = workout.healthKitWorkoutID else { return true }
                return !mergedHealthKitIDs.contains(healthKitWorkoutID)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"

        // Keep sort date separate from the formatted date string so ordering is chronologically correct.
        var workoutsWithDate: [(sortDate: Date, payload: [String: Any])] = workoutSessions.map { workout in
            let trimmedNotes = workout.trimmedNotes
            return (
                sortDate: workout.loggedAt,
                payload: [
                    "id": workout.id.uuidString,
                    "name": workout.displayName,
                    "type": workout.inferredWorkoutMode.rawValue,
                    "display_type": workout.displayTypeName,
                    "date": dateFormatter.string(from: workout.loggedAt),
                    "duration_minutes": workout.durationMinutes ?? 0,
                    "sets": workout.sets,
                    "reps": workout.reps,
                    "weight_kg": workout.weightKg ?? 0,
                    "distance_meters": workout.distanceMeters ?? 0,
                    "average_heart_rate": workout.averageHeartRate ?? 0,
                    "tracked_in_app": false,
                    "source": workout.sourceIsHealthKit ? "apple_health" : "manual_session",
                    "notes": trimmedNotes.isEmpty ? "" : trimmedNotes
                ]
            )
        }

        // Format LiveWorkout entries with full exercise details
        for liveWorkout in liveWorkouts {
            let entries = liveWorkout.entries ?? []
            let sortedEntries = entries.sorted { $0.orderIndex < $1.orderIndex }

            // Build detailed exercise list
            var exercises: [[String: Any]] = []
            for entry in sortedEntries {
                let sets = entry.sets
                guard !sets.isEmpty else { continue }

                var exerciseData: [String: Any] = [
                    "name": entry.exerciseName,
                    "sets_count": sets.count,
                    "total_reps": entry.totalReps,
                    "best_weight_kg": sets.map(\.weightKg).max() ?? 0,
                    "total_volume_kg": entry.totalVolume
                ]

                // Include set-by-set breakdown
                exerciseData["sets_detail"] = sets.map { set -> [String: Any] in
                    [
                        "reps": set.reps,
                        "weight_kg": set.weightKg,
                        "is_warmup": set.isWarmup
                    ]
                }

                exercises.append(exerciseData)
            }

            var workoutData: [String: Any] = [
                "id": liveWorkout.id.uuidString,
                "name": liveWorkout.name,
                "type": liveWorkout.type.rawValue,
                "date": dateFormatter.string(from: liveWorkout.startedAt),
                "duration_minutes": Int(liveWorkout.duration / 60),
                "total_sets": liveWorkout.totalSets,
                "total_volume_kg": liveWorkout.totalVolume,
                "muscle_groups": liveWorkout.muscleGroups.map(\.displayName),
                "tracked_in_app": true,
                "source": "trai_live_workout",
                "notes": liveWorkout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            ]

            if !exercises.isEmpty {
                workoutData["exercises"] = exercises
            }

            workoutsWithDate.append((sortDate: liveWorkout.startedAt, payload: workoutData))
        }

        // Sort all workouts by actual date descending.
        workoutsWithDate.sort { $0.sortDate > $1.sortDate }

        // Date-range queries return the full range; recent-mode queries still honor the limit.
        let formattedWorkouts: [[String: Any]]
        if hasDateRange {
            formattedWorkouts = workoutsWithDate.map(\.payload)
        } else {
            formattedWorkouts = Array(workoutsWithDate.prefix(limit).map(\.payload))
        }

        return .dataResponse(FunctionResult(
            name: "get_recent_workouts",
            response: [
                "date_range": dateDescription,
                "workouts": formattedWorkouts,
                "count": formattedWorkouts.count
            ]
        ))
    }

    func executeReviseWorkoutPlan(_ args: [String: Any]) async -> ExecutionResult {
        guard let profile = userProfile else {
            return .directMessage("I couldn't find your profile, so I can't revise your workout plan yet.")
        }

        guard let currentPlan = pendingWorkoutPlan ?? profile.workoutPlan else {
            return .directMessage("You don't have a saved workout plan yet. We can create one from the workouts tab first, then I can revise it here anytime.")
        }

        let changeRequest = (args["change_request"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !changeRequest.isEmpty else {
            return .directMessage("Tell me what you want to change in your workout plan, and I’ll propose an update for you to review.")
        }

        let request = buildWorkoutPlanRevisionRequest(profile: profile)
        let service = AIService()

        do {
            let response = try await service.refineWorkoutPlan(
                currentPlan: currentPlan,
                request: request,
                userMessage: changeRequest,
                conversationHistory: []
            )

            if let plan = response.proposedPlan ?? response.updatedPlan {
                return .suggestedWorkoutPlanUpdate(
                    WorkoutPlanSuggestionEntry(
                        plan: plan,
                        message: response.message
                    )
                )
            }

            let fallbackMessage = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackMessage.isEmpty {
                return .directMessage(fallbackMessage)
            }

            return .directMessage("I reviewed your workout plan, but I'm not confident enough to suggest a concrete change yet.")
        } catch {
            return .directMessage("I hit a snag while revising your workout plan. Please try again in a moment.")
        }
    }

    private func buildWorkoutPlanRevisionRequest(profile: UserProfile) -> WorkoutPlanGenerationRequest {
        profile.buildWorkoutPlanRequest()
    }

    func executeGetWorkoutGoals(_ args: [String: Any]) -> ExecutionResult {
        let requestedStatus = (args["status"] as? String)?.lowercased() ?? "active"
        let descriptor = FetchDescriptor<WorkoutGoal>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let fetchedGoals = (try? modelContext.fetch(descriptor)) ?? []

        let filteredGoals = fetchedGoals.filter { goal in
            switch requestedStatus {
            case "all":
                return true
            case "completed":
                return goal.status == .completed
            case "paused":
                return goal.status == .paused
            default:
                return goal.status == .active
            }
        }

        let serializedGoals = filteredGoals.map { goal in
            [
                "id": goal.id.uuidString,
                "title": goal.trimmedTitle,
                "goal_kind": goal.goalKind.rawValue,
                "status": goal.status.rawValue,
                "workout_type": goal.linkedWorkoutType?.rawValue ?? "",
                "activity_name": goal.trimmedActivityName ?? "",
                "target_value": goal.targetValue as Any,
                "target_unit": goal.targetUnit,
                "period_unit": goal.periodUnit?.rawValue ?? "",
                "period_count": goal.periodCount as Any,
                "notes": goal.trimmedNotes,
                "target_date": goal.targetDate.map(formatDateForFunction) ?? "",
                "check_in_cadence_days": goal.checkInCadenceDays as Any,
                "updated_at": formatDateTimeForFunction(goal.updatedAt),
                "scope_summary": goal.scopeSummary,
                "tracking_summary": goal.trackingSummary ?? "",
                "horizon_summary": goal.horizonSummary ?? ""
            ]
        }

        return .dataResponse(FunctionResult(
            name: "get_workout_goals",
            response: [
                "goals": serializedGoals,
                "count": serializedGoals.count,
                "status_filter": requestedStatus
            ]
        ))
    }

    func executeCreateWorkoutGoal(_ args: [String: Any]) -> ExecutionResult {
        guard let rawTitle = args["title"] as? String else {
            return .dataResponse(FunctionResult(
                name: "create_workout_goal",
                response: ["error": "Missing title"]
            ))
        }

        guard let rawKind = args["goal_kind"] as? String,
              let goalKind = WorkoutGoal.GoalKind(rawValue: rawKind) else {
            return .dataResponse(FunctionResult(
                name: "create_workout_goal",
                response: ["error": "Missing or invalid goal_kind"]
            ))
        }

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return .dataResponse(FunctionResult(
                name: "create_workout_goal",
                response: ["error": "Title cannot be empty"]
            ))
        }

        let workoutType = (args["workout_type"] as? String).flatMap(WorkoutMode.init(rawValue:))
        let activityName = (args["activity_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetValue = numericDouble(from: args["target_value"])
        let targetUnit = (args["target_unit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let periodUnit = (args["period_unit"] as? String).flatMap(WorkoutGoal.PeriodUnit.init(rawValue:))
        let periodCount = numericInt(from: args["period_count"])
        let targetDate = parseDate(args["target_date"] as? String)
        let checkInCadenceDays = numericInt(from: args["check_in_cadence_days"])

        let goal = WorkoutGoal(
            title: title,
            goalKind: goalKind,
            linkedWorkoutType: workoutType,
            linkedActivityName: activityName?.isEmpty == false ? activityName : nil,
            targetValue: goalKind.supportsNumericTarget ? targetValue : nil,
            targetUnit: goalKind.supportsNumericTarget ? targetUnit : "",
            periodUnit: goalKind.usesPeriodTarget ? periodUnit : nil,
            periodCount: goalKind.usesPeriodTarget ? periodCount : nil,
            notes: notes,
            targetDate: targetDate,
            checkInCadenceDays: checkInCadenceDays
        )

        modelContext.insert(goal)
        try? modelContext.save()
        return .dataResponse(FunctionResult(
            name: "create_workout_goal",
            response: [
                "success": true,
                "goal": [
                    "id": goal.id.uuidString,
                    "title": goal.trimmedTitle,
                    "goal_kind": goal.goalKind.rawValue,
                    "status": goal.status.rawValue,
                    "workout_type": goal.linkedWorkoutType?.rawValue ?? "",
                    "activity_name": goal.trimmedActivityName ?? "",
                    "target_value": goal.targetValue as Any,
                    "target_unit": goal.targetUnit,
                    "period_unit": goal.periodUnit?.rawValue ?? "",
                    "period_count": goal.periodCount as Any,
                    "notes": goal.trimmedNotes,
                    "target_date": goal.targetDate.map(formatDateForFunction) ?? "",
                    "check_in_cadence_days": goal.checkInCadenceDays as Any
                ]
            ]
        ))
    }

    func executeUpdateWorkoutGoal(_ args: [String: Any]) -> ExecutionResult {
        guard let goalIdString = args["goal_id"] as? String,
              let goalId = UUID(uuidString: goalIdString) else {
            return .dataResponse(FunctionResult(
                name: "update_workout_goal",
                response: ["error": "Invalid or missing goal_id"]
            ))
        }

        let descriptor = FetchDescriptor<WorkoutGoal>(
            predicate: #Predicate { $0.id == goalId }
        )

        let matchingGoals = (try? modelContext.fetch(descriptor)) ?? []
        guard let goal = matchingGoals.first else {
            return .dataResponse(FunctionResult(
                name: "update_workout_goal",
                response: ["error": "Workout goal not found"]
            ))
        }

        if let rawTitle = args["title"] as? String {
            let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                goal.title = trimmed
            }
        }

        if let rawKind = args["goal_kind"] as? String,
           let goalKind = WorkoutGoal.GoalKind(rawValue: rawKind) {
            goal.goalKind = goalKind
        }

        if let rawStatus = args["status"] as? String,
           let status = WorkoutGoal.GoalStatus(rawValue: rawStatus) {
            goal.status = status
            switch status {
            case .completed:
                goal.completedAt = goal.completedAt ?? Date()
            case .active:
                goal.completedAt = nil
            case .paused:
                break
            }
        }

        if let rawWorkoutType = args["workout_type"] as? String {
            let trimmedType = rawWorkoutType.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.linkedWorkoutType = trimmedType.isEmpty ? nil : WorkoutMode(rawValue: trimmedType)
        }

        if let rawActivityName = args["activity_name"] as? String {
            let trimmedActivity = rawActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.linkedActivityName = trimmedActivity.isEmpty ? nil : trimmedActivity
        }

        if args.keys.contains("target_value") {
            goal.targetValue = numericDouble(from: args["target_value"])
        }

        if let rawTargetUnit = args["target_unit"] as? String {
            goal.targetUnit = rawTargetUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let rawPeriodUnit = args["period_unit"] as? String {
            let trimmedPeriodUnit = rawPeriodUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.periodUnit = trimmedPeriodUnit.isEmpty ? nil : WorkoutGoal.PeriodUnit(rawValue: trimmedPeriodUnit)
        }

        if args.keys.contains("period_count") {
            goal.periodCount = numericInt(from: args["period_count"])
        }

        if let rawTargetDate = args["target_date"] as? String {
            let trimmedTargetDate = rawTargetDate.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.targetDate = trimmedTargetDate.isEmpty ? nil : parseDate(trimmedTargetDate)
        }

        if args.keys.contains("check_in_cadence_days") {
            goal.checkInCadenceDays = numericInt(from: args["check_in_cadence_days"])
        }

        if let rawNotes = args["notes"] as? String {
            goal.notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        goal.updatedAt = Date()
        try? modelContext.save()
        return .dataResponse(FunctionResult(
            name: "update_workout_goal",
            response: [
                "success": true,
                "goal": [
                    "id": goal.id.uuidString,
                    "title": goal.trimmedTitle,
                    "goal_kind": goal.goalKind.rawValue,
                    "status": goal.status.rawValue,
                    "workout_type": goal.linkedWorkoutType?.rawValue ?? "",
                    "activity_name": goal.trimmedActivityName ?? "",
                    "target_value": goal.targetValue as Any,
                    "target_unit": goal.targetUnit,
                    "period_unit": goal.periodUnit?.rawValue ?? "",
                    "period_count": goal.periodCount as Any,
                    "notes": goal.trimmedNotes,
                    "target_date": goal.targetDate.map(formatDateForFunction) ?? "",
                    "check_in_cadence_days": goal.checkInCadenceDays as Any
                ]
            ]
        ))
    }

    private func parseDate(_ rawDate: String?) -> Date? {
        guard let rawDate else { return nil }
        let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        if let isoDate = isoFormatter.date(from: trimmed) {
            return isoDate
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    private func formatDateForFunction(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatDateTimeForFunction(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func numericDouble(from value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func numericInt(from value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Double:
            return Int(number.rounded())
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    func executeUpdateWorkoutNotes(_ args: [String: Any]) -> ExecutionResult {
        guard let workoutIdString = args["workout_id"] as? String,
              let workoutId = UUID(uuidString: workoutIdString) else {
            return .dataResponse(FunctionResult(
                name: "update_workout_notes",
                response: ["error": "Invalid or missing workout_id"]
            ))
        }

        guard let rawNotes = args["notes"] as? String else {
            return .dataResponse(FunctionResult(
                name: "update_workout_notes",
                response: ["error": "Missing notes"]
            ))
        }

        let trimmedNotes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else {
            return .dataResponse(FunctionResult(
                name: "update_workout_notes",
                response: ["error": "Notes cannot be empty"]
            ))
        }

        let append = args["append"] as? Bool ?? false

        let liveDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { $0.id == workoutId }
        )
        if let liveWorkout = try? modelContext.fetch(liveDescriptor).first {
            let existingNotes = liveWorkout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            liveWorkout.notes = mergedWorkoutNotes(existing: existingNotes, incoming: trimmedNotes, append: append)
            try? modelContext.save()

            return .dataResponse(FunctionResult(
                name: "update_workout_notes",
                response: [
                    "success": true,
                    "workout_id": liveWorkout.id.uuidString,
                    "name": liveWorkout.name,
                    "type": liveWorkout.type.rawValue,
                    "source": "trai_live_workout",
                    "notes": liveWorkout.notes
                ]
            ))
        }

        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == workoutId }
        )
        if let workoutSession = try? modelContext.fetch(sessionDescriptor).first {
            let existingNotes = workoutSession.trimmedNotes
            workoutSession.notes = mergedWorkoutNotes(existing: existingNotes, incoming: trimmedNotes, append: append)
            try? modelContext.save()

            return .dataResponse(FunctionResult(
                name: "update_workout_notes",
                response: [
                    "success": true,
                    "workout_id": workoutSession.id.uuidString,
                    "name": workoutSession.displayName,
                    "type": workoutSession.inferredWorkoutMode.rawValue,
                    "display_type": workoutSession.displayTypeName,
                    "source": workoutSession.sourceIsHealthKit ? "apple_health" : "manual_session",
                    "notes": workoutSession.notes ?? ""
                ]
            ))
        }

        return .dataResponse(FunctionResult(
            name: "update_workout_notes",
            response: ["error": "Workout not found"]
        ))
    }

    private func mergedWorkoutNotes(existing: String, incoming: String, append: Bool) -> String {
        guard append, !existing.isEmpty else { return incoming }
        if existing.caseInsensitiveCompare(incoming) == .orderedSame {
            return existing
        }
        return existing + "\n" + incoming
    }

    /// Determines the date range for workout queries
    private func determineWorkoutDateRange(
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

        // Default with range_days only: start from today and go back
        let rangeDays = (args["range_days"] as? Int) ?? 7
        let startDate = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: calendar.startOfDay(for: today))!
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: calendar.startOfDay(for: today))
        return (startDate, endOfRange, "\(startDateString) to \(endDateString)")
    }

    func executeLogWorkout(_ args: [String: Any]) -> ExecutionResult {
        guard let type = args["type"] as? String else {
            return .dataResponse(FunctionResult(
                name: "log_workout",
                response: ["error": "Missing workout type"]
            ))
        }

        let workoutName = args["name"] as? String  // Trai-generated name
        let durationMinutes = args["duration_minutes"] as? Int
        let notes = args["notes"] as? String

        // Parse exercises with per-set data
        var exercises: [SuggestedWorkoutLog.LoggedExercise] = []
        if let exercisesData = args["exercises"] as? [[String: Any]] {
            for exerciseData in exercisesData {
                guard let name = exerciseData["name"] as? String else { continue }

                var sets: [SuggestedWorkoutLog.LoggedExercise.SetData] = []

                // New format: sets is an array of {reps, weight_kg}
                if let setsArray = exerciseData["sets"] as? [[String: Any]] {
                    for setData in setsArray {
                        let reps = setData["reps"] as? Int ?? 10
                        let weight = setData["weight_kg"] as? Double
                        sets.append(SuggestedWorkoutLog.LoggedExercise.SetData(
                            reps: reps,
                            weightKg: weight
                        ))
                    }
                }
                // Legacy format: sets/reps as integers
                else if let setCount = exerciseData["sets"] as? Int {
                    let reps = exerciseData["reps"] as? Int ?? 10
                    let weight = exerciseData["weight_kg"] as? Double
                    for _ in 0..<setCount {
                        sets.append(SuggestedWorkoutLog.LoggedExercise.SetData(
                            reps: reps,
                            weightKg: weight
                        ))
                    }
                }

                if !sets.isEmpty {
                    exercises.append(SuggestedWorkoutLog.LoggedExercise(
                        name: name,
                        sets: sets
                    ))
                }
            }
        }

        // Return suggestion for user approval (don't save yet)
        let suggestion = SuggestedWorkoutLog(
            name: workoutName,
            workoutType: type,
            durationMinutes: durationMinutes,
            exercises: exercises,
            notes: notes
        )

        return .suggestedWorkoutLog(suggestion)
    }

    // MARK: - Weight Functions

    func executeGetWeightHistory(_ args: [String: Any]) -> ExecutionResult {
        let calendar = Calendar.current
        let today = Date()
        let limit = args["limit"] as? Int ?? 10

        // Check if date range is specified
        let hasDateRange = args["date"] != nil || args["days_back"] != nil || args["range_days"] != nil

        var entries: [WeightEntry] = []
        var dateDescription = "recent"

        if hasDateRange {
            let (startDate, endDate, description) = determineWeightDateRange(
                args: args,
                calendar: calendar,
                today: today
            )
            dateDescription = description

            let descriptor = FetchDescriptor<WeightEntry>(
                predicate: #Predicate { $0.loggedAt >= startDate && $0.loggedAt < endDate },
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            entries = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            // Default: get recent entries with limit
            let descriptor = FetchDescriptor<WeightEntry>(
                sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
            )
            entries = (try? modelContext.fetch(descriptor)) ?? []
            entries = Array(entries.prefix(limit))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"

        let formattedEntries = entries.map { entry -> [String: Any] in
            var result: [String: Any] = [
                "id": entry.id.uuidString,
                "weight_kg": entry.weightKg,
                "weight_lbs": entry.weightLbs,
                "date": dateFormatter.string(from: entry.loggedAt)
            ]
            if let bodyFat = entry.bodyFatPercentage {
                result["body_fat_percentage"] = bodyFat
            }
            if let leanMass = entry.calculatedLeanMassKg {
                result["lean_mass_kg"] = leanMass
            }
            return result
        }

        // Calculate trends if we have multiple entries
        var trends: [String: Any]?
        if entries.count >= 2 {
            let oldest = entries.last!
            let newest = entries.first!
            let weightChange = newest.weightKg - oldest.weightKg
            let daysBetween = calendar.dateComponents([.day], from: oldest.loggedAt, to: newest.loggedAt).day ?? 1

            trends = [
                "weight_change_kg": weightChange,
                "weight_change_lbs": weightChange * 2.20462,
                "days_tracked": daysBetween,
                "direction": weightChange > 0 ? "gained" : weightChange < 0 ? "lost" : "maintained"
            ]
        }

        // Include current and target weight from profile
        var profileInfo: [String: Any] = [:]
        if let profile = userProfile {
            if let currentWeight = profile.currentWeightKg {
                profileInfo["current_weight_kg"] = currentWeight
            }
            if let targetWeight = profile.targetWeightKg {
                profileInfo["target_weight_kg"] = targetWeight
                if let currentWeight = profile.currentWeightKg {
                    profileInfo["remaining_to_target_kg"] = currentWeight - targetWeight
                }
            }
        }

        var response: [String: Any] = [
            "date_range": dateDescription,
            "entries": formattedEntries,
            "count": entries.count
        ]

        if let trends {
            response["trends"] = trends
        }
        if !profileInfo.isEmpty {
            response["profile"] = profileInfo
        }

        return .dataResponse(FunctionResult(
            name: "get_weight_history",
            response: response
        ))
    }

    /// Log a new body weight entry
    func executeLogWeight(_ args: [String: Any]) -> ExecutionResult {
        let explicitUnit = (args["unit"] as? String).flatMap(normalizeWeightUnit)
        let fallbackUnit = defaultWeightUnit()

        guard let rawWeight = args["weight"],
              let parsedInput = parseWeightInput(
                rawWeight,
                explicitUnit: explicitUnit,
                fallbackUnit: fallbackUnit
              ),
              parsedInput.weight > 0 else {
            return .dataResponse(FunctionResult(
                name: "log_weight",
                response: ["error": "Missing or invalid parameters: weight and unit"]
            ))
        }

        let weight = parsedInput.weight
        let unit = parsedInput.unit

        // Convert to kg if needed
        let weightKg: Double
        if unit == "lbs" {
            weightKg = weight / 2.20462
        } else {
            weightKg = weight
        }

        // Parse optional date (defaults to now)
        var logDate = Date()
        if let dateString = args["date"] as? String {
            if let parsedDate = parseWeightLogDate(dateString) {
                logDate = parsedDate
            }
        }

        // Create and save the weight entry
        let entry = WeightEntry(weightKg: weightKg, loggedAt: logDate)
        if let notes = args["notes"] as? String {
            entry.notes = notes
        }

        modelContext.insert(entry)

        do {
            try modelContext.save()
        } catch {
            return .dataResponse(FunctionResult(
                name: "log_weight",
                response: ["error": "Failed to save weight entry: \(error.localizedDescription)"]
            ))
        }

        // Update user profile's current weight if logging for today
        if Calendar.current.isDateInToday(logDate), let profile = userProfile {
            profile.currentWeightKg = weightKg
            try? modelContext.save()
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        return .dataResponse(FunctionResult(
            name: "log_weight",
            response: [
                "success": true,
                "message": "Weight logged successfully",
                "weight_kg": weightKg,
                "weight_lbs": weightKg * 2.20462,
                "unit_used": unit,
                "date": dateFormatter.string(from: logDate)
            ]
        ))
    }

    /// Determines the date range for weight queries
    private func determineWeightDateRange(
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

        // Default with range_days only: start from today and go back
        let rangeDays = (args["range_days"] as? Int) ?? 30
        let startDate = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: calendar.startOfDay(for: today))!
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: calendar.startOfDay(for: today))
        return (startDate, endOfRange, "\(startDateString) to \(endDateString)")
    }

    private func parseWeightValue(_ rawValue: Any) -> Double? {
        if let number = rawValue as? Double {
            return number
        }
        if let number = rawValue as? Int {
            return Double(number)
        }
        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }
        if let string = rawValue as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parseWeightInput(
        _ rawValue: Any,
        explicitUnit: String?,
        fallbackUnit: String
    ) -> (weight: Double, unit: String)? {
        if let value = parseWeightValue(rawValue) {
            let unit = explicitUnit ?? fallbackUnit
            return (value, unit)
        }

        guard let stringValue = rawValue as? String else {
            return nil
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let inferredUnit = inferWeightUnit(from: trimmed)
        guard let numericComponent = extractLeadingNumber(from: trimmed),
              let numericValue = Double(numericComponent) else {
            return nil
        }

        let unit = explicitUnit ?? inferredUnit ?? fallbackUnit
        return (numericValue, unit)
    }

    private func extractLeadingNumber(from input: String) -> String? {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: input,
                range: NSRange(input.startIndex..., in: input)
              ),
              let range = Range(match.range, in: input) else {
            return nil
        }

        return String(input[range]).replacingOccurrences(of: ",", with: ".")
    }

    private func inferWeightUnit(from input: String) -> String? {
        let normalized = input.lowercased()
        if normalized.contains("lb") || normalized.contains("pound") {
            return "lbs"
        }
        if normalized.contains("kg") || normalized.contains("kilo") {
            return "kg"
        }
        return nil
    }

    private func defaultWeightUnit() -> String {
        guard let userProfile else { return "kg" }
        return userProfile.usesMetricWeight ? "kg" : "lbs"
    }

    private func normalizeWeightUnit(_ rawUnit: String) -> String? {
        switch rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "kg", "kgs", "kilogram", "kilograms":
            return "kg"
        case "lb", "lbs", "pound", "pounds":
            return "lbs"
        default:
            return nil
        }
    }

    private func parseWeightLogDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let day = dayFormatter.date(from: trimmed) {
            return day
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let isoDate = isoFormatter.date(from: trimmed) {
            return isoDate
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        if let isoDate = fallbackISOFormatter.date(from: trimmed) {
            return isoDate
        }

        return nil
    }
}
