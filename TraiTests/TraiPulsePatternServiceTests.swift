import XCTest
@testable import Trai

final class TraiPulsePatternServiceTests: XCTestCase {
    func testBuildProfileNormalizesProteinAnchorsAndWorkoutWindow() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let profile = UserProfile()
        profile.dailyProteinGoal = 120

        let foodEntries = [
            food(name: "Chicken breast!!!", protein: 35, calories: 450, at: date(daysFrom: now, offset: -1, hour: 12)),
            food(name: "chicken-breast", protein: 38, calories: 430, at: date(daysFrom: now, offset: -2, hour: 13)),
            food(name: "Greek Yogurt", protein: 32, calories: 210, at: date(daysFrom: now, offset: -3, hour: 9))
        ]

        let workouts = [
            workout(at: date(daysFrom: now, offset: -1, hour: 18)),
            workout(at: date(daysFrom: now, offset: -3, hour: 19))
        ]

        let built = TraiPulsePatternService.buildProfile(
            now: now,
            foodEntries: foodEntries,
            workouts: workouts,
            liveWorkouts: [],
            suggestionUsage: [],
            behaviorEvents: [],
            profile: profile
        )

        XCTAssertEqual(built.commonProteinAnchors.first, "Chicken Breast")
        XCTAssertTrue(built.commonProteinAnchors.contains("Greek Yogurt"))
        XCTAssertEqual(built.strongestMealWindow(), .midday)
    }

    func testBuildProfileWeightsBehaviorAffinityOverLegacySuggestionUsage() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)

        let behaviorEvents = [
            BehaviorEvent(
                actionKey: BehaviorActionKey.startWorkout,
                domain: .workout,
                surface: .dashboard,
                outcome: .performed,
                occurredAt: now.addingTimeInterval(-1_800)
            )
        ]

        let legacyUsage = SuggestionUsage(suggestionType: "meal_log")
        legacyUsage.tapCount = 20

        let built = TraiPulsePatternService.buildProfile(
            now: now,
            foodEntries: [],
            workouts: [],
            liveWorkouts: [],
            suggestionUsage: [legacyUsage],
            behaviorEvents: behaviorEvents,
            profile: nil
        )

        let workoutAffinity = built.actionAffinity[TraiPulseAction.Kind.startWorkout.rawValue] ?? 0
        let foodAffinity = built.actionAffinity[TraiPulseAction.Kind.logFood.rawValue] ?? 0

        XCTAssertGreaterThan(workoutAffinity, foodAffinity)
        XCTAssertEqual(workoutAffinity, 0.85, accuracy: 0.0001)
        XCTAssertEqual(foodAffinity, 0.15, accuracy: 0.0001)
    }

    func testBuildTrendSnapshotComputesStreakAndWorkoutDistance() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let profile = UserProfile()
        profile.dailyProteinGoal = 100
        profile.dailyCalorieGoal = 2_000

        let foodEntries = [
            food(name: "Day3", protein: 90, calories: 1700, at: date(daysFrom: now, offset: -3, hour: 12)),
            food(name: "Day2", protein: 50, calories: 1700, at: date(daysFrom: now, offset: -2, hour: 12)),
            food(name: "Day1", protein: 40, calories: 1700, at: date(daysFrom: now, offset: -1, hour: 12)),
            food(name: "Day0", protein: 30, calories: 1700, at: date(daysFrom: now, offset: 0, hour: 12))
        ]

        let workouts = [
            workout(at: date(daysFrom: now, offset: -1, hour: 18))
        ]
        let liveWorkouts = [
            liveWorkout(at: date(daysFrom: now, offset: -3, hour: 17))
        ]

        let snapshot = TraiPulsePatternService.buildTrendSnapshot(
            now: now,
            foodEntries: foodEntries,
            workouts: workouts,
            liveWorkouts: liveWorkouts,
            profile: profile,
            daysWindow: 4
        )

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.daysWithFoodLogs, 4)
        XCTAssertEqual(snapshot?.proteinTargetHitDays, 1)
        XCTAssertEqual(snapshot?.calorieTargetHitDays, 4)
        XCTAssertEqual(snapshot?.lowProteinStreak, 3)
        XCTAssertEqual(snapshot?.workoutDays, 2)
        XCTAssertEqual(snapshot?.daysSinceWorkout, 1)
    }

    private func food(name: String, protein: Double, calories: Int, at date: Date) -> FoodEntry {
        let entry = FoodEntry()
        entry.name = name
        entry.proteinGrams = protein
        entry.calories = calories
        entry.loggedAt = date
        return entry
    }

    private func workout(at date: Date) -> WorkoutSession {
        let session = WorkoutSession()
        session.loggedAt = date
        return session
    }

    private func liveWorkout(at date: Date) -> LiveWorkout {
        let workout = LiveWorkout()
        workout.startedAt = date
        return workout
    }

    private func date(daysFrom base: Date, offset: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: offset, to: base) ?? base
        var components = calendar.dateComponents([.year, .month, .day], from: shifted)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? shifted
    }
}
