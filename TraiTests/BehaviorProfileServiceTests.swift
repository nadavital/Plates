import XCTest
@testable import Trai

final class BehaviorProfileServiceTests: XCTestCase {
    func testBuildProfileExcludesDismissedEventsAndTracksLatestActionTime() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let events = [
            event(
                actionKey: BehaviorActionKey.logFood,
                outcome: .completed,
                at: now.addingTimeInterval(-6 * 3600)
            ),
            event(
                actionKey: BehaviorActionKey.logFood,
                outcome: .dismissed,
                at: now.addingTimeInterval(-2 * 3600)
            ),
            event(
                actionKey: BehaviorActionKey.logFood,
                outcome: .performed,
                at: now.addingTimeInterval(-1 * 3600)
            ),
            event(
                actionKey: BehaviorActionKey.logWeight,
                outcome: .completed,
                at: now.addingTimeInterval(-26 * 3600)
            )
        ]

        let profile = BehaviorProfileService.buildProfile(now: now, events: events, windowDays: 3)

        XCTAssertEqual(profile.actionCounts[BehaviorActionKey.logFood], 2)
        XCTAssertEqual(profile.actionCounts[BehaviorActionKey.logWeight], 1)
        XCTAssertEqual(profile.daysSinceLastAction(BehaviorActionKey.logWeight, now: now), 1)
        XCTAssertEqual(profile.daysSinceLastAction(BehaviorActionKey.logFood, now: now), 0)
    }

    func testLikelyTimeLabelsUsesBucketsAndMinimumEventThreshold() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let events = [
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: now, hour: 6)),
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: now, hour: 7)),
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: now, hour: 8)),
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: previousDay, hour: 20))
        ]

        let profile = BehaviorProfileService.buildProfile(now: now, events: events, windowDays: 2)
        let labels = profile.likelyTimeLabels(
            for: BehaviorActionKey.logWeight,
            maxLabels: 2,
            minimumEvents: 3
        )

        XCTAssertEqual(labels.first, "Morning (4-9 AM)")
        XCTAssertEqual(labels.count, 2)
    }

    func testLikelyTimeLabelsReturnsEmptyWhenEventCountBelowThreshold() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let events = [
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: now, hour: 7)),
            event(actionKey: BehaviorActionKey.logWeight, outcome: .completed, at: date(relativeTo: now, hour: 8))
        ]

        let profile = BehaviorProfileService.buildProfile(now: now, events: events, windowDays: 2)
        let labels = profile.likelyTimeLabels(
            for: BehaviorActionKey.logWeight,
            maxLabels: 2,
            minimumEvents: 3
        )

        XCTAssertTrue(labels.isEmpty)
    }

    func testHourlyPreferenceScoreIncludesNeighboringHours() {
        let snapshot = BehaviorProfileSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_736_208_000),
            windowDays: 7,
            actionCounts: [BehaviorActionKey.logWeight: 4],
            actionHourlyCounts: [
                BehaviorActionKey.logWeight: [
                    7: 1,
                    8: 2,
                    9: 1
                ]
            ],
            lastActionAt: [BehaviorActionKey.logWeight: Date(timeIntervalSince1970: 1_736_208_000)]
        )

        let score = snapshot.hourlyPreferenceScore(
            for: BehaviorActionKey.logWeight,
            hour: 8,
            minimumEvents: 2
        )

        XCTAssertEqual(score, 0.675, accuracy: 0.0001)
    }

    func testDaysSinceLastActionUsesDayBoundaries() {
        let calendar = Calendar.current
        let baseline = Date(timeIntervalSince1970: 1_736_208_000)
        let todayNoon = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: baseline
        ) ?? baseline
        let yesterdayNight = calendar.date(byAdding: .hour, value: -13, to: todayNoon) ?? todayNoon

        let snapshot = BehaviorProfileSnapshot(
            generatedAt: todayNoon,
            windowDays: 7,
            actionCounts: [BehaviorActionKey.logFood: 1],
            actionHourlyCounts: [BehaviorActionKey.logFood: [calendar.component(.hour, from: yesterdayNight): 1]],
            lastActionAt: [BehaviorActionKey.logFood: yesterdayNight]
        )

        XCTAssertEqual(snapshot.daysSinceLastAction(BehaviorActionKey.logFood, now: todayNoon), 1)
    }

    private func event(
        actionKey: String,
        outcome: BehaviorOutcome,
        at date: Date
    ) -> BehaviorEvent {
        BehaviorEvent(
            actionKey: actionKey,
            domain: .general,
            surface: .system,
            outcome: outcome,
            occurredAt: date
        )
    }

    private func date(relativeTo base: Date, hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: base)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? base
    }
}
