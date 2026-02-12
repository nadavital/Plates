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

        return anomalies.sorted { $0.utility > $1.utility }
    }

    private static func rankedActions(
        context: TraiPulseInputContext,
        patternProfile: TraiPulsePatternProfile,
        proteinRemaining: Int
    ) -> [RankedSnippet] {
        let workoutTitle = context.recommendedWorkoutName ?? "recommended workout"
        var ranked: [RankedSnippet] = []

        if !context.hasWorkoutToday && !context.hasActiveWorkout {
            ranked.append(
                RankedSnippet(
                    text: "Start \(workoutTitle)",
                    utility: clamp(0.74 + patternProfile.affinity(for: .startWorkout) * 0.22)
                )
            )
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
                    text: "Open Trai for a pain-aware adjustment",
                    utility: clamp(0.72 + patternProfile.affinity(for: .openChat) * 0.18)
                )
            )
        } else {
            ranked.append(
                RankedSnippet(
                    text: "Open Trai to refine tomorrow's plan",
                    utility: clamp(0.55 + patternProfile.affinity(for: .openChat) * 0.24)
                )
            )
        }

        return ranked.sorted { $0.utility > $1.utility }
    }

    private static func select(from snippets: [RankedSnippet], limit: Int) -> [String] {
        Array(snippets.prefix(max(limit, 0)).map(\.text))
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
}
