//
//  TraiPulseEngine.swift
//  Trai
//
//  Deterministic pulse analysis for daily recommendations and questions.
//

import Foundation

enum TraiPulseEngine {
    static func makeBrief(context: TraiPulseInputContext) -> TraiPulseBrief {
        let currentHour = Calendar.current.component(.hour, from: context.now)
        let learnedWorkoutWindow = context.patternProfile?.strongestWorkoutWindow(minScore: 0.38)?.hourRange
        let scheduleStartHour = learnedWorkoutWindow?.start ?? context.workoutWindowStartHour
        let scheduleEndHour = learnedWorkoutWindow?.end ?? context.workoutWindowEndHour

        let calorieProgress = progress(consumed: context.caloriesConsumed, goal: context.calorieGoal)
        let proteinProgress = progress(consumed: context.proteinConsumed, goal: context.proteinGoal)
        let workoutProgress = context.hasActiveWorkout || context.hasWorkoutToday ? 1.0 : 0.0
        let adherenceScore = clamp((calorieProgress + proteinProgress + workoutProgress) / 3.0)

        let scheduleRisk = computeScheduleRisk(
            currentHour: currentHour,
            startHour: scheduleStartHour,
            endHour: scheduleEndHour,
            hasWorkoutToday: context.hasWorkoutToday,
            hasActiveWorkout: context.hasActiveWorkout
        )

        let recoveryReadiness = computeRecoveryReadiness(
            readyMuscleCount: context.readyMuscleCount,
            activeSignals: context.activeSignals
        )
        let trendRisk = computeTrendRisk(context.trend)

        let dataCoverage = clamp(
            (context.caloriesConsumed > 0 ? 0.45 : 0.0) +
            (context.proteinConsumed > 0 ? 0.35 : 0.0) +
            ((context.hasWorkoutToday || context.hasActiveWorkout) ? 0.20 : 0.0)
        )

        let consistency = 1.0 - abs(calorieProgress - proteinProgress)
        let confidence = clamp(
            (0.40 * dataCoverage) +
            (0.25 * consistency) +
            (0.20 * (1.0 - scheduleRisk)) +
            (0.15 * (1.0 - trendRisk))
        )

        let phase = phaseFor(
            currentHour: currentHour,
            startHour: scheduleStartHour,
            endHour: scheduleEndHour,
            hasWorkoutToday: context.hasWorkoutToday,
            hasActiveWorkout: context.hasActiveWorkout
        )

        let workoutName = context.recommendedWorkoutName ?? "recommended session"
        let calorieRemaining = max(context.calorieGoal - context.caloriesConsumed, 0)
        let proteinRemaining = max(context.proteinGoal - context.proteinConsumed, 0)
        let painSignal = context.activeSignals
            .filter { $0.domain == .pain }
            .max { $0.severity < $1.severity }
        let recentAnswer = TraiPulseResponseInterpreter.recentPulseAnswer(
            from: context.activeSignals,
            now: context.now
        )

        let title = titleFor(
            phase: phase,
            scheduleRisk: scheduleRisk,
            painSignal: painSignal,
            trend: context.trend
        )
        let message = messageFor(
            phase: phase,
            scheduleRisk: scheduleRisk,
            workoutName: workoutName,
            calorieRemaining: calorieRemaining,
            proteinRemaining: proteinRemaining,
            painSignal: painSignal,
            trend: context.trend,
            preferredWorkoutWindow: context.patternProfile?.strongestWorkoutWindow(minScore: 0.38),
            recentAnswer: recentAnswer
        )

        var reasons = trendReasons(for: context.trend)
        if let recentAnswer {
            reasons.insert(
                TraiPulseReason(
                    text: TraiPulseResponseInterpreter.carryoverReason(for: recentAnswer),
                    emphasis: 0.84
                ),
                at: 0
            )
        }
        if let packet = context.contextPacket {
            if let pattern = packet.patterns.first {
                reasons.append(TraiPulseReason(text: pattern, emphasis: 0.72))
            }
            if let anomaly = packet.anomalies.first {
                reasons.append(TraiPulseReason(text: anomaly, emphasis: 0.78))
            }
        }
        reasons.append(TraiPulseReason(
            text: "Adherence \(Int((adherenceScore * 100).rounded()))%",
            emphasis: adherenceScore
        ))
        reasons.append(TraiPulseReason(
            text: "Recovery \(Int((recoveryReadiness * 100).rounded()))%",
            emphasis: recoveryReadiness
        ))
        if let painSignal {
            reasons.append(TraiPulseReason(
                text: "\(painSignal.title)",
                emphasis: max(0.65, painSignal.severity)
            ))
        } else {
            reasons.append(TraiPulseReason(
                text: "\(max(context.readyMuscleCount, 0)) muscle groups ready",
                emphasis: recoveryReadiness
            ))
        }

        let primaryAction = primaryActionFor(
            phase: phase,
            workoutName: workoutName,
            proteinRemaining: proteinRemaining,
            calorieRemaining: calorieRemaining,
            recentAnswer: recentAnswer
        )
        let secondaryAction = secondaryActionFor(
            phase: phase,
            scheduleRisk: scheduleRisk,
            painSignal: painSignal,
            trend: context.trend,
            recentAnswer: recentAnswer
        )

        let question = questionFor(
            phase: phase,
            painSignal: painSignal,
            proteinRemaining: proteinRemaining,
            scheduleRisk: scheduleRisk,
            trend: context.trend,
            activeSignals: context.activeSignals
        )

        return TraiPulseBrief(
            phase: phase,
            title: title,
            message: message,
            reasons: Array(reasons.prefix(3)),
            confidence: confidence,
            confidenceLabel: confidenceLabel(for: confidence),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            question: question,
            tomorrowPreview: TraiPulseResponseInterpreter.adaptedTomorrowPreview(
                defaultMinutes: context.tomorrowWorkoutMinutes,
                recent: recentAnswer
            )
        )
    }

