import XCTest
@testable import Trai

final class WorkoutPlanGenerationRequestTests: XCTestCase {
    func testFallbackSessionDurationUsesDefaultWhenUnspecified() {
        let request = makeRequest(timePerWorkout: nil)

        XCTAssertEqual(request.fallbackSessionDuration, 45)
    }

    func testFallbackSessionDurationClampsToSupportedBounds() {
        XCTAssertEqual(makeRequest(timePerWorkout: 10).fallbackSessionDuration, 20)
        XCTAssertEqual(makeRequest(timePerWorkout: 75).fallbackSessionDuration, 75)
        XCTAssertEqual(makeRequest(timePerWorkout: 180).fallbackSessionDuration, 120)
    }

    func testIncludesCardioHonorsSelectedWorkoutTypes() {
        let request = makeRequest(
            workoutType: .strength,
            selectedWorkoutTypes: [.strength, .cardio]
        )

        XCTAssertTrue(request.includesCardio)
    }

    func testAccessoryCardioDirectiveKeepsCardioInsideStrengthSession() {
        let request = makeRequest(
            workoutType: .mixed,
            selectedWorkoutTypes: [.strength, .cardio],
            preferences: "I want to add some cardio at the end of one strength session every week."
        )

        XCTAssertTrue(request.requestsCardioAsAccessory)
        XCTAssertTrue(request.generationDirectives.contains { $0.contains("supportive finisher") })
        XCTAssertTrue(request.generationDirectives.contains { $0.contains("Dedicated cardio") })
    }

    func testAccessoryCardioDefaultPlanUsesFinisherInsteadOfStandaloneCardioDay() {
        let request = makeRequest(
            workoutType: .mixed,
            selectedWorkoutTypes: [.strength, .cardio],
            preferences: "Strength should lead and I only want a short easy cardio finisher after one lift each week.",
            availableDays: 3
        )

        let plan = WorkoutPlan.createDefault(from: request)

        XCTAssertEqual(plan.templates.count, 3)
        XCTAssertFalse(plan.templates.contains { $0.sessionType == .cardio || $0.name.localizedCaseInsensitiveContains("running endurance") })
        XCTAssertTrue(plan.templates.first?.displayBlocks.contains { $0.kind == .cardioFinisher } == true)
    }

    func testDedicatedCardioSignalOverridesAccessoryCardioDirective() {
        let request = makeRequest(
            workoutType: .mixed,
            selectedWorkoutTypes: [.strength, .cardio],
            preferences: "I want cardio after lifting, but I am training for a 10k race."
        )

        XCTAssertFalse(request.requestsCardioAsAccessory)
        XCTAssertFalse(request.generationDirectives.contains { $0.contains("supportive finisher") })
    }

    func testLegacyWorkoutPlanJSONSynthesizesBlocks() throws {
        let json = """
        {
          "splitType": "upperLower",
          "daysPerWeek": 3,
          "templates": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Upper Strength",
              "targetMuscleGroups": ["chest", "back"],
              "exercises": [
                {
                  "id": "22222222-2222-2222-2222-222222222222",
                  "exerciseName": "Bench Press",
                  "muscleGroup": "chest",
                  "defaultSets": 3,
                  "defaultReps": 8,
                  "order": 0
                }
              ],
              "estimatedDurationMinutes": 45,
              "order": 0
            }
          ],
          "rationale": "Legacy",
          "guidelines": [],
          "progressionStrategy": {
            "type": "doubleProgression",
            "weightIncrementKg": 2.5,
            "repsTrigger": 12,
            "description": "Progress reps, then load."
          }
        }
        """

        let plan = try XCTUnwrap(WorkoutPlan.fromJSON(json))
        let template = try XCTUnwrap(plan.templates.first)

        XCTAssertNil(plan.planIntent)
        XCTAssertNil(plan.modalityProgression)
        XCTAssertEqual(template.sessionType, .strength)
        XCTAssertTrue(template.blocks.isEmpty)
        XCTAssertEqual(template.displayBlocks.count, 1)
        XCTAssertEqual(template.displayBlocks.first?.kind, .strength)
        XCTAssertEqual(template.structuredExercises.map(\.exerciseName), ["Bench Press"])
    }

