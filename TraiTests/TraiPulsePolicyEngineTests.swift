import XCTest
@testable import Trai

final class TraiPulsePolicyEngineTests: XCTestCase {
    private let cooldownKey = "pulse_last_plan_proposal_shown_at"

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: cooldownKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: cooldownKey)
        try super.tearDownWithError()
    }

    func testApplyDropsInvalidCompleteReminderActionWhenMultipleCandidatesAndNoMetadata() {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let context = makeContext(
            hasWorkoutToday: true,
            caloriesConsumed: 0,
            proteinConsumed: 150,
            proteinGoal: 150,
            pendingReminderCandidates: [
                TraiPulseReminderCandidate(id: firstID, title: "Hydrate", time: "08:30 AM", hour: 8, minute: 30),
                TraiPulseReminderCandidate(id: secondID, title: "Walk", time: "09:30 AM", hour: 9, minute: 30)
            ],
            pendingReminderCandidateScores: [
                firstID: 0.0,
                secondID: 0.0
            ]
        )

        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .coachNote,
            title: "Title",
            message: "Message",
            prompt: .action(DailyCoachAction(kind: .completeReminder, title: "Complete reminder"))
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: context.now)

        XCTAssertNil(result.prompt)
    }

    func testApplyKeepsValidCompleteReminderActionWithMatchingReminderID() {
        let reminderID = UUID().uuidString
        let context = makeContext(
            pendingReminderCandidates: [
                TraiPulseReminderCandidate(id: reminderID, title: "Hydrate", time: "08:30 AM", hour: 8, minute: 30)
            ],
            pendingReminderCandidateScores: [reminderID: 0.9]
        )

        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .coachNote,
            title: "Title",
            message: "Message",
            prompt: .action(
                DailyCoachAction(
                    kind: .completeReminder,
                    title: "Complete Hydrate",
                    metadata: ["reminder_id": reminderID]
                )
            )
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: context.now)

        guard case .action(let action)? = result.prompt else {
            return XCTFail("Expected action prompt")
        }

        XCTAssertEqual(action.kind, .completeReminder)
        XCTAssertEqual(action.metadata?["reminder_id"], reminderID)
        XCTAssertEqual(action.metadata?["pulse_policy_version"], "pulse_policy_v2")
    }

    func testApplyConvertsPlanProposalToQuestionWhenEvidenceIsInsufficient() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let context = makeContext(now: now, trend: nil)
        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .planProposal,
            title: "Plan",
            message: "Message",
            prompt: .planProposal(planProposalFixture(id: "p1"))
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: now)

        XCTAssertEqual(result.surfaceType, .quickCheckin)
        guard case .question(let question)? = result.prompt else {
            return XCTFail("Expected question prompt")
        }
        XCTAssertEqual(question.id, "plan_checkin_p1")
    }

    func testApplySuppressesPlanProposalDuringCooldown() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        UserDefaults.standard.set(now.timeIntervalSince1970 - 60, forKey: cooldownKey)

        let trend = TraiPulseTrendSnapshot(
            daysWindow: 7,
            daysWithFoodLogs: 5,
            proteinTargetHitDays: 2,
            calorieTargetHitDays: 3,
            workoutDays: 1,
            lowProteinStreak: 3,
            daysSinceWorkout: 1
        )
        let context = makeContext(now: now, trend: trend)
        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .planProposal,
            title: "Plan",
            message: "Message",
            prompt: .planProposal(planProposalFixture(id: "p2"))
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: now)

        XCTAssertEqual(result.surfaceType, .coachNote)
        XCTAssertNil(result.prompt)
    }

    func testApplyInjectsPostWorkoutQuestionWhenEligible() {
        let now = Date(timeIntervalSince1970: 1_736_208_000)
        let currentHour = Calendar.current.component(.hour, from: now)
        let lastWorkoutHour = (currentHour + 23) % 24
        let context = makeContext(
            now: now,
            hasWorkoutToday: true,
            hasActiveWorkout: false,
            lastActiveWorkoutHour: lastWorkoutHour
        )

        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .coachNote,
            title: "Title",
            message: "Message",
            prompt: nil
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: now)

        XCTAssertEqual(result.surfaceType, .quickCheckin)
        guard case .question(let question)? = result.prompt else {
            return XCTFail("Expected question prompt")
        }
        XCTAssertEqual(question.id, "readiness-post-workout")
    }

    func testApplyReplacesWorkoutActionWithMorningWeightActionWhenRoutineMatches() {
        let now = dateAt(hour: 8, minute: 0)
        let context = makeContext(
            now: now,
            daysSinceLastWeightLog: 2,
            weightLikelyLogTimes: ["Morning (4-9 AM)"],
            weightLogRoutineScore: 0.6
        )

        let snapshot = TraiPulseContentSnapshot(
            source: .modelManaged,
            surfaceType: .coachNote,
            title: "Title",
            message: "Message",
            prompt: .action(DailyCoachAction(kind: .startWorkout, title: "Start Workout"))
        )

        let result = TraiPulsePolicyEngine.apply(snapshot, request: makeRequest(context: context), now: now)

        XCTAssertEqual(result.surfaceType, .timingNudge)
        guard case .action(let action)? = result.prompt else {
            return XCTFail("Expected action prompt")
        }
        XCTAssertEqual(action.kind, .logWeight)
    }

    private func makeRequest(
        context: DailyCoachContext,
        blockedQuestionID: String? = nil
    ) -> GeminiService.PulseContentRequest {
        GeminiService.PulseContentRequest(
            context: context,
            preferences: DailyCoachPreferences(
                effortMode: .balanced,
                workoutWindow: .morning,
                tomorrowFocus: .both,
                tomorrowWorkoutMinutes: 40
            ),
            tone: .balanced,
            allowQuestion: true,
            blockedQuestionID: blockedQuestionID
        )
    }

    private func makeContext(
        now: Date = Date(timeIntervalSince1970: 1_736_208_000),
        hasWorkoutToday: Bool = false,
        hasActiveWorkout: Bool = false,
        trend: TraiPulseTrendSnapshot? = nil,
        caloriesConsumed: Int = 1_200,
        proteinConsumed: Int = 80,
        proteinGoal: Int = 150,
        daysSinceLastWeightLog: Int? = nil,
        weightLikelyLogTimes: [String] = [],
        weightLogRoutineScore: Double = 0,
        lastActiveWorkoutHour: Int? = nil,
        pendingReminderCandidates: [TraiPulseReminderCandidate] = [],
        pendingReminderCandidateScores: [String: Double] = [:]
    ) -> DailyCoachContext {
        DailyCoachContext(
            now: now,
            hasWorkoutToday: hasWorkoutToday,
            hasActiveWorkout: hasActiveWorkout,
            caloriesConsumed: caloriesConsumed,
            calorieGoal: 2_000,
            proteinConsumed: proteinConsumed,
            proteinGoal: proteinGoal,
            readyMuscleCount: 3,
            recommendedWorkoutName: "Upper Body",
            activeSignals: [],
            trend: trend,
            patternProfile: .empty,
            daysSinceLastWeightLog: daysSinceLastWeightLog,
            weightLikelyLogTimes: weightLikelyLogTimes,
            weightLogRoutineScore: weightLogRoutineScore,
            lastActiveWorkoutHour: lastActiveWorkoutHour,
            pendingReminderCandidates: pendingReminderCandidates,
            pendingReminderCandidateScores: pendingReminderCandidateScores
        )
    }

    private func planProposalFixture(id: String) -> TraiPulsePlanProposal {
        TraiPulsePlanProposal(
            id: id,
            title: "Adjust Plan",
            rationale: "Rationale",
            impact: "Impact",
            changes: ["Change 1"],
            applyLabel: "Apply",
            reviewLabel: "Review",
            deferLabel: "Later"
        )
    }

    private func dateAt(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: 1_736_208_000))
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_736_208_000)
    }
}
