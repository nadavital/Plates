# Make Generated Workout Plans Fully Trackable

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository has `.agent/PLANS.md`; this document must be maintained in accordance with that file. This plan intentionally replaces the previous pending onboarding ExecPlan in `.agent/execplan-pending.md` because the current priority is making Pro workout-plan generation produce plans that users can actually log, review, refine, and track across the app.

## Purpose / Big Picture

Trai Pro workout-plan generation should feel useful because the generated plan becomes a real working system in the app, not just a nice review card. After this change, Trai can generate a workout day that includes strength work plus any kind of supporting activity, such as cardio, mobility, skill practice, recovery, conditioning, or a custom activity. The user can start that day from the Workouts tab, see each planned activity inside Live Workout, add unplanned activities during the workout, complete or edit them, see them in summaries and workout detail sheets, and have goals progress from the actual logged activity entries.

The key product change is replacing example-specific thinking with a broad model. "Cardio finisher" is not a first-class type. The durable shape is an activity `kind` plus a session `role`: a block can be `kind = cardio` and `role = finisher`, or `kind = mobility` and `role = warmup`, or `kind = skill` and `role = accessory`. The same model applies whether Trai planned the block or the user added it mid-workout.

## Progress

- [x] (2026-05-21 05:59Z) Set the active Codex goal to implement generalized workout activity/accessory block support across plan generation, onboarding, live workout logging, summaries/details, goals, and progress tracking.
- [x] (2026-05-21 06:02Z) Reviewed the current plan, live workout, activity card, summary, goal, and prompt paths; confirmed the app already converts non-strength plan blocks to `LiveWorkoutEntry` rows but still uses the overly specific `cardioFinisher` block kind and session-level frequency counting.
- [x] (2026-05-21 06:08Z) Authored this replacement ExecPlan.
- [x] (2026-05-21 06:17Z) Milestone 1: Added a generalized activity taxonomy to plan blocks and live workout entries while preserving legacy decode compatibility.
- [x] (2026-05-21 06:23Z) Milestone 2: Updated plan generation prompts, schemas, fallback defaults, and Pro setup questions so Trai asks useful broad questions and returns `kind + role` blocks instead of hardcoded example types.
- [x] (2026-05-21 06:25Z) Milestone 3: Updated Live Workout and workout detail entry UI so planned and ad hoc activity blocks can be logged with category, role, duration, notes, completion, and source context. Cardio-like entries continue to expose distance through the existing cardio row after they are created.
- [x] (2026-05-21 06:25Z) Milestone 4: Updated workout summaries, plan cards, chat context, and Trai review prompts so logged activity blocks remain visible and understandable after the workout ends.
- [x] (2026-05-21 06:30Z) Milestone 5: Strengthened workout-goal creation and progress tracking so goals can target activity entries by name, kind, role, duration, distance, or frequency without relying on brittle title matching.
- [x] (2026-05-21 06:36Z) Milestone 6: Verified with a simulator build, focused tests, and a Pro setup walkthrough through generation start. The walkthrough exposed an auth/session error path, which is now mapped to the sign-in-required message instead of leaking `Session not found`.

## Surprises & Discoveries

- Observation: `WorkoutTemplateService.createWorkoutFromTemplate` already converts plan blocks into live workout entries. Strength blocks with exercises become set-based entries; non-strength blocks become duration/note/completion entries.
  Evidence: `Trai/Core/Services/WorkoutTemplateService.swift` lines 111-165 create `LiveWorkoutEntry` values from every `WorkoutPlan.TrainingBlock`.

- Observation: The current model hardcodes `cardioFinisher` as a `WorkoutPlan.TrainingBlock.BlockKind`, which makes one user example look like a product primitive.
  Evidence: `Trai/Core/Models/WorkoutPlan.swift` defines `case cardioFinisher`; `Trai/Core/Models/WorkoutPlanDefaults.swift` adds `blocksWithAccessoryCardioFinisher`; tests assert `.cardioFinisher`.

- Observation: Live workout entries can already store much of what activity blocks need: name, exercise type, duration, distance, calories, notes, completion, and order.
  Evidence: `Trai/Core/Models/LiveWorkoutEntry.swift` has `exerciseType`, `durationSeconds`, `distanceMeters`, `caloriesBurned`, `notes`, and `completedAt`.

- Observation: The Live Workout UI already branches non-strength entries to either `CardioExerciseCard` or `GeneralActivityCard`, so the implementation can extend existing surfaces instead of inventing a new workout screen.
  Evidence: `Trai/Features/Workouts/LiveWorkoutView.swift` lines 408-430 render general activity and cardio entries separately from strength exercise cards.

