//
//  TraiPulseActionRanker.swift
//  Trai
//
//  Deterministic candidate ranking for Pulse actions.
//

import Foundation

struct TraiPulseRankedAction: Sendable {
    let action: DailyCoachAction
    let score: Double
}

enum TraiPulseActionRanker {
    static func rankActions(
        context: DailyCoachContext,
        now: Date = .now,
        limit: Int = 6
    ) -> [TraiPulseRankedAction] {
        let hour = Calendar.current.component(.hour, from: now)
        let proteinRemaining = max(context.proteinGoal - context.proteinConsumed, 0)
        var candidates: [TraiPulseRankedAction] = []

        if let reminder = bestReminderCandidate(from: context) {
            let reminderAffinity = affinity(for: .completeReminder, context: context)
            let utility = adjustedScore(
                0.67 + (reminder.score * 0.2) + (reminderAffinity * 0.1),
                for: .completeReminder,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(
                        kind: .completeReminder,
                        title: "Complete \(reminder.candidate.title)",
                        subtitle: "Scheduled at \(reminder.candidate.time)",
                        metadata: [
                            "reminder_id": reminder.candidate.id,
                            "reminder_title": reminder.candidate.title,
                            "reminder_time": reminder.candidate.time,
                            "reminder_hour": String(reminder.candidate.hour),
                            "reminder_minute": String(reminder.candidate.minute)
                        ]
                    ),
                    score: utility
                )
            )
        }

