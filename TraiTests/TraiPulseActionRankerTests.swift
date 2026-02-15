import XCTest
@testable import Trai

final class TraiPulseActionRankerTests: XCTestCase {
    func testRankActionsSelectsTopReminderCandidateAndIncludesMetadata() {
        let first = TraiPulseReminderCandidate(id: "a", title: "Hydrate", time: "08:30 AM", hour: 8, minute: 30)
        let second = TraiPulseReminderCandidate(id: "b", title: "Walk", time: "09:15 AM", hour: 9, minute: 15)
        let context = makeContext(
            pendingReminderCandidates: [first, second],
            pendingReminderCandidateScores: ["a": 0.3, "b": 0.9]
        )

        let ranked = TraiPulseActionRanker.rankActions(context: context, now: context.now, limit: 20)
        let reminder = ranked.first { $0.action.kind == .completeReminder }?.action

        XCTAssertEqual(reminder?.title, "Complete Walk")
        XCTAssertEqual(reminder?.metadata?["reminder_id"], "b")
        XCTAssertEqual(reminder?.metadata?["reminder_time"], "09:15 AM")
    }

    func testRankActionsSuggestsMorningWeightLogOnlyInMorningWindow() {
        let morningContext = makeContext(
            now: dateAt(hour: 8),
            daysSinceLastWeightLog: 2,
            weightLikelyLogTimes: ["Morning (4-9 AM)"]
        )
        let afternoonContext = makeContext(
            now: dateAt(hour: 14),
            daysSinceLastWeightLog: 2,
            weightLikelyLogTimes: ["Morning (4-9 AM)"]
        )

        let morningKinds = Set(TraiPulseActionRanker.rankActions(context: morningContext, now: morningContext.now, limit: 20).map(\.action.kind))
        let afternoonKinds = Set(TraiPulseActionRanker.rankActions(context: afternoonContext, now: afternoonContext.now, limit: 20).map(\.action.kind))

        XCTAssertTrue(morningKinds.contains(.logWeight))
        XCTAssertFalse(afternoonKinds.contains(.logWeight))
    }

    func testRankActionsMapsPlanReviewTriggerToExpectedKind() {
        let workoutContext = makeContext(planReviewTrigger: "plan_age")
        let nutritionContext = makeContext(planReviewTrigger: "weight_change")

        let workoutKinds = Set(TraiPulseActionRanker.rankActions(context: workoutContext, now: workoutContext.now, limit: 20).map(\.action.kind))
        let nutritionKinds = Set(TraiPulseActionRanker.rankActions(context: nutritionContext, now: nutritionContext.now, limit: 20).map(\.action.kind))

        XCTAssertTrue(workoutKinds.contains(.reviewWorkoutPlan))
        XCTAssertTrue(nutritionKinds.contains(.reviewNutritionPlan))
    }

    func testRankActionsAppliesRepetitionPenaltyToWorkoutAction() {
        let base = makeContext(hasWorkoutToday: false, hasActiveWorkout: false)
        let penalized = makeContext(
            hasWorkoutToday: false,
            hasActiveWorkout: false,
            todayCompletedActionKeys: [BehaviorActionKey.startWorkout]
        )

        let baseRanked = TraiPulseActionRanker.rankActions(context: base, now: base.now, limit: 20)
        let penalizedRanked = TraiPulseActionRanker.rankActions(context: penalized, now: penalized.now, limit: 20)

        let action = DailyCoachAction(kind: .startWorkout, title: "Start Workout")
        let baseScore = TraiPulseActionRanker.score(for: action, in: baseRanked)
        let penalizedScore = TraiPulseActionRanker.score(for: action, in: penalizedRanked)

        XCTAssertGreaterThan(baseScore, penalizedScore)
    }

    func testRankActionsRespectsLimitIncludingZero() {
        let context = makeContext()

        XCTAssertTrue(TraiPulseActionRanker.rankActions(context: context, now: context.now, limit: 0).isEmpty)
        XCTAssertEqual(TraiPulseActionRanker.rankActions(context: context, now: context.now, limit: 1).count, 1)
    }

    func testRankActionsAddsOpenWorkoutPlanWhenTemplateRecommendationExists() {
        let withRecommendation = makeContext(hasWorkoutToday: false, hasActiveWorkout: false, recommendedWorkoutName: "Leg Day")
        let withoutRecommendation = makeContext(hasWorkoutToday: false, hasActiveWorkout: false, recommendedWorkoutName: nil)

        let withKinds = Set(TraiPulseActionRanker.rankActions(context: withRecommendation, now: withRecommendation.now, limit: 20).map(\.action.kind))
        let withoutKinds = Set(TraiPulseActionRanker.rankActions(context: withoutRecommendation, now: withoutRecommendation.now, limit: 20).map(\.action.kind))

        XCTAssertTrue(withKinds.contains(.openWorkoutPlan))
        XCTAssertFalse(withoutKinds.contains(.openWorkoutPlan))
    }

    private func makeContext(
        now: Date = Date(timeIntervalSince1970: 1_736_208_000),
        hasWorkoutToday: Bool = true,
        hasActiveWorkout: Bool = false,
        recommendedWorkoutName: String? = "Upper Body",
        daysSinceLastWeightLog: Int? = nil,
        weightLikelyLogTimes: [String] = [],
        weightLogRoutineScore: Double = 0.0,
        planReviewTrigger: String? = nil,
        todayOpenedActionKeys: Set<String> = [],
        todayCompletedActionKeys: Set<String> = [],
        pendingReminderCandidates: [TraiPulseReminderCandidate] = [],
        pendingReminderCandidateScores: [String: Double] = [:]
    ) -> DailyCoachContext {
        DailyCoachContext(
            now: now,
            hasWorkoutToday: hasWorkoutToday,
            hasActiveWorkout: hasActiveWorkout,
            caloriesConsumed: 1_100,
            calorieGoal: 2_000,
            proteinConsumed: 75,
            proteinGoal: 150,
            readyMuscleCount: 3,
            recommendedWorkoutName: recommendedWorkoutName,
            activeSignals: [],
            trend: nil,
            patternProfile: .empty,
            daysSinceLastWeightLog: daysSinceLastWeightLog,
            weightLikelyLogTimes: weightLikelyLogTimes,
            weightLogRoutineScore: weightLogRoutineScore,
            planReviewTrigger: planReviewTrigger,
            todayOpenedActionKeys: todayOpenedActionKeys,
            todayCompletedActionKeys: todayCompletedActionKeys,
            pendingReminderCandidates: pendingReminderCandidates,
            pendingReminderCandidateScores: pendingReminderCandidateScores
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