    func testWorkoutPlanJSONAcceptsAISemanticStringIDs() throws {
        let json = """
        {
          "splitType": "custom",
          "daysPerWeek": 1,
          "planIntent": {
            "primaryFocus": "Bench strength",
            "supportingFocuses": ["Short cardio support"],
            "sessionAllocation": "One strength session with one short cardio finisher",
            "honoredInputs": ["No standalone cardio day"],
            "avoided": ["Standalone cardio day"],
            "summary": "Strength first."
          },
          "templates": [
            {
              "id": "session-1",
              "name": "Strength A + Easy Run Finisher",
              "sessionType": "mixed",
              "focusAreas": ["Bench Press", "Easy Cardio Finisher"],
              "targetMuscleGroups": ["Chest", "Back"],
              "exercises": [
                {
                  "id": "bench-press",
                  "exerciseName": "Bench Press",
                  "muscleGroup": "Chest",
                  "defaultSets": 3,
                  "defaultReps": 6,
                  "repRange": "5-8",
                  "restSeconds": 120,
                  "notes": "Smooth reps.",
                  "order": 1
                }
              ],
              "blocks": [
                {
                  "id": "session-1-strength",
                  "kind": "strength",
                  "title": "Strength",
                  "detail": "Bench work",
                  "exercises": [
                    {
                      "id": "bench-press",
                      "exerciseName": "Bench Press",
                      "muscleGroup": "Chest",
                      "defaultSets": 3,
                      "defaultReps": 6,
                      "order": 1
                    }
                  ],
                  "durationMinutes": 35,
                  "intensity": "moderate",
                  "target": "Pressing strength",
                  "order": 1,
                  "notes": null
                },
                {
                  "id": "session-1-cardio",
                  "kind": "cardioFinisher",
                  "title": "Cardio Finisher",
                  "detail": "Easy incline walk",
                  "exercises": [],
                  "durationMinutes": 5,
                  "intensity": "easy",
                  "target": "Aerobic support",
                  "order": 2,
                  "notes": "Do not turn this into a standalone day."
                }
              ],
              "estimatedDurationMinutes": 45,
              "order": 1,
              "notes": "Strength leads."
            }
          ],
          "rationale": "Cardio is kept as a finisher.",
          "guidelines": ["Keep cardio easy."],
          "progressionStrategy": {
            "type": "doubleProgression",
            "weightIncrementKg": 2.5,
            "repsTrigger": 8,
            "description": "Add reps, then load."
          },
          "modalityProgression": {
            "focus": "mixed",
            "weeklyProgression": "Progress bench while keeping cardio easy.",
            "targets": [
              {
                "id": "bench-strength",
                "label": "Bench Press performance",
                "metric": "reps or load on bench",
                "direction": "up"
              }
            ]
          },
          "warnings": []
        }
        """

        let firstDecode = try XCTUnwrap(WorkoutPlan.fromJSON(json))
        let secondDecode = try XCTUnwrap(WorkoutPlan.fromJSON(json))
        let template = try XCTUnwrap(firstDecode.templates.first)

        XCTAssertEqual(template.sessionType, .mixed)
        XCTAssertEqual(template.displayBlocks.map(\.kind), [.strength, .cardioFinisher])
        XCTAssertEqual(template.structuredExercises.map(\.exerciseName), ["Bench Press"])
        XCTAssertEqual(firstDecode.templates.first?.id, secondDecode.templates.first?.id)
        XCTAssertEqual(firstDecode.templates.first?.blocks.first?.id, secondDecode.templates.first?.blocks.first?.id)
        XCTAssertEqual(firstDecode.modalityProgression?.targets.first?.id, secondDecode.modalityProgression?.targets.first?.id)
    }

    func testWorkoutPlanRefinementSchemaRequiresModalityFields() throws {
        let schema = AIPromptBuilder.workoutPlanRefinementSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let proposedPlan = try XCTUnwrap(properties["proposedPlan"] as? [String: Any])
        let planProperties = try XCTUnwrap(proposedPlan["properties"] as? [String: Any])
        let templates = try XCTUnwrap(planProperties["templates"] as? [String: Any])
        let templateSchema = try XCTUnwrap(templates["items"] as? [String: Any])
        let required = try XCTUnwrap(templateSchema["required"] as? [String])

        XCTAssertTrue(required.contains("sessionType"))
        XCTAssertTrue(required.contains("focusAreas"))
        XCTAssertTrue(required.contains("blocks"))
        XCTAssertTrue(required.contains("notes"))
    }

    func testWorkoutGoalSuggestionsDropDuplicateTitles() {
        let first = makeGoalSuggestion(title: "Add a weekly cardio finisher")
        let duplicate = makeGoalSuggestion(title: "  Add a Weekly Cardio Finisher  ")

        let validated = WorkoutGoalSuggestion.validatedUnique([first, duplicate])

        XCTAssertEqual(validated.map(\.title), ["Add a weekly cardio finisher"])
    }

    func testWorkoutGoalSuggestionsDropUntrackableNumericGoals() {
        let untrackable = makeGoalSuggestion(
            title: "Add a weekly cardio finisher",
            targetValue: nil,
            targetUnit: "finishers"
        )
        let trackable = makeGoalSuggestion(title: "Finish one cardio finisher each week")

        let validated = WorkoutGoalSuggestion.validatedUnique([untrackable, trackable])

        XCTAssertEqual(validated.map(\.title), ["Finish one cardio finisher each week"])
    }