        if shouldSuggestWeightLog(context: context, hour: hour) {
            let daysSince = Double(context.daysSinceLastWeightLog ?? 1)
            let utility = adjustedScore(
                0.71 + min(daysSince, 7) * 0.02 + (context.weightLogRoutineScore * 0.1),
                for: .logWeight,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(
                        kind: .logWeight,
                        title: "Log Morning Weight",
                        subtitle: "Keep your check-in routine"
                    ),
                    score: utility
                )
            )
        }

        if let daysSince = context.daysSinceLastWeightLog, daysSince >= 6 {
            let utility = adjustedScore(
                0.6 + min(Double(daysSince), 10) * 0.02 + (context.weightLogRoutineScore * 0.08),
                for: .openWeight,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(
                        kind: .openWeight,
                        title: "Review Weight Trend",
                        subtitle: "Re-anchor your routine"
                    ),
                    score: utility
                )
            )
        }

        if !context.hasWorkoutToday && !context.hasActiveWorkout {
            let workoutAffinity = affinity(for: .startWorkout, context: context)
            let inWindow = hour >= 6 && hour <= 21
            let utility = adjustedScore(
                (inWindow ? 0.68 : 0.56) + (workoutAffinity * 0.24),
                for: .startWorkout,
                context: context,
                hour: hour
            )
            let workoutTitle = context.recommendedWorkoutName.map { "Start \($0)" } ?? "Start Workout"
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(kind: .startWorkout, title: workoutTitle),
                    score: utility
                )
            )

            let workoutsUtility = adjustedScore(
                0.46 + affinity(for: .openWorkouts, context: context) * 0.2,
                for: .openWorkouts,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(kind: .openWorkouts, title: "Open Workouts"),
                    score: workoutsUtility
                )
            )

            if context.recommendedWorkoutName != nil {
                let openPlanUtility = adjustedScore(
                    0.48 + affinity(for: .openWorkoutPlan, context: context) * 0.2,
                    for: .openWorkoutPlan,
                    context: context,
                    hour: hour
                )
                candidates.append(
                    TraiPulseRankedAction(
                        action: DailyCoachAction(kind: .openWorkoutPlan, title: "Open Workout Plan"),
                        score: openPlanUtility
                    )
                )
            }
        }

        if proteinRemaining >= 25 {
            let utility = adjustedScore(
                0.62 +
                min(Double(proteinRemaining) / 100.0, 0.16) +
                affinity(for: .logFood, context: context) * 0.18,
                for: .logFood,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(
                        kind: .logFood,
                        title: "Log Protein Meal",
                        subtitle: "\(proteinRemaining)g protein remaining"
                    ),
                    score: utility
                )
            )

            let cameraUtility = adjustedScore(
                0.58 + min(Double(proteinRemaining) / 120.0, 0.12) + affinity(for: .logFoodCamera, context: context) * 0.16,
                for: .logFoodCamera,
                context: context,
                hour: hour
            )
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(
                        kind: .logFoodCamera,
                        title: "Scan Next Meal",
                        subtitle: "Fast photo log"
                    ),
                    score: cameraUtility
                )
            )
        }

        if context.caloriesConsumed > 0 {
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(kind: .openCalorieDetail, title: "Open Calorie Detail"),
                    score: adjustedScore(
                        0.44 + affinity(for: .openCalorieDetail, context: context) * 0.2,
                        for: .openCalorieDetail,
                        context: context,
                        hour: hour
                    )
                )
            )
        }

        candidates.append(
            TraiPulseRankedAction(
                action: DailyCoachAction(kind: .openMacroDetail, title: "Open Macro Detail"),
                score: adjustedScore(
                    0.42 + affinity(for: .openMacroDetail, context: context) * 0.2,
                    for: .openMacroDetail,
                    context: context,
                    hour: hour
                )
            )
        )

        if context.activeSignals.contains(where: { $0.domain == .pain || $0.domain == .recovery }) {
            candidates.append(
                TraiPulseRankedAction(
                    action: DailyCoachAction(kind: .openRecovery, title: "Check Recovery"),
                    score: adjustedScore(
                        0.66 + affinity(for: .openRecovery, context: context) * 0.2,
                        for: .openRecovery,
                        context: context,
                        hour: hour
                    )
                )
            )
        }

        let openProfileUtility = adjustedScore(
            0.34 + affinity(for: .openProfile, context: context) * 0.2,
            for: .openProfile,
            context: context,
            hour: hour
        )
        candidates.append(
            TraiPulseRankedAction(
                action: DailyCoachAction(kind: .openProfile, title: "Open Profile"),
                score: openProfileUtility
            )
        )

        if let trigger = context.planReviewTrigger, !trigger.isEmpty {
            let isWorkout = trigger == "plan_age"
            let kind: DailyCoachAction.Kind = isWorkout ? .reviewWorkoutPlan : .reviewNutritionPlan
            let affinityKind: TraiPulseAction.Kind = isWorkout ? .reviewWorkoutPlan : .reviewNutritionPlan
            let title = isWorkout ? "Review Workout Plan" : "Review Nutrition Plan"
            let score = adjustedScore(
                0.8 + affinity(for: affinityKind, context: context) * 0.18,
                for: kind,
                context: context,
                hour: hour
            )
            candidates.append(TraiPulseRankedAction(action: DailyCoachAction(kind: kind, title: title), score: score))
        }

        let deduped = dedupeKeepingBest(candidates)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.action.kind.rawValue < rhs.action.kind.rawValue
            }

        return Array(deduped.prefix(max(limit, 0)))
    }

    static func score(
        for action: DailyCoachAction,
        in ranked: [TraiPulseRankedAction]
    ) -> Double {
        ranked.first { candidate in
            candidate.action.kind == action.kind
        }?.score ?? 0
    }

    private static func bestReminderCandidate(
        from context: DailyCoachContext
    ) -> (candidate: TraiPulseReminderCandidate, score: Double)? {
        context.pendingReminderCandidates
            .map { candidate in
                (candidate: candidate, score: context.pendingReminderCandidateScores[candidate.id] ?? 0)
            }
            .max { $0.score < $1.score }
    }

    private static func affinity(
        for kind: TraiPulseAction.Kind,
        context: DailyCoachContext
    ) -> Double {
        context.patternProfile?.affinity(for: kind) ?? 0
    }

    private static func adjustedScore(
        _ base: Double,
        for kind: DailyCoachAction.Kind,
        context: DailyCoachContext,
        hour: Int
    ) -> Double {
        let timingBoost = timingAlignmentBoost(for: kind, context: context, hour: hour)
        let stalenessBoost = stalenessBoost(for: kind, context: context)
        let repeatPenalty = repetitionPenalty(for: kind, context: context)
        return clamp(base + timingBoost + stalenessBoost - repeatPenalty)
    }

    private static func timingAlignmentBoost(
        for kind: DailyCoachAction.Kind,
        context: DailyCoachContext,
        hour: Int
    ) -> Double {
        guard let actionKey = behaviorActionKey(for: kind),
              let behaviorProfile = context.behaviorProfile else {
            return 0
        }

        let preference = behaviorProfile.hourlyPreferenceScore(
            for: actionKey,
            hour: hour,
            minimumEvents: 2
        )
        return min(preference * 0.22, 0.16)
    }

    private static func stalenessBoost(
        for kind: DailyCoachAction.Kind,
        context: DailyCoachContext
    ) -> Double {
        guard let actionKey = behaviorActionKey(for: kind),
              let behaviorProfile = context.behaviorProfile,
              let daysSince = behaviorProfile.daysSinceLastAction(actionKey),
              daysSince > 0 else {
            return 0
        }

        let days = Double(daysSince)
        switch kind {
        case .logWeight, .openWeight:
            return min(days * 0.03, 0.18)
        case .reviewNutritionPlan, .reviewWorkoutPlan, .openWorkoutPlan, .openProfile:
            return min(days * 0.025, 0.14)
        case .logFood, .logFoodCamera:
            return min(days * 0.015, 0.08)
        case .startWorkout, .startWorkoutTemplate:
            return min(days * 0.018, 0.1)
        case .openCalorieDetail, .openMacroDetail, .openWorkouts, .openRecovery, .completeReminder:
            return min(days * 0.012, 0.07)
        }
    }

    private static func repetitionPenalty(
        for kind: DailyCoachAction.Kind,
        context: DailyCoachContext
    ) -> Double {
        guard let actionKey = behaviorActionKey(for: kind) else { return 0 }
        let openedToday = context.todayOpenedActionKeys.contains(actionKey)
        let completedToday = context.todayCompletedActionKeys.contains(actionKey)

        guard openedToday || completedToday else { return 0 }

        switch kind {
        case .logWeight, .openWeight:
            return completedToday ? 0.42 : 0.26
        case .startWorkout, .startWorkoutTemplate:
            return completedToday ? 0.36 : 0.2
        case .logFood, .logFoodCamera:
            return completedToday ? 0.08 : 0.04
        case .completeReminder:
            if context.pendingReminderCandidates.count > 1 {
                return completedToday ? 0.08 : 0.04
            }
            return completedToday ? 0.2 : 0.1
        case .openCalorieDetail, .openMacroDetail, .openProfile, .openWorkouts, .openWorkoutPlan, .openRecovery,
                .reviewNutritionPlan, .reviewWorkoutPlan:
            return completedToday ? 0.24 : 0.16
        }
    }

    private static func behaviorActionKey(for kind: DailyCoachAction.Kind) -> String? {
        switch kind {
        case .startWorkout, .startWorkoutTemplate:
            return BehaviorActionKey.startWorkout
        case .logFood, .logFoodCamera:
            return BehaviorActionKey.logFood
        case .logWeight:
            return BehaviorActionKey.logWeight
        case .openWeight:
            return BehaviorActionKey.openWeight
        case .openCalorieDetail:
            return BehaviorActionKey.openCalorieDetail
        case .openMacroDetail:
            return BehaviorActionKey.openMacroDetail
        case .openProfile:
            return BehaviorActionKey.openProfile
        case .openWorkouts:
            return BehaviorActionKey.openWorkouts
        case .openWorkoutPlan:
            return BehaviorActionKey.openWorkoutPlan
        case .openRecovery:
            return BehaviorActionKey.openRecovery
        case .reviewNutritionPlan:
            return BehaviorActionKey.reviewNutritionPlan
        case .reviewWorkoutPlan:
            return BehaviorActionKey.reviewWorkoutPlan
        case .completeReminder:
            return BehaviorActionKey.completeReminder
        }
    }

    private static func shouldSuggestWeightLog(context: DailyCoachContext, hour: Int) -> Bool {
        guard let daysSince = context.daysSinceLastWeightLog, daysSince > 0 else { return false }
        guard (4..<12).contains(hour) else { return false }
        let hasMorningPattern = context.weightLikelyLogTimes.contains(where: {
            $0.localizedStandardContains("Morning (4-9 AM)") ||
            $0.localizedStandardContains("Late Morning (9-12 PM)")
        })
        return hasMorningPattern || context.weightLogRoutineScore >= 0.42 || daysSince >= 2
    }

    private static func dedupeKeepingBest(_ candidates: [TraiPulseRankedAction]) -> [TraiPulseRankedAction] {
        var bestByKind: [DailyCoachAction.Kind: TraiPulseRankedAction] = [:]
        for candidate in candidates {
            if let existing = bestByKind[candidate.action.kind] {
                if candidate.score > existing.score {
                    bestByKind[candidate.action.kind] = candidate
                }
            } else {
                bestByKind[candidate.action.kind] = candidate
            }
        }
        return Array(bestByKind.values)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
