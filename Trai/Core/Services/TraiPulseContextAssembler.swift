//
//  TraiPulseContextAssembler.swift
//  Trai
//
//  Builds compact, ranked context packets for Pulse and chat prompts.
//

import Foundation

enum TraiPulseContextAssembler {
    private struct RankedSnippet {
        let text: String
        let utility: Double
    }

    static func assemble(
        patternProfile: TraiPulsePatternProfile,
        activeSignals: [CoachSignalSnapshot],
        context: TraiPulseInputContext,
        tokenBudget: Int = 700
    ) -> TraiPulseContextPacket {
        let proteinRemaining = max(context.proteinGoal - context.proteinConsumed, 0)
        let calorieRemaining = max(context.calorieGoal - context.caloriesConsumed, 0)

        let goal = primaryGoal(
            context: context,
            proteinRemaining: proteinRemaining,
            calorieRemaining: calorieRemaining
        )

        let constraints = rankedConstraints(from: activeSignals, context: context)
        let patterns = rankedPatterns(from: patternProfile)
        let anomalies = rankedAnomalies(context: context)
        let actions = rankedActions(
            context: context,
            patternProfile: patternProfile,
            proteinRemaining: proteinRemaining
        )

        var selectedConstraints = select(from: constraints, limit: 2)
        var selectedPatterns = select(from: patterns, limit: 3)
        var selectedAnomalies = select(from: anomalies, limit: 2)
        var selectedActions = select(from: actions, limit: 2)

        var packet = packetFrom(
            goal: goal,
            constraints: selectedConstraints,
            patterns: selectedPatterns,
            anomalies: selectedAnomalies,
            actions: selectedActions
        )

        while packet.estimatedTokens > tokenBudget {
            if !selectedAnomalies.isEmpty {
                selectedAnomalies.removeLast()
            } else if selectedPatterns.count > 1 {
                selectedPatterns.removeLast()
            } else if selectedActions.count > 1 {
                selectedActions.removeLast()
            } else if selectedConstraints.count > 1 {
                selectedConstraints.removeLast()
            } else {
                break
            }

            packet = packetFrom(
                goal: goal,
                constraints: selectedConstraints,
                patterns: selectedPatterns,
                anomalies: selectedAnomalies,
                actions: selectedActions
            )
        }

        return packet
    }

    private static func primaryGoal(
        context: TraiPulseInputContext,
        proteinRemaining: Int,
        calorieRemaining: Int
    ) -> String {
        if !context.hasWorkoutToday && !context.hasActiveWorkout {
            return "Complete your workout in today's available window"
        }
        if proteinRemaining >= 30 {
            return "Close the protein gap (~\(proteinRemaining)g remaining)"
        }
        if calorieRemaining >= 450 {
            return "Finish nutrition within today's calorie target"
        }
        return "Protect consistency and recovery for tomorrow"
    }