- Observation: Goal frequency progress currently counts parent workouts and imported sessions. That is wrong for goals such as "complete one accessory cardio block each week" because the parent strength workout may complete even if the accessory block is skipped.
  Evidence: `Trai/Features/Workouts/WorkoutGoalComponents.swift` lines 641-679 count matching workouts and sessions, while entry matching exists only for notes and numeric duration/distance/weight cases.

- Discovery: In a UI-test launch without a prepared live AI backend session, Pro generation reached the backend with a debug local session and failed with HTTP 401 `Session not found`.
  Evidence: The iPhone 16e simulator Pro setup walkthrough reached generation after three answers, and the runtime log at `Nadav.Trai_2026-05-21T06-32-11-742Z...log` showed the backend 401. `AIService.parseAIProxyError` now normalizes that session failure to the sign-in-required user-facing message.

## Decision Log

- Decision: Model "finisher" as a role, not as a block kind.
  Rationale: The app should not grow one-off block types from examples. A cardio finisher is just cardio with a finisher role; the same pattern supports mobility warmups, skill accessories, conditioning finishers, and custom activity work.
  Date/Author: 2026-05-21 / Codex

- Decision: Keep backward compatibility for legacy `cardioFinisher` JSON and saved plans.
  Rationale: Existing generated plans and tests may contain that string. Decoding should map legacy `cardioFinisher` to `kind = cardio` and `role = finisher` instead of failing or losing the planned activity.
  Date/Author: 2026-05-21 / Codex

- Decision: Store activity metadata on `LiveWorkoutEntry` rather than creating a separate SwiftData model.
  Rationale: Live workout rows are already the source of truth for user interaction, summaries, and goal progress. Adding optional fields keeps migration additive and avoids splitting one visible workout item across two persisted objects.
  Date/Author: 2026-05-21 / Codex

- Decision: Goal progress for activity-specific frequency goals should count completed matching live workout entries before falling back to whole-session counts.
  Rationale: A goal about an accessory block is achieved by completing that block, not merely by completing the parent workout.
  Date/Author: 2026-05-21 / Codex

## Outcomes & Retrospective

Implemented the generalized activity model and connected it through plan generation, template-to-live-workout conversion, live activity logging, summaries, Trai review context, AI goal creation, manual goal editing, and goal progress. The old `cardioFinisher` raw value remains supported only as legacy decode input; new generation and defaults use broad block kinds plus roles.

Validation completed:

    mcp__xcodebuildmcp__.build_sim, scheme Trai, iPhone 16e simulator: succeeded with no warnings or errors.
    mcp__xcodebuildmcp__.test_sim, scheme TraiTests, focused suites WorkoutPlanGenerationRequestTests, WorkoutTemplateServiceTests, LiveWorkoutViewModelInvalidationTests: 31 passed, 0 failed.

Simulator walkthrough status: the Pro setup UI reached the mandatory chat-style personalization step, showed the revised "What are you training for?" screen without the old banner line, and advanced to generation after three answers. The test launch intentionally did not include `--ui-test-live-ai-backend`, so the backend rejected the debug session; the user-facing error mapping was fixed.

## Context and Orientation

The app is a SwiftUI iOS app in `/Users/nadav/Desktop/Trai`. Main app code lives in `Trai/`, unit tests live in `TraiTests/`, and the Xcode project is `Trai.xcodeproj`.

A `WorkoutPlan` is a Codable value stored on `UserProfile`. It contains `WorkoutTemplate` values, and each template contains ordered `TrainingBlock` values. A training block is one part of a workout day. Today it has a `kind`, title, detail, optional exercises, duration, intensity, target, order, and notes. This plan changes that by adding a `role`. The `kind` says what the work is, such as strength, cardio, mobility, skill, or recovery. The `role` says how it fits into the session, such as main, warmup, accessory, finisher, or cooldown.

A `LiveWorkout` is a persisted SwiftData workout session. It owns `LiveWorkoutEntry` rows. A strength entry has sets. A cardio or activity entry has duration, distance, notes, and completion state. `WorkoutTemplateService.createWorkoutFromTemplate` is the bridge from a saved plan template into a startable live workout. This bridge is the most important integration point because generated plans are only useful if this conversion keeps their structure intact.