    private static func progress(consumed: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0.0 }
        return clamp(Double(consumed) / Double(goal))
    }

    private static func computeTrendRisk(_ trend: TraiPulseTrendSnapshot?) -> Double {
        guard let trend else { return 0.45 }

        let loggingPenalty = (1.0 - trend.loggingConsistency) * 0.35
        let proteinPenalty = (1.0 - trend.proteinHitRate) * 0.35
        let workoutPenalty: Double
        if trend.daysSinceWorkout >= 5 {
            workoutPenalty = 0.30
        } else if trend.daysSinceWorkout >= 3 {
            workoutPenalty = 0.18
        } else {
            workoutPenalty = 0.05
        }
        let streakPenalty: Double
        if trend.lowProteinStreak >= 3 {
            streakPenalty = 0.20
        } else if trend.lowProteinStreak >= 2 {
            streakPenalty = 0.10
        } else {
            streakPenalty = 0
        }

        return clamp(loggingPenalty + proteinPenalty + workoutPenalty + streakPenalty)
    }

    private static func computeScheduleRisk(
        currentHour: Int,
        startHour: Int,
        endHour: Int,
        hasWorkoutToday: Bool,
        hasActiveWorkout: Bool
    ) -> Double {
        guard !hasWorkoutToday && !hasActiveWorkout else { return 0.05 }
        if currentHour < startHour { return 0.25 }
        if currentHour <= endHour {
            let span = max(endHour - startHour, 1)
            let elapsed = max(0, currentHour - startHour)
            return clamp(0.35 + (Double(elapsed) / Double(span)) * 0.45)
        }
        return 0.88
    }

    private static func computeRecoveryReadiness(
        readyMuscleCount: Int,
        activeSignals: [CoachSignalSnapshot]
    ) -> Double {
        let base = clamp(Double(readyMuscleCount) / 8.0)
        let painPenalty = activeSignals
            .filter { $0.domain == .pain }
            .map(\.severity)
            .max() ?? 0.0
        let sleepPenalty = activeSignals
            .filter { $0.domain == .sleep }
            .map(\.severity)
            .max() ?? 0.0
        return clamp(base - (painPenalty * 0.35) - (sleepPenalty * 0.20))
    }

    private static func phaseFor(
        currentHour: Int,
        startHour: Int,
        endHour: Int,
        hasWorkoutToday: Bool,
        hasActiveWorkout: Bool
    ) -> TraiPulseBrief.Phase {
        if hasActiveWorkout { return .onTrack }
        if hasWorkoutToday { return .completed }
        if currentHour < startHour { return .morningPlan }
        if currentHour <= endHour { return currentHour >= endHour - 1 ? .atRisk : .onTrack }
        return .rescue
    }

    private static func titleFor(
        phase: TraiPulseBrief.Phase,
        scheduleRisk: Double,
        painSignal: CoachSignalSnapshot?,
        trend: TraiPulseTrendSnapshot?
    ) -> String {
        if painSignal != nil {
            return "Smart Recovery Mode"
        }
        if let trend, trend.daysSinceWorkout >= 4, phase != .completed {
            return "Let's Rebuild Momentum"
        }
        if let trend, trend.lowProteinStreak >= 3, phase == .completed {
            return "Strong Recovery Finish"
        }

        switch phase {
        case .morningPlan: return "Today's Pulse Plan"
        case .onTrack: return "On Track"
        case .atRisk: return "You Can Still Make Today Count"
        case .rescue:
            return scheduleRisk > 0.9 ? "Let's Save The Day" : "Adaptive Plan"
        case .completed: return "Great Work Today"
        }
    }

    private static func messageFor(
        phase: TraiPulseBrief.Phase,
        scheduleRisk: Double,
        workoutName: String,
        calorieRemaining: Int,
        proteinRemaining: Int,
        painSignal: CoachSignalSnapshot?,
        trend: TraiPulseTrendSnapshot?,
        preferredWorkoutWindow: TraiPulseTimeWindow?,
        recentAnswer: TraiPulseRecentAnswer?
    ) -> String {
        if let painSignal {
            return "\(painSignal.title). Nice job checking in. We'll keep tomorrow pain-safe and still productive."
        }
        if let trend, trend.daysSinceWorkout >= 4, phase != .completed {
            return "You've had a few days off, which is okay. A lighter \(workoutName) block gets momentum back quickly."
        }

        let phaseMessage: String

        switch phase {
        case .morningPlan:
            if let preferredWorkoutWindow, preferredWorkoutWindow != .earlyMorning, preferredWorkoutWindow != .morning {
                phaseMessage = "You usually train in the \(preferredWorkoutWindow.label.lowercased()). Keep energy steady now and execute \(workoutName) later."
            } else {
                phaseMessage = "Start with \(workoutName), then finish with protein so recovery stays strong."
            }
        case .onTrack:
            phaseMessage = "You're in a good rhythm. Keep it simple and close the nutrition gap tonight."
        case .atRisk:
            phaseMessage = "A quick decision still wins this day. Pick full session or a short adaptive version."
        case .rescue:
            if scheduleRisk > 0.9 {
                phaseMessage = "Window slipped, but a short session still protects consistency for tomorrow."
            } else {
                phaseMessage = "Use a lighter backup session and keep momentum moving."
            }
        case .completed:
            let noFoodTonight = recentAnswer.map {
                $0.questionID.contains("protein") &&
                TraiPulseResponseInterpreter.containsNoFoodCue($0.answer)
            } ?? false
            if let trend, trend.lowProteinStreak >= 2 {
                if noFoodTonight {
                    phaseMessage = "Workout done. Since you're done eating tonight, we'll front-load protein tomorrow to break the recent trend."
                } else {
                    phaseMessage = "Workout done. A high-protein meal tonight helps break the recent low-protein trend."
                }
            } else if proteinRemaining > 0 {
                if noFoodTonight {
                    phaseMessage = "Workout done. You're finished eating tonight, so I'll prioritize an easier protein catch-up tomorrow."
                } else {
                    phaseMessage = "Workout done. Add about \(proteinRemaining)g protein to support recovery."
                }
            } else if calorieRemaining > 0 {
                if noFoodTonight {
                    phaseMessage = "Workout done. You're finished eating tonight; we'll reset cleanly for tomorrow."
                } else {
                    phaseMessage = "Workout done. Stay inside your remaining \(calorieRemaining) kcal target."
                }
            } else {
                phaseMessage = "Workout and nutrition lined up well today. Keep hydration and sleep simple tonight."
            }
        }
        return phaseMessage
    }

    private static func questionFor(
        phase: TraiPulseBrief.Phase,
        painSignal: CoachSignalSnapshot?,
        proteinRemaining: Int,
        scheduleRisk: Double,
        trend: TraiPulseTrendSnapshot?,
        activeSignals: [CoachSignalSnapshot]
    ) -> TraiPulseQuestion {
        if let painSignal, !hasRecentQuestionAnswer(id: "pain-follow-up", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "pain-follow-up",
                prompt: "How does \(painSignal.domain.displayName.lowercased()) feel now?",
                mode: .slider(range: 0...10, step: 1, unit: "/10"),
                options: [],
                placeholder: "Any movement that triggered it?",
                isRequired: false
            )
        }

        if (phase == .rescue || scheduleRisk > 0.8) &&
            !hasRecentQuestionAnswer(id: "schedule-rescue", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "schedule-rescue",
                prompt: "What can you commit to tonight?",
                mode: .singleChoice,
                options: [
                    TraiPulseQuestionOption(title: "15 min quick lift"),
                    TraiPulseQuestionOption(title: "30 min full session"),
                    TraiPulseQuestionOption(title: "Recovery walk + protein")
                ],
                placeholder: "Or add a quick note",
                isRequired: false
            )
        }

        if let trend, trend.daysSinceWorkout >= 3, phase != .completed,
           !hasRecentQuestionAnswer(id: "workout-consistency-unblock", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "workout-consistency-unblock",
                prompt: "What helps you get a workout in this week?",
                mode: .singleChoice,
                options: [
                    TraiPulseQuestionOption(title: "Short home session"),
                    TraiPulseQuestionOption(title: "Schedule gym time"),
                    TraiPulseQuestionOption(title: "Need a lighter plan")
                ],
                placeholder: "Optional note",
                isRequired: false
            )
        }

        if let trend, trend.lowProteinStreak >= 2,
           !hasRecentQuestionAnswer(id: "protein-trend-blocker", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "protein-trend-blocker",
                prompt: "What's blocking protein lately?",
                mode: .singleChoice,
                options: [
                    TraiPulseQuestionOption(title: "No time to prep"),
                    TraiPulseQuestionOption(title: "Not hungry"),
                    TraiPulseQuestionOption(title: "Need easy options")
                ],
                placeholder: "Optional note",
                isRequired: false
            )
        }

        if let trend, trend.loggingConsistency < 0.5,
           !hasRecentQuestionAnswer(id: "logging-consistency", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "logging-consistency",
                prompt: "Want a faster logging setup?",
                mode: .multipleChoice,
                options: [
                    TraiPulseQuestionOption(title: "1-tap repeat meals"),
                    TraiPulseQuestionOption(title: "Photo-first logging"),
                    TraiPulseQuestionOption(title: "Reminder prompts")
                ],
                placeholder: "Optional note",
                isRequired: false
            )
        }

        if proteinRemaining >= 35 &&
            !hasRecentQuestionAnswer(id: "protein-close", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "protein-close",
                prompt: "How do you want to close protein today?",
                mode: .multipleChoice,
                options: [
                    TraiPulseQuestionOption(title: "Shake"),
                    TraiPulseQuestionOption(title: "Greek yogurt"),
                    TraiPulseQuestionOption(title: "Lean dinner"),
                    TraiPulseQuestionOption(title: "Need suggestions")
                ],
                placeholder: "Add food preference",
                isRequired: false
            )
        }

        if !hasRecentQuestionAnswer(id: "readiness-scan", signals: activeSignals) {
            return TraiPulseQuestion(
                id: "readiness-scan",
                prompt: "Quick readiness scan for tomorrow?",
                mode: .singleChoice,
                options: [
                    TraiPulseQuestionOption(title: "Push"),
                    TraiPulseQuestionOption(title: "Balanced"),
                    TraiPulseQuestionOption(title: "Keep it light")
                ],
                placeholder: "Optional note",
                isRequired: false
            )
        }

        return TraiPulseQuestion(
            id: "open-note",
            prompt: "Anything I should adapt for tomorrow?",
            mode: .note(maxLength: 180),
            options: [],
            placeholder: "Type a quick note",
            isRequired: false
        )
    }

    private static func hasRecentQuestionAnswer(id: String, signals: [CoachSignalSnapshot]) -> Bool {
        signals.contains { signal in
            signal.source == .dashboardNote &&
            signal.detail.contains("[PulseQuestion:\(id)]")
        }
    }

    private static func trendReasons(for trend: TraiPulseTrendSnapshot?) -> [TraiPulseReason] {
        guard let trend else { return [] }

        var reasons: [TraiPulseReason] = []
        reasons.append(
            TraiPulseReason(
                text: "7d logging \(trend.daysWithFoodLogs)/\(trend.daysWindow) days",
                emphasis: trend.loggingConsistency
            )
        )

        if trend.lowProteinStreak >= 2 {
            reasons.append(
                TraiPulseReason(
                    text: "Protein under target \(trend.lowProteinStreak)d streak",
                    emphasis: 0.8
                )
            )
        } else {
            reasons.append(
                TraiPulseReason(
                    text: "Protein hit \(trend.proteinTargetHitDays)/\(trend.daysWindow) days",
                    emphasis: trend.proteinHitRate
                )
            )
        }

        if trend.daysSinceWorkout >= 3 {
            reasons.append(
                TraiPulseReason(
                    text: "Last workout \(trend.daysSinceWorkout)d ago",
                    emphasis: 0.82
                )
            )
        } else {
            reasons.append(
                TraiPulseReason(
                    text: "Workout days \(trend.workoutDays)/\(trend.daysWindow)",
                    emphasis: Double(trend.workoutDays) / Double(max(trend.daysWindow, 1))
                )
            )
        }

        return reasons
    }

    private static func primaryActionFor(
        phase: TraiPulseBrief.Phase,
        workoutName: String,
        proteinRemaining: Int,
        calorieRemaining: Int,
        recentAnswer: TraiPulseRecentAnswer?
    ) -> TraiPulseAction {
        let noFoodTonight = recentAnswer.map {
            $0.questionID.contains("protein") &&
            TraiPulseResponseInterpreter.containsNoFoodCue($0.answer)
        } ?? false

        if phase == .completed && noFoodTonight {
            return TraiPulseAction(
                kind: .openChat,
                title: "Plan Tomorrow Protein",
                subtitle: "No more food tonight"
            )
        }

        if let recentAnswer {
            let answer = recentAnswer.answer.lowercased()
            if recentAnswer.questionID.contains("schedule-rescue") {
                if answer.contains("15 min") {
                    return TraiPulseAction(
                        kind: .startWorkout,
                        title: "Start 15-Min Quick Lift",
                        subtitle: "Fast consistency win"
                    )
                }
                if answer.contains("30 min") {
                    return TraiPulseAction(
                        kind: .startWorkout,
                        title: "Start 30-Min Session",
                        subtitle: "Locked in with your check-in"
                    )
                }
                if answer.contains("recovery walk") {
                    return TraiPulseAction(
                        kind: .startWorkout,
                        title: "Start Recovery Walk",
                        subtitle: "Low-friction momentum"
                    )
                }
            }

            if recentAnswer.questionID.contains("protein") {
                if answer.contains("shake") {
                    return TraiPulseAction(kind: .logFood, title: "Log Protein Shake", subtitle: "Quick close-out")
                }
                if answer.contains("yogurt") {
                    return TraiPulseAction(kind: .logFood, title: "Log Greek Yogurt", subtitle: "Fast protein")
                }
                if answer.contains("lean dinner") {
                    return TraiPulseAction(kind: .logFood, title: "Log Lean Dinner", subtitle: "Recovery support")
                }
            }
        }

        switch phase {
        case .completed:
            if proteinRemaining > 0 {
                return TraiPulseAction(
                    kind: .logFood,
                    title: "Log Protein Meal",
                    subtitle: "Close recovery target"
                )
            }
            if calorieRemaining > 0 {
                return TraiPulseAction(
                    kind: .logFood,
                    title: "Log Final Meal",
                    subtitle: "Finish within target"
                )
            }
            return TraiPulseAction(
                kind: .logFood,
                title: "Log Recovery Meal",
                subtitle: "Keep the streak clean"
            )
        default:
            return TraiPulseAction(
                kind: .startWorkout,
                title: "Start \(workoutName)",
                subtitle: nil
            )
        }
    }

    private static func secondaryActionFor(
        phase: TraiPulseBrief.Phase,
        scheduleRisk: Double,
        painSignal: CoachSignalSnapshot?,
        trend: TraiPulseTrendSnapshot?,
        recentAnswer: TraiPulseRecentAnswer?
    ) -> TraiPulseAction {
        let noFoodTonight = recentAnswer.map {
            $0.questionID.contains("protein") &&
            TraiPulseResponseInterpreter.containsNoFoodCue($0.answer)
        } ?? false

        if phase == .completed && noFoodTonight {
            return TraiPulseAction(
                kind: .openChat,
                title: "Set Morning Plan",
                subtitle: "Protein-first tomorrow"
            )
        }

        if let recentAnswer {
            let answer = recentAnswer.answer.lowercased()
            if recentAnswer.questionID.contains("protein"), answer.contains("need suggestions") {
                return TraiPulseAction(
                    kind: .openChat,
                    title: "Get Easy Protein Ideas",
                    subtitle: "Based on your preference"
                )
            }

            if recentAnswer.questionID.contains("workout-consistency"), answer.contains("need a lighter plan") {
                return TraiPulseAction(
                    kind: .openChat,
                    title: "Build Lighter Plan",
                    subtitle: "Match your consistency goal"
                )
            }

            if recentAnswer.questionID.contains("logging-consistency"), answer.contains("photo") {
                return TraiPulseAction(
                    kind: .logFood,
                    title: "Open Food Camera",
                    subtitle: "Photo-first logging"
                )
            }
        }

        if painSignal != nil {
            return TraiPulseAction(
                kind: .openChat,
                title: "Adjust with Trai",
                subtitle: "Pain-aware plan"
            )
        }

        if phase == .completed, let trend, trend.lowProteinStreak >= 2 {
            return TraiPulseAction(
                kind: .openChat,
                title: "Get Meal Ideas",
                subtitle: "Fast protein options"
            )
        }

        if phase == .rescue || scheduleRisk > 0.88 {
            return TraiPulseAction(
                kind: .openChat,
                title: "Build Quick Plan",
                subtitle: "2-minute adjustment"
            )
        }

        if let trend, trend.loggingConsistency < 0.5 {
            return TraiPulseAction(
                kind: .logFood,
                title: "Quick Log",
                subtitle: "Rebuild consistency"
            )
        }

        return TraiPulseAction(
            kind: .openChat,
            title: "Open Trai Coach",
            subtitle: "Context-aware guidance"
        )
    }

    private static func confidenceLabel(for confidence: Double) -> String {
        switch confidence {
        case ..<0.34: "Low data confidence"
        case ..<0.67: "Medium data confidence"
        default: "High data confidence"
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