    private static func rankedConstraints(from signals: [CoachSignalSnapshot], context: TraiPulseInputContext) -> [RankedSnippet] {
        var ranked = signals
            .sorted { lhs, rhs in
                (lhs.severity * lhs.confidence) > (rhs.severity * rhs.confidence)
            }
            .map {
                RankedSnippet(
                    text: "\($0.domain.displayName): \($0.title)",
                    utility: clamp(($0.severity * 0.7) + ($0.confidence * 0.3))
                )
            }

        if !context.hasWorkoutToday && !context.hasActiveWorkout {
            let hour = Calendar.current.component(.hour, from: context.now)
            if hour > context.workoutWindowEndHour {
                ranked.append(
                    RankedSnippet(
                        text: "Today's workout window has passed",
                        utility: 0.8
                    )
                )
            }
        }

        if let reminderRate = context.reminderCompletionRate {
            if reminderRate < 0.6 {
                ranked.append(
                    RankedSnippet(
                        text: "Reminder completion is low",
                        utility: clamp(0.64 + (1 - reminderRate) * 0.25)
                    )
                )
            }
        }

        if let missed = context.recentMissedReminderCount, missed > 0 {
            ranked.append(
                RankedSnippet(
                    text: "\(missed) reminders still pending",
                    utility: clamp(0.61 + Double(min(missed, 4)) * 0.08)
                )
            )
        }

        if let daysSinceWeight = context.daysSinceLastWeightLog, daysSinceWeight >= 3 {
            ranked.append(
                RankedSnippet(
                    text: "Last weight log was \(daysSinceWeight)d ago",
                    utility: clamp(0.6 + Double(min(daysSinceWeight, 6)) * 0.06)
                )
            )
        }

        if !context.weightLoggedThisWeekDays.isEmpty {
            let currentWeekday = weekdayName(for: Calendar.current.component(.weekday, from: context.now))
            if context.weightLoggedThisWeekDays.contains(currentWeekday) {
                ranked.append(
                    RankedSnippet(
                        text: "You usually log weight on \(currentWeekday)",
                        utility: 0.62
                    )
                )
            }
        }

        if let exerciseMinutes = context.todaysExerciseMinutes {
            if exerciseMinutes == 0 && !context.hasWorkoutToday && !context.hasActiveWorkout {
                ranked.append(
                    RankedSnippet(
                        text: "No exercise minutes logged today",
                        utility: 0.58
                    )
                )
            } else if exerciseMinutes < 10 {
                ranked.append(
                    RankedSnippet(
                        text: "Exercise today is light (\(exerciseMinutes)m)",
                        utility: 0.44 + min(Double(exerciseMinutes) / 40.0, 0.06)
                    )
                )
            }
        }

        return ranked.sorted { $0.utility > $1.utility }
    }

    private static func rankedPatterns(from profile: TraiPulsePatternProfile) -> [RankedSnippet] {
        var ranked: [RankedSnippet] = []

        if let window = profile.strongestWorkoutWindow(minScore: 0.32),
           let score = profile.workoutWindowScores[window.rawValue] {
            ranked.append(
                RankedSnippet(
                    text: "You usually train in the \(window.label.lowercased())",
                    utility: clamp(score * 0.9 + profile.confidence * 0.1)
                )
            )
        }

        if let mealWindow = profile.strongestMealWindow(minScore: 0.28),
           let score = profile.mealWindowScores[mealWindow.rawValue] {
            ranked.append(
                RankedSnippet(
                    text: "Most meal logs happen in the \(mealWindow.label.lowercased())",
                    utility: clamp(score * 0.85 + profile.confidence * 0.15)
                )
            )
        }

        if !profile.commonProteinAnchors.isEmpty {
            let anchors = profile.commonProteinAnchors.prefix(2).joined(separator: ", ")
            ranked.append(
                RankedSnippet(
                    text: "Common protein anchors: \(anchors)",
                    utility: clamp(0.62 + (Double(min(profile.commonProteinAnchors.count, 3)) * 0.08))
                )
            )
        }

        for note in profile.adherenceNotes {
            ranked.append(
                RankedSnippet(
                    text: note,
                    utility: 0.58
                )
            )
        }

        return ranked.sorted { $0.utility > $1.utility }
    }