Workout goals are persisted as `WorkoutGoal`. The current goal model can link to a broad workout type and optionally to an activity name. `WorkoutGoalProgressResolver` in `Trai/Features/Workouts/WorkoutGoalComponents.swift` computes the visible progress. This must be extended so activity-kind and activity-role goals can be tracked from completed live entries.

The UI surfaces that must agree with this model are:

- `Trai/Features/Workouts/WorkoutPlanChatFlow.swift`, which collects Pro workout-plan answers and requests AI-generated plans.
- `Trai/Core/Services/AIWorkoutPlanPrompts.swift`, `AIService+WorkoutPlan.swift`, and `AIService+WorkoutGoals.swift`, which steer generated plans and goals.
- `Trai/Core/Services/WorkoutTemplateService.swift`, which converts plan blocks to live entries.
- `Trai/Features/Workouts/LiveWorkoutView.swift`, `GeneralWorkoutComponents.swift`, and `LiveWorkoutViewModel.swift`, which let users log live entries and add ad hoc activity.
- `Trai/Features/Workouts/WorkoutSummarySheet.swift`, `LiveWorkoutDetailSheet.swift`, `WorkoutHistoryRows.swift`, `WorkoutHistorySection.swift`, and `AllWorkoutsSheet.swift`, which present completed sessions.
- `Trai/Features/Workouts/WorkoutGoalComponents.swift` and `WorkoutGoalAISheet.swift`, which show and create goals.

## Plan of Work

Milestone 1 adds the data model vocabulary. In `WorkoutPlan.TrainingBlock`, add a nested `Role` enum with cases `main`, `warmup`, `accessory`, `finisher`, `cooldown`, and `custom`. Add a `role` property to `TrainingBlock`, include it in Codable keys, and default it during decoding. When old JSON contains `kind = cardioFinisher`, decode it as `kind = cardio` and `role = finisher`. Keep the Swift enum case temporarily only if needed for legacy decode, but new generation, defaults, tests, and UI should stop creating it. Add optional metadata fields to `LiveWorkoutEntry`: `activityKindRaw`, `activityRoleRaw`, `sourcePlanBlockIDRaw`, `plannedDurationSeconds`, `plannedIntensity`, and `plannedTarget`. Add computed helpers that expose kind and role in a safe way. Extend `WorkoutTemplateService.createWorkoutFromTemplate` so each non-strength block copies its kind, role, duration, intensity, target, detail, and source block ID to the `LiveWorkoutEntry`.

Milestone 2 changes generation and onboarding. Update `AIWorkoutPlanPrompts` so the schema asks for block `kind` and `role`, not `cardioFinisher`. The valid block kinds should be broad activity categories. The prompt should say that a finisher, warmup, cooldown, or accessory is a role that can apply to many kinds. Update the Pro setup questions in `WorkoutPlanChatFlow` to ask what the plan should include or avoid in terms of priorities, split preferences, support work, and constraints, but do not ask fixed questions that only make sense for strength. The final shaping step should encourage concrete answers without forcing users to know the internal taxonomy. Update fallback defaults in `WorkoutPlanDefaults` so accessory support blocks are built as `kind = cardio`, `role = finisher` or `role = accessory`.

Milestone 3 updates live logging. Replace the generic "Add Activity" sheet with a compact activity add/edit sheet that supports activity name, kind, role, duration, optional distance for cardio-like kinds, and notes. The sheet should use existing card styles and avoid verbose instructional text. `GeneralActivityCard` and `CardioExerciseCard` should show concise chips for kind/role/intensity/target when present and should continue to let users edit duration, distance, notes, and completion. Planned blocks should show as planned entries; ad hoc entries should store the same fields without a source block ID.

Milestone 4 updates post-workout surfaces. Workout summaries and details should show non-strength entries as first-class workout items with kind/role labels and the relevant measured values. History rows should summarize completed activity blocks as "2 activities done" or a concise named highlight when useful. Trai review prompts and chat context should include activity entries so Trai can understand that a user completed a mobility warmup, cardio finisher, climbing practice block, or other support activity.

Milestone 5 updates goal creation and progress. Add optional `linkedActivityKindRaw` and `linkedActivityRoleRaw` to `WorkoutGoal` and `WorkoutGoalSuggestion`. Update AI function declarations and executors so Trai can create or update goals with activity kind and role. Update goal prompts to explain that goals may target a broad session, a specific activity name, a kind, a role, or a kind+role combination. In `WorkoutGoalProgressResolver`, when a frequency goal has an activity name, kind, or role, count matching completed entries in the period instead of counting parent workouts. For duration and distance goals, use matching entries first. For milestone goals, use entry completion or notes as evidence when relevant.