    func testWorkoutGoalSuggestionsDropGoalsWithoutSuccessCriteria() {
        let vague = makeGoalSuggestion(
            title: "Improve climbing",
            goalKindRaw: WorkoutGoal.GoalKind.milestone.rawValue,
            targetValue: nil,
            targetUnit: nil,
            periodUnitRaw: nil,
            periodCount: nil,
            successCriteria: "   "
        )
        let specific = makeGoalSuggestion(
            title: "Send one V5 clean",
            goalKindRaw: WorkoutGoal.GoalKind.milestone.rawValue,
            targetValue: nil,
            targetUnit: nil,
            periodUnitRaw: nil,
            periodCount: nil,
            successCriteria: "Complete one V5 from start to finish without falls."
        )

        let validated = WorkoutGoalSuggestion.validatedUnique([vague, specific])

        XCTAssertEqual(validated.map(\.title), ["Send one V5 clean"])
    }

    func testWorkoutGoalSuggestionPreservesSuccessCriteria() throws {
        let suggestion = makeGoalSuggestion(
            title: "Send the blue V5 clean",
            goalKindRaw: WorkoutGoal.GoalKind.milestone.rawValue,
            targetValue: nil,
            targetUnit: nil,
            periodUnitRaw: nil,
            periodCount: nil,
            successCriteria: "Climb the blue V5 from start to finish without falls."
        )

        let goal = try XCTUnwrap(WorkoutGoalSuggestion.validatedUnique([suggestion]).first?.asWorkoutGoal())

        XCTAssertEqual(goal.trimmedSuccessCriteria, "Climb the blue V5 from start to finish without falls.")
        XCTAssertEqual(goal.trackingSummary, "Climb the blue V5 from start to finish without falls.")
    }

    func testWorkoutTemplateDisplayBlocksSortByDeclaredOrder() {
        let template = WorkoutPlan.WorkoutTemplate(
            name: "Hybrid Day",
            sessionType: .mixed,
            focusAreas: ["Hybrid"],
            targetMuscleGroups: [],
            exercises: [],
            blocks: [
                WorkoutPlan.TrainingBlock(
                    kind: .cardioFinisher,
                    title: "Finisher",
                    detail: "Bike",
                    order: 2
                ),
                WorkoutPlan.TrainingBlock(
                    kind: .warmup,
                    title: "Warmup",
                    detail: "Move",
                    order: 0
                ),
                WorkoutPlan.TrainingBlock(
                    kind: .strength,
                    title: "Strength",
                    detail: "Lift",
                    order: 1
                )
            ],
            estimatedDurationMinutes: 45,
            order: 0
        )

        XCTAssertEqual(template.displayBlocks.map(\.title), ["Warmup", "Strength", "Finisher"])
        XCTAssertEqual(template.displayBlocks.map(\.order), [0, 1, 2])
    }

    private func makeGoalSuggestion(
        title: String,
        goalKindRaw: String = WorkoutGoal.GoalKind.frequency.rawValue,
        targetValue: Double? = 1,
        targetUnit: String? = "finishers",
        periodUnitRaw: String? = WorkoutGoal.PeriodUnit.week.rawValue,
        periodCount: Int? = 1,
        successCriteria: String = "Complete the tracked target."
    ) -> WorkoutGoalSuggestion {
        WorkoutGoalSuggestion(
            title: title,
            rationale: "Fits the plan.",
            goalKindRaw: goalKindRaw,
            linkedWorkoutTypeRaw: WorkoutMode.mixed.rawValue,
            linkedActivityName: "Cardio Finisher",
            targetValue: targetValue,
            targetUnit: targetUnit,
            periodUnitRaw: periodUnitRaw,
            periodCount: periodCount,
            successCriteria: successCriteria,
            notes: nil,
            targetDateISO8601: nil,
            checkInCadenceDays: nil
        )
    }

    private func makeRequest(
        workoutType: WorkoutPlanGenerationRequest.WorkoutType = .mixed,
        selectedWorkoutTypes: [WorkoutPlanGenerationRequest.WorkoutType]? = nil,
        timePerWorkout: Int? = nil,
        preferences: String? = nil,
        conversationContext: [String]? = nil,
        availableDays: Int? = 4
    ) -> WorkoutPlanGenerationRequest {
        WorkoutPlanGenerationRequest(
            name: "Test User",
            age: 30,
            gender: .notSpecified,
            goal: .health,
            activityLevel: .moderate,
            workoutType: workoutType,
            selectedWorkoutTypes: selectedWorkoutTypes,
            experienceLevel: .intermediate,
            equipmentAccess: .fullGym,
            availableDays: availableDays,
            timePerWorkout: timePerWorkout,
            preferredSplit: nil,
            cardioTypes: nil,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: nil,
            weakPoints: nil,
            injuries: nil,
            preferences: preferences,
            conversationContext: conversationContext
        )
    }
}
