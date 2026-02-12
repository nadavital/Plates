//
//  TraiPulseResponseInterpreter.swift
//  Trai
//
//  Interprets Pulse question responses into short-term signals and optional durable memory.
//

import Foundation

struct TraiPulseMemoryCandidate: Hashable, Sendable {
    let content: String
    let category: MemoryCategory
    let topic: MemoryTopic
    let importance: Int
}

struct TraiPulseResponseInterpretation: Sendable {
    let signalTitle: String
    let domain: CoachSignalDomain
    let severity: Double
    let confidence: Double
    let expiresAfter: TimeInterval
    let acknowledgement: String
    let handoffPrompt: String
    let adaptationLine: String
    let memoryCandidate: TraiPulseMemoryCandidate?
}

struct TraiPulseRecentAnswer: Hashable, Sendable {
    let questionID: String
    let answer: String
    let domain: CoachSignalDomain
    let createdAt: Date
    let ageHours: Double
}

enum TraiPulseResponseInterpreter {
    static func containsNoFoodCue(_ answer: String) -> Bool {
        let lower = answer.lowercased()
        return containsAny(
            lower,
            [
                "done eating",
                "already ate",
                "not hungry",
                "too full",
                "full",
                "no more food",
                "finished eating"
            ]
        )
    }

    static func interpret(question: TraiPulseQuestion, answer: String) -> TraiPulseResponseInterpretation {
        let normalizedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedAnswer.lowercased()

        let domain = domainFor(questionID: question.id)
        let painScore = parsePainScore(from: normalizedAnswer)

        var severity: Double = 0.45
        var confidence: Double = 0.74
        var expiresAfter: TimeInterval = 48 * 60 * 60
        var signalTitle = "Pulse Check-In"

        switch domain {
        case .pain:
            severity = max(0.38, Double(painScore ?? 5) / 10.0)
            confidence = 0.84
            expiresAfter = 72 * 60 * 60
            signalTitle = "Pain-aware adjustment"
        case .schedule:
            severity = lower.contains("can't") || lower.contains("no time") ? 0.62 : 0.5
            confidence = 0.78
            expiresAfter = 48 * 60 * 60
            signalTitle = "Schedule preference"
        case .nutrition:
            severity = 0.48
            confidence = 0.76
            expiresAfter = 36 * 60 * 60
            signalTitle = "Nutrition preference"
        case .readiness:
            severity = lower.contains("light") ? 0.52 : 0.4
            confidence = 0.74
            expiresAfter = 36 * 60 * 60
            signalTitle = "Readiness input"
        case .recovery, .sleep, .stress, .general:
            severity = 0.42
            confidence = 0.72
            expiresAfter = 48 * 60 * 60
            signalTitle = "Pulse context"
        }

        let acknowledgement = acknowledgementFor(questionID: question.id, answer: normalizedAnswer, domain: domain)
        let handoffPrompt = "Pulse check-in: \(question.prompt) Answer: \(normalizedAnswer). Please adapt tonight and tomorrow with a short practical plan."
        let adaptationLine = adaptationLineFor(questionID: question.id, answer: normalizedAnswer, domain: domain)

        return TraiPulseResponseInterpretation(
            signalTitle: signalTitle,
            domain: domain,
            severity: clamp(severity),
            confidence: clamp(confidence),
            expiresAfter: expiresAfter,
            acknowledgement: acknowledgement,
            handoffPrompt: handoffPrompt,
            adaptationLine: adaptationLine,
            memoryCandidate: memoryCandidateFor(questionID: question.id, answer: normalizedAnswer, lower: lower, painScore: painScore)
        )
    }

    static func recentPulseAnswer(from signals: [CoachSignalSnapshot], now: Date = .now) -> TraiPulseRecentAnswer? {
        guard let latest = signals
            .filter({ $0.source == .dashboardNote })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { $0.detail.contains("[PulseQuestion:") }) else {
            return nil
        }

        guard let questionID = parseQuestionID(from: latest.detail),
              let answer = parseAnswer(from: latest.detail),
              !answer.isEmpty else {
            return nil
        }