    private static func rankedAnomalies(context: TraiPulseInputContext) -> [RankedSnippet] {
        guard let trend = context.trend else { return [] }

        var anomalies: [RankedSnippet] = []

        if trend.lowProteinStreak >= 2 {
            anomalies.append(
                RankedSnippet(
                    text: "Protein has been under target for \(trend.lowProteinStreak) days",
                    utility: clamp(0.62 + Double(min(trend.lowProteinStreak, 4)) * 0.08)
                )
            )
        }

        if trend.daysSinceWorkout >= 3 {
            anomalies.append(
                RankedSnippet(
                    text: "No workout logged for \(trend.daysSinceWorkout) days",
                    utility: clamp(0.6 + Double(min(trend.daysSinceWorkout, 6)) * 0.05)
                )
            )
        }

        if trend.loggingConsistency < 0.5 {
            anomalies.append(
                RankedSnippet(
                    text: "Logging coverage is low this week",
                    utility: clamp(0.72 - trend.loggingConsistency * 0.5)
                )
            )
        }

        if context.weightLoggedThisWeek == false {
            anomalies.append(
                RankedSnippet(
                    text: "Weight hasn't been logged this week",
                    utility: 0.66
                )
            )
        }

        if !context.weightLoggedThisWeekDays.isEmpty &&
            context.daysSinceLastWeightLog != nil &&
            context.daysSinceLastWeightLog! >= 2 {
            let currentWeekday = weekdayName(for: Calendar.current.component(.weekday, from: context.now))
            if context.weightLoggedThisWeekDays.contains(currentWeekday) {
                anomalies.append(
                    RankedSnippet(
                        text: "Today is a usual weight-log day but no log yet",
                        utility: 0.7
                    )
                )
            }
        }

        if let planReviewMessage = context.planReviewMessage, !planReviewMessage.isEmpty {
            anomalies.append(
                RankedSnippet(
                    text: planReviewMessage,
                    utility: clamp(0.76 + (context.planReviewWeightDeltaKg.map { min(abs($0) / 4.0, 0.1) } ?? 0))
                )
            )
        }

        if let weightRange = context.weightRecentRangeKg,
           weightRange >= 1.6 {
            anomalies.append(
                RankedSnippet(
                    text: "Weight has fluctuated by about \(String(format: "%.1f", weightRange))kg recently",
                    utility: clamp(0.68 + min(weightRange / 5.0, 0.18))
                )
            )
        }

        return anomalies.sorted { $0.utility > $1.utility }
    }