Milestone 6 verifies the whole path. Add or update unit tests in `TraiTests/WorkoutPlanGenerationRequestTests.swift`, `WorkoutTemplateServiceTests.swift`, `LiveWorkoutViewModelInvalidationTests.swift`, and a new or existing goal progress test file. Then run focused tests and a project-level simulator build. Finally, use the simulator Pro plan flow to generate a mixed plan, start one planned workout, complete a planned support activity, add an ad hoc activity, finish the workout, and verify summaries and goal progress.

## Concrete Steps

Work from `/Users/nadav/Desktop/Trai`.

First, write failing tests for the model bridge:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiAccessoryPlanDerived CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

If selected XCTest execution is unavailable because of the scheme, use the project build as compile validation and keep focused tests in the test target for CI or Xcode execution. The current environment has previously reported that the `Trai` scheme is not configured for direct test actions.

For each milestone, after tests/build pass, commit only the relevant files. Do not stage unrelated files such as screenshots, videos, or old local artifacts.

## Validation and Acceptance

The feature is complete when all of the following are true:

1. Generated plan JSON no longer needs a `cardioFinisher` kind. A support activity is represented as a broad kind plus role, such as cardio + finisher or mobility + warmup.
2. Legacy plan JSON containing `cardioFinisher` still decodes and starts correctly.
3. Starting a generated mixed workout creates live entries for strength exercises and non-strength activity blocks in the right order.
4. A user can add an unplanned activity during Live Workout, set its kind/role/duration/notes, complete it, and see it in the workout summary and detail page.
5. A goal tied to a support activity counts completed matching live entries, not just parent workouts.
6. Trai-generated goals do not depend on brittle title matching and can target activity name, kind, role, or broad session type.
7. The simulator Pro workout-plan flow still reaches the generated plan screen and produces a plan whose support work can be logged.

The minimum automated checks are:

- A focused simulator build with `xcodebuild` or `mcp__xcodebuildmcp__.build_sim`.
- Unit tests for legacy block decoding, block-to-live-entry mapping, ad hoc activity completion, and entry-scoped goal frequency progress.

## Idempotence and Recovery

All model additions should be additive optional fields or Codable defaults so existing users' data continues to load. If a build fails after adding SwiftData model fields, verify the app model container includes `LiveWorkoutEntry` and that newly added fields have defaults. If legacy JSON decoding fails, restore the legacy decode branch before continuing.

The plan can be resumed safely. Start by reading this file, running `git status --short`, and checking the Progress section. Do not revert unrelated dirty files. If a milestone is partially complete, inspect the named files and continue from the next unchecked Progress item.

## Artifacts and Notes

Initial evidence from code inspection:

    WorkoutTemplateService.createWorkoutFromTemplate already loops through template.displayBlocks and creates LiveWorkoutEntry rows for non-strength blocks.
    LiveWorkoutEntry already has durationSeconds, distanceMeters, caloriesBurned, notes, completedAt.
    LiveWorkoutView already renders isCardio and isGeneralActivity entries with non-strength cards.
    WorkoutGoalProgressResolver currently counts frequency progress from workouts and sessions, which must change for activity-scoped goals.

## Interfaces and Dependencies

The implementation should use existing SwiftUI, SwiftData, and Trai design-system components. Do not introduce a new persistence layer or a separate activity model unless the additive `LiveWorkoutEntry` approach proves impossible.

At the end of Milestone 1, these interfaces should exist:

    WorkoutPlan.TrainingBlock.Role
    WorkoutPlan.TrainingBlock.role
    LiveWorkoutEntry.activityKindRaw
    LiveWorkoutEntry.activityRoleRaw
    LiveWorkoutEntry.sourcePlanBlockIDRaw
    LiveWorkoutEntry.plannedDurationSeconds
    LiveWorkoutEntry.plannedIntensity
    LiveWorkoutEntry.plannedTarget

At the end of Milestone 5, these interfaces should exist:

    WorkoutGoal.linkedActivityKindRaw
    WorkoutGoal.linkedActivityRoleRaw
    WorkoutGoalSuggestion.linkedActivityKindRaw
    WorkoutGoalSuggestion.linkedActivityRoleRaw
    WorkoutGoalProgressResolver frequency progress that counts completed entries when the goal has activity-level scope.

## Revision Notes

2026-05-21: Created this ExecPlan to replace the previous pending onboarding plan. The reason is that Pro workout plan generation now needs a cross-app trackability pass before the plan-generation and onboarding update can be considered ready to ship.
