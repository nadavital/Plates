import XCTest
@testable import Trai

@MainActor
final class DailyCoachEngineTests: XCTestCase {
    func testMakeRecommendationNutritionFocusPrioritizesFoodAction() {
        let context = makeContext(
            now: dateAt(hour: 10),
            hasWorkoutToday: false,
            hasActiveWorkout: false
        )
        let preferences = DailyCoachPreferences(
            effortMode: .balanced,
            workoutWindow: .flexible,
            tomorrowFocus: .nutrition,
            tomorrowWorkoutMinutes: 40
        )

        let recommendation = DailyCoachEngine.makeRecommendation(context: context, preferences: preferences)

        XCTAssertEqual(recommendation.primaryAction.kind, .logFood)
        XCTAssertEqual(recommendation.secondaryAction.kind, .startWorkout)
    }

    func testMakeRecommendationWorkoutFocusUsesFallbackWorkoutWhenPhaseCompleted() {
        let context = makeContext(
            now: dateAt(hour: 18),
            hasWorkoutToday: true,
            hasActiveWorkout: false,
            proteinConsumed: 70,
            proteinGoal: 150
        )
        let preferences = DailyCoachPreferences(
            effortMode: .balanced,
            workoutWindow: .flexible,
            tomorrowFocus: .workout,
            tomorrowWorkoutMinutes: 45
        )

        let recommendation = DailyCoachEngine.makeRecommendation(context: context, preferences: preferences)

        XCTAssertEqual(recommendation.primaryAction.kind, .startWorkout)
        XCTAssertEqual(recommendation.secondaryAction.kind, .logFood)
        XCTAssertTrue(recommendation.primaryAction.title.contains("Start"))
    }

    func testMakeRecommendationRescuePhaseBuildsSwapOptions() {
        let context = makeContext(
            now: dateAt(hour: 23),
            hasWorkoutToday: false,
            hasActiveWorkout: false
        )
        let preferences = DailyCoachPreferences(
            effortMode: .consistency,
            workoutWindow: .morning,
            tomorrowFocus: .both,
            tomorrowWorkoutMinutes: 50
        )

        let recommendation = DailyCoachEngine.makeRecommendation(context: context, preferences: preferences)

        XCTAssertEqual(recommendation.phase, .rescue)
        XCTAssertEqual(recommendation.swaps.count, 3)
        XCTAssertEqual(recommendation.swaps.first?.action.kind, .startWorkout)
    }

    private func makeContext(
        now: Date,
        hasWorkoutToday: Bool,
        hasActiveWorkout: Bool,
        proteinConsumed: Int = 60,
        proteinGoal: Int = 150
    ) -> DailyCoachContext {
        DailyCoachContext(
            now: now,
            hasWorkoutToday: hasWorkoutToday,
            hasActiveWorkout: hasActiveWorkout,
            caloriesConsumed: 1_100,
            calorieGoal: 2_000,
            proteinConsumed: proteinConsumed,
            proteinGoal: proteinGoal,
            readyMuscleCount: 4,
            recommendedWorkoutName: "Upper Body",
            activeSignals: [],
            trend: nil,
            patternProfile: .empty
        )
    }

    private func dateAt(hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: 1_736_208_000))
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_736_208_000)
    }
}