    private static func rankedActions(
        context: TraiPulseInputContext,
        patternProfile: TraiPulsePatternProfile,
        proteinRemaining: Int
    ) -> [RankedSnippet] {
        let workoutTitle = context.recommendedWorkoutName ?? "recommended workout"
        var ranked: [RankedSnippet] = []
        var hasWeightLogAction = false

        if let reminderRate = context.reminderCompletionRate, reminderRate < 0.7 {
            ranked.append(
                RankedSnippet(
                    text: "Reminder completion is low",
                    utility: clamp(0.74 + (1 - reminderRate) * 0.2)
                )
            )
        } else if let missed = context.recentMissedReminderCount, missed > 1 {
            ranked.append(
                RankedSnippet(
                    text: "You have \(missed) reminders pending",
                    utility: clamp(0.7 + min(Double(missed), 3) * 0.06)
                )
            )
        }

        for reminder in rankedReminderCandidates(context: context).prefix(3) {
            let actionUtility = reminderScoreToUtility(reminder.score)
            ranked.append(
                RankedSnippet(
                    text: "Complete \(reminder.candidate.title) at \(reminder.candidate.time)",
                    utility: actionUtility
                )
            )
        }

        if !context.hasWorkoutToday && !context.hasActiveWorkout,
           let bestWorkoutWindow = patternProfile.strongestWorkoutWindow(minScore: 0.24) {
            ranked.append(
                RankedSnippet(
                    text: "Start workout in your \(bestWorkoutWindow.label.lowercased()) pattern window",
                    utility: clamp(0.76 + patternProfile.affinity(for: .startWorkout) * 0.15)
                )
            )
        }

        for workoutWindow in context.likelyWorkoutTimes.prefix(3) {
            ranked.append(
                RankedSnippet(
                    text: "Workout around \(workoutWindow)",
                    utility: clamp(0.63)
                )
            )
        }

        let currentWeekday = weekdayName(for: Calendar.current.component(.weekday, from: context.now))
        let usualWeightDay = context.weightLoggedThisWeekDays.contains(currentWeekday)
        let currentHour = Calendar.current.component(.hour, from: context.now)
        let currentWeightLogWindow = matchingWeightLogWindow(
            hour: currentHour,
            windows: context.weightLikelyLogTimes
        )
        let weightLogRoutineScore = context.weightLogRoutineScore

        if let daysSinceWeight = context.daysSinceLastWeightLog,
           (daysSinceWeight >= 4 && (context.weightLoggedThisWeek ?? true) == false) {
            ranked.append(
                RankedSnippet(
                    text: "Log Weight",
                    utility: clamp(0.76 + Double(min(daysSinceWeight, 7)) * 0.02 + (weightLogRoutineScore * 0.08))
                )
            )
            hasWeightLogAction = true
        } else if usualWeightDay && (context.weightLoggedThisWeek ?? true) == false {
            ranked.append(
                RankedSnippet(
                    text: "Log Weight",
                    utility: clamp(0.78 + (weightLogRoutineScore * 0.06))
                )
            )
            hasWeightLogAction = true
        } else if let weightWindow = currentWeightLogWindow, (context.weightLoggedThisWeek ?? true) == false {
            ranked.append(
                RankedSnippet(
                    text: "Log Weight (\(weightWindow))",
                    utility: clamp(0.73 + (weightLogRoutineScore * 0.07))
                )
            )
            hasWeightLogAction = true
        }

        if !hasWeightLogAction && (context.weightLoggedThisWeek ?? true) == false && currentWeightLogWindow != nil {
            ranked.append(
                RankedSnippet(
                    text: "Log Weight (\(currentWeightLogWindow ?? "your usual slot"))",
                    utility: clamp(0.66 + (weightLogRoutineScore * 0.08))
                )
            )
            hasWeightLogAction = true
        }

        if let daysSinceWeight = context.daysSinceLastWeightLog, daysSinceWeight >= 8 {
            ranked.append(
                RankedSnippet(
                    text: "Open Weight",
                    utility: clamp(0.62 + (weightLogRoutineScore * 0.05))
                )
            )
        } else if context.weightLoggedThisWeek == false {
            ranked.append(
                RankedSnippet(
                    text: "Open Weight",
                    utility: clamp(0.54 + (weightLogRoutineScore * 0.08))
                )
            )
        }

        if !context.hasWorkoutToday && !context.hasActiveWorkout {
            let workoutWindow = Calendar.current.component(.hour, from: context.now)
            if workoutWindow >= context.workoutWindowStartHour && workoutWindow <= context.workoutWindowEndHour {
                ranked.append(
                    RankedSnippet(
                        text: "Start \(workoutTitle)",
                        utility: clamp(0.74 + patternProfile.affinity(for: .startWorkout) * 0.22)
                    )
                )
            }
        }

        if proteinRemaining >= 25 {
            ranked.append(
                RankedSnippet(
                    text: "Log a protein-focused meal",
                    utility: clamp(0.68 + patternProfile.affinity(for: .logFood) * 0.22)
                )
            )
        }

        if context.activeSignals.contains(where: { $0.domain == .pain || $0.domain == .recovery }) {
            ranked.append(
                RankedSnippet(
                    text: "Open Recovery",
                    utility: clamp(0.72 + patternProfile.affinity(for: .openRecovery) * 0.18)
                )
            )
        }

        if context.todaysExerciseMinutes == 0 && !context.hasActiveWorkout && !context.hasWorkoutToday {
            ranked.append(
                RankedSnippet(
                    text: "Open Workouts",
                    utility: 0.48 + patternProfile.affinity(for: .openWorkouts) * 0.17
                )
            )
        }

        if let planReviewTrigger = context.planReviewTrigger, !planReviewTrigger.isEmpty {
            let reviewAction: String
            let affinityKind: TraiPulseAction.Kind
            switch planReviewTrigger {
            case "weight_change", "weight_plateau":
                reviewAction = "Review Nutrition Plan"
                affinityKind = .reviewNutritionPlan
            default:
                reviewAction = "Review Workout Plan"
                affinityKind = .reviewWorkoutPlan
            }

            ranked.append(
                RankedSnippet(
                    text: reviewAction,
                    utility: clamp(0.84 + (patternProfile.affinity(for: affinityKind) * 0.16) +
                                   (context.planReviewDaysSince ?? 0 > 30 ? 0.06 : 0.0))
                )
            )
        } else if let weightRange = context.weightRecentRangeKg, weightRange >= 2.2 {
            ranked.append(
                RankedSnippet(
                    text: "Review Nutrition Plan",
                    utility: clamp(0.75 + patternProfile.affinity(for: .reviewNutritionPlan) * 0.15)
                )
            )
        }

        if context.caloriesConsumed > 0 {
            ranked.append(
                RankedSnippet(
                    text: "Open Calorie Detail",
                    utility: clamp(0.45 + (patternProfile.affinity(for: .openCalorieDetail) * 0.16))
                )
            )
        }

        if context.proteinConsumed > 0 || context.proteinGoal > 0 {
            ranked.append(
                RankedSnippet(
                    text: "Open Macro Detail",
                    utility: clamp(0.44 + (patternProfile.affinity(for: .openMacroDetail) * 0.15))
                )
            )
        }

        return ranked.sorted { $0.utility > $1.utility }
    }