        let ageHours = max(0, now.timeIntervalSince(latest.createdAt) / 3600)
        return TraiPulseRecentAnswer(
            questionID: questionID,
            answer: answer,
            domain: latest.domain,
            createdAt: latest.createdAt,
            ageHours: ageHours
        )
    }

    static func carryoverReason(for recent: TraiPulseRecentAnswer) -> String {
        let prefix = recent.ageHours <= 18 ? "You said" : "Earlier you said"

        if recent.questionID.contains("schedule") {
            return "\(prefix) \"\(shorten(recent.answer))\" for timing"
        }
        if recent.questionID.contains("protein") {
            if containsNoFoodCue(recent.answer) {
                return recent.ageHours <= 18
                    ? "You said you're done eating tonight"
                    : "Earlier you said you were done eating tonight"
            }
            return "\(prefix) \"\(shorten(recent.answer))\" for protein"
        }
        if recent.questionID.contains("readiness") {
            return "\(prefix) \"\(shorten(recent.answer))\" for intensity"
        }
        if recent.questionID.contains("pain") {
            return "\(prefix) \"\(shorten(recent.answer))\" about discomfort"
        }
        return "\(prefix) \"\(shorten(recent.answer))\""
    }

    static func adaptedTomorrowPreview(defaultMinutes: Int, recent: TraiPulseRecentAnswer?) -> String {
        guard let recent else {
            return "Tomorrow: \(defaultMinutes) min focus with adaptive adjustments."
        }

        let answer = recent.answer.lowercased()
        if recent.questionID.contains("readiness") {
            if answer.contains("push") {
                return "Tomorrow: \(defaultMinutes + 10) min push-biased plan, with recovery checkpoints."
            }
            if answer.contains("light") {
                return "Tomorrow: \(max(defaultMinutes - 10, 20)) min lighter plan to keep momentum without overload."
            }
        }

        if recent.questionID.contains("schedule") {
            return "Tomorrow: plan shaped around \(shorten(recent.answer, maxLength: 28))."
        }

        if recent.questionID.contains("protein") {
            if containsNoFoodCue(recent.answer) {
                return "Tomorrow: protein catch-up plan queued since you're done eating tonight."
            }
            return "Tomorrow: meal suggestions will prioritize \(shorten(recent.answer, maxLength: 26))."
        }

        return "Tomorrow: \(defaultMinutes) min focus tuned to your latest check-in."
    }

    private static func domainFor(questionID: String) -> CoachSignalDomain {
        if questionID.contains("pain") {
            return .pain
        }
        if questionID.contains("schedule") || questionID.contains("workout-consistency") || questionID.contains("logging-consistency") {
            return .schedule
        }
        if questionID.contains("protein") {
            return .nutrition
        }
        if questionID.contains("readiness") {
            return .readiness
        }
        return .general
    }

    private static func memoryCandidateFor(
        questionID: String,
        answer: String,
        lower: String,
        painScore: Int?
    ) -> TraiPulseMemoryCandidate? {
        if questionID.contains("protein") {
            if containsNoFoodCue(answer) {
                return TraiPulseMemoryCandidate(
                    content: "Often done eating by evening; prefers protein catch-up strategy next day.",
                    category: .habit,
                    topic: .schedule,
                    importance: 3
                )
            }
            let normalized = answer.replacingOccurrences(of: "Need suggestions", with: "easy options")
            return TraiPulseMemoryCandidate(
                content: "Prefers \(normalized.lowercased()) when closing daily protein.",
                category: .preference,
                topic: .food,
                importance: 3
            )
        }

        if questionID.contains("logging-consistency") {
            return TraiPulseMemoryCandidate(
                content: "Prefers \(answer.lowercased()) for faster nutrition logging.",
                category: .preference,
                topic: .food,
                importance: 3
            )
        }

        if questionID.contains("schedule") || questionID.contains("workout-consistency") {
            return TraiPulseMemoryCandidate(
                content: "Workout consistency works better with \(answer.lowercased()).",
                category: .habit,
                topic: .schedule,
                importance: 3
            )
        }

        if questionID.contains("readiness") {
            return TraiPulseMemoryCandidate(
                content: "Prefers \(answer.lowercased()) training intensity on readiness check-ins.",
                category: .preference,
                topic: .workout,
                importance: 3
            )
        }

        if questionID.contains("pain") || containsAny(lower, ["shoulder", "knee", "back", "elbow"]) {
            let scoreText = painScore.map { " (\($0)/10)" } ?? ""
            return TraiPulseMemoryCandidate(
                content: "Watch for discomfort signals\(scoreText): \(answer.lowercased()).",
                category: .restriction,
                topic: .workout,
                importance: 4
            )
        }

        return nil
    }

    private static func acknowledgementFor(questionID: String, answer: String, domain: CoachSignalDomain) -> String {
        if questionID.contains("pain") {
            return "Saved. I'll keep your next workout pain-aware and adjust exercise choices."
        }
        if questionID.contains("protein") {
            if containsNoFoodCue(answer) {
                return "Saved: no more food tonight. Protein strategy moves to tomorrow."
            }
            return "Nice. I'll bias meal ideas toward \(answer.lowercased()) so hitting protein is easier."
        }
        if questionID.contains("schedule") || questionID.contains("workout-consistency") {
            return "Perfect. I'll time nudges and backups around \(answer.lowercased())."
        }
        if questionID.contains("logging-consistency") {
            return "Great signal. I'll shape logging suggestions around \(answer.lowercased())."
        }
        if questionID.contains("readiness") {
            return "Got it. I'll tune tomorrow's intensity to \(answer.lowercased())."
        }

        switch domain {
        case .nutrition:
            return "Saved. I'll tune your nutrition suggestions from this."
        case .schedule:
            return "Saved. I'll adjust timing and action order around this."
        case .pain, .recovery:
            return "Saved. I'll keep recommendations recovery-aware."
        case .readiness:
            return "Saved. I'll adapt tomorrow's plan from this signal."
        case .sleep, .stress, .general:
            return "Saved. I'll apply this in your next Pulse recommendation."
        }
    }

    private static func adaptationLineFor(questionID: String, answer: String, domain: CoachSignalDomain) -> String {
        if questionID.contains("schedule") || questionID.contains("workout-consistency") {
            return "Adapting timing around: \(shorten(answer))."
        }
        if questionID.contains("protein") {
            if containsNoFoodCue(answer) {
                return "Tonight food prompts are paused; tomorrow protein planning is prioritized."
            }
            return "Next meal suggestions will prioritize: \(shorten(answer))."
        }
        if questionID.contains("readiness") {
            return "Tomorrow intensity tuned toward: \(shorten(answer))."
        }
        if questionID.contains("pain") {
            return "Recovery mode adjusted for: \(shorten(answer))."
        }

        switch domain {
        case .nutrition:
            return "Nutrition guidance tuned to your latest check-in."
        case .schedule:
            return "Plan timing tuned to your latest check-in."
        case .pain, .recovery:
            return "Recovery guidance tuned to your latest check-in."
        case .readiness:
            return "Readiness guidance tuned to your latest check-in."
        case .sleep, .stress, .general:
            return "Pulse is adapting from your latest check-in."
        }
    }

    private static func parseQuestionID(from detail: String) -> String? {
        guard let markerStart = detail.range(of: "[PulseQuestion:") else { return nil }
        guard let markerEnd = detail[markerStart.upperBound...].firstIndex(of: "]") else { return nil }
        return String(detail[markerStart.upperBound..<markerEnd])
    }

    private static func parseAnswer(from detail: String) -> String? {
        guard let answerRange = detail.range(of: "Answer:", options: .caseInsensitive) else { return nil }
        let answer = detail[answerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? nil : answer
    }

    private static func parsePainScore(from answer: String) -> Int? {
        let digits = answer
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first
        guard let digits else { return nil }
        return min(max(digits, 0), 10)
    }

    private static func shorten(_ text: String, maxLength: Int = 32) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
