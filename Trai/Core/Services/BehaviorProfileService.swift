//
//  BehaviorProfileService.swift
//  Trai
//
//  Derives compact behavior patterns from app-wide behavior events.
//

import Foundation

struct BehaviorProfileSnapshot {
    let generatedAt: Date
    let windowDays: Int
    let actionCounts: [String: Int]
    let actionHourlyCounts: [String: [Int: Int]]
    let lastActionAt: [String: Date]

    func daysSinceLastAction(_ actionKey: String, now: Date = .now) -> Int? {
        guard let last = lastActionAt[actionKey] else { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let lastStart = calendar.startOfDay(for: last)
        let delta = calendar.dateComponents([.day], from: lastStart, to: dayStart).day ?? 0
        return max(delta, 0)
    }

    func likelyTimeLabels(
        for actionKey: String,
        maxLabels: Int = 2,
        minimumEvents: Int = 3
    ) -> [String] {
        guard let hourly = actionHourlyCounts[actionKey], !hourly.isEmpty else { return [] }
        guard actionCounts[actionKey, default: 0] >= minimumEvents else { return [] }

        var bucketCounts: [String: Int] = [:]
        for (hour, count) in hourly where count > 0 {
            let label = Self.bucketLabel(for: hour)
            bucketCounts[label, default: 0] += count
        }

        return bucketCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(max(0, maxLabels))
            .map(\.key)
    }

    func hourlyPreferenceScore(
        for actionKey: String,
        hour: Int,
        minimumEvents: Int = 3
    ) -> Double {
        guard let hourly = actionHourlyCounts[actionKey], !hourly.isEmpty else { return 0 }
        let totalCount = actionCounts[actionKey, default: 0]
        guard totalCount >= minimumEvents else { return 0 }

        let normalizedHour = ((hour % 24) + 24) % 24
        let previousHour = (normalizedHour + 23) % 24
        let nextHour = (normalizedHour + 1) % 24

        let exactWeight = Double(hourly[normalizedHour, default: 0]) / Double(totalCount)
        let neighborWeight = Double(hourly[previousHour, default: 0] + hourly[nextHour, default: 0]) / Double(totalCount)

        return min(max(exactWeight + (neighborWeight * 0.35), 0), 1)
    }

    static func bucketLabel(for hour: Int) -> String {
        switch hour {
        case 4..<9:
            return "Morning (4-9 AM)"
        case 9..<12:
            return "Late Morning (9-12 PM)"
        case 12..<15:
            return "Early Afternoon (12-3 PM)"
        case 15..<18:
            return "Mid-Afternoon (3-6 PM)"
        case 18..<22:
            return "Evening (6-10 PM)"
        default:
            return "Night (10 PM-4 AM)"
        }
    }
}

enum BehaviorProfileService {
    static func buildProfile(
        now: Date,
        events: [BehaviorEvent],
        windowDays: Int = 45
    ) -> BehaviorProfileSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -max(windowDays - 1, 0), to: now) ?? now

        let relevantEvents = events.filter { event in
            event.occurredAt >= start &&
            event.occurredAt <= now &&
            event.outcome != .dismissed
        }

        var actionCounts: [String: Int] = [:]
        var actionHourlyCounts: [String: [Int: Int]] = [:]
        var lastActionAt: [String: Date] = [:]

        for event in relevantEvents {
            let key = event.actionKey
            guard !key.isEmpty else { continue }

            actionCounts[key, default: 0] += 1

            let hour = calendar.component(.hour, from: event.occurredAt)
            var hourly = actionHourlyCounts[key] ?? [:]
            hourly[hour, default: 0] += 1
            actionHourlyCounts[key] = hourly

            if let existing = lastActionAt[key] {
                if event.occurredAt > existing {
                    lastActionAt[key] = event.occurredAt
                }
            } else {
                lastActionAt[key] = event.occurredAt
            }
        }

        return BehaviorProfileSnapshot(
            generatedAt: now,
            windowDays: windowDays,
            actionCounts: actionCounts,
            actionHourlyCounts: actionHourlyCounts,
            lastActionAt: lastActionAt
        )
    }
}