    private static func select(from snippets: [RankedSnippet], limit: Int) -> [String] {
        Array(snippets.prefix(max(limit, 0)).map(\.text))
    }

    private static func rankedReminderCandidates(
        context: TraiPulseInputContext
    ) -> [(candidate: TraiPulseReminderCandidate, score: Double)] {
        guard !context.pendingReminderCandidates.isEmpty else { return [] }

        return context.pendingReminderCandidates
            .map { candidate in
                (candidate: candidate, score: context.pendingReminderCandidateScores[candidate.id] ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.candidate.hour != rhs.candidate.hour {
                    return lhs.candidate.hour < rhs.candidate.hour
                }
                return lhs.candidate.minute < rhs.candidate.minute
            }
    }

    private static func reminderScoreToUtility(_ score: Double) -> Double {
        let boundedScore = clamp(score)
        return clamp(0.74 + (boundedScore * 0.18))
    }

    private static func weekdayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Unknown"
        }
    }

    private static func packetFrom(
        goal: String,
        constraints: [String],
        patterns: [String],
        anomalies: [String],
        actions: [String]
    ) -> TraiPulseContextPacket {
        var lines: [String] = []
        lines.append("goal=\(goal)")

        if !constraints.isEmpty {
            lines.append("constraints=\(constraints.joined(separator: " | "))")
        }
        if !patterns.isEmpty {
            lines.append("patterns=\(patterns.joined(separator: " | "))")
        }
        if !anomalies.isEmpty {
            lines.append("anomalies=\(anomalies.joined(separator: " | "))")
        }
        if !actions.isEmpty {
            lines.append("next_actions=\(actions.joined(separator: " | "))")
        }

        let summary = lines.joined(separator: "\n")

        return TraiPulseContextPacket(
            goal: goal,
            constraints: constraints,
            patterns: patterns,
            anomalies: anomalies,
            suggestedActions: actions,
            estimatedTokens: estimateTokens(summary),
            promptSummary: summary
        )
    }

    private static func estimateTokens(_ text: String) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return max(1, Int((Double(words) * 1.25).rounded()))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func matchingWeightLogWindow(hour: Int, windows: [String]) -> String? {
        guard (0...23).contains(hour) else { return nil }

        for window in windows {
            switch window {
            case "Morning (4-9 AM)":
                if (4...8).contains(hour) { return "morning window" }
            case "Late Morning (9-12 PM)":
                if (9...11).contains(hour) { return "late morning window" }
            case "Early Afternoon (12-3 PM)":
                if (12...14).contains(hour) { return "early afternoon window" }
            case "Mid-Afternoon (3-6 PM)":
                if (15...17).contains(hour) { return "mid afternoon window" }
            case "Evening (6-10 PM)":
                if (18...21).contains(hour) { return "evening window" }
            case "Night (10 PM-4 AM)":
                if hour >= 22 || hour <= 3 { return "night window" }
            default:
                continue
            }
        }

        return nil
    }
}
