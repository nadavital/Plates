# ExecPlan: Consolidate Live Workout Creation into One Canonical Service Surface

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository has `.agent/PLANS.md`; this plan must be maintained in accordance with that file.

## Purpose / Big Picture

Starting a workout currently follows different creation paths depending on where the user starts (widget/app intent deep link, Dashboard CTA, Workouts tab, or Chat suggestion acceptance). After this refactor, all those entry points will use one canonical app service for `LiveWorkout` construction and persistence, so behavior stays consistent and future changes to workout start semantics happen in one place.

User-visible outcome: when a user starts a workout from any entry surface, the same creation rules apply (name/type/muscle mapping, save semantics, and fallback behavior), and regressions from one-off path edits are much less likely.

## Progress

- [x] (2026-02-12 22:51Z) Completed repository analysis, traced core workout-entry flows, and ranked consolidation candidates.
- [ ] Define the canonical workout-creation interface in `/Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift`.
- [ ] Migrate app-intent/deep-link, Dashboard, and Workouts tab workout-start paths to the canonical service.
- [ ] Migrate Chat workout suggestion/log acceptance paths to the same creation service.
- [ ] Remove duplicate constructor logic and validate compile safety + behavior parity.

## Surprises & Discoveries

- Observation: The repository already has a dedicated creation service (`WorkoutTemplateService`), but its primary creation API is not called by any feature flow.
  Evidence: `createWorkoutFromTemplate` is defined in `/Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift:28`, and `rg -n "createWorkoutFromTemplate\(" /Users/nadav/Desktop/Trai/Trai -g"*.swift"` shows no call sites outside that file.

- Observation: `WorkoutsView` stores `@State private var templateService = WorkoutTemplateService()` but does not use it, while hand-rolling workout creation in local functions.
  Evidence: declaration at `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:38`; duplicate constructors at `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:212` and `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:230`.

- Observation: The same concept (create + insert + save `LiveWorkout`) is repeated across multiple feature files.
  Evidence: `/Users/nadav/Desktop/Trai/Trai/ContentView.swift:234`, `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:547`, `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:212`, `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:185`, `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:248`.

## Decision Log

- Decision: Choose "consolidate live workout creation/start paths" as the single refactor to execute.
  Rationale: This is the highest payoff consolidation with acceptable risk: it removes one repeated concept across at least four core flows and directly reduces shotgun surgery for future workout-start changes.
  Date/Author: 2026-02-12 / Codex

- Decision: Reuse `WorkoutTemplateService` as the canonical surface instead of introducing a brand-new service type.
  Rationale: Reusing an existing domain service reduces conceptual surface area and avoids another abstraction layer while still centralizing behavior.
  Date/Author: 2026-02-12 / Codex

- Decision: Preserve current user-visible behavior first (template vs custom fallback semantics, chat suggestion conversion) and explicitly avoid changing workout recommendation logic in this refactor.
  Rationale: This keeps blast radius controlled and makes rollback straightforward.
  Date/Author: 2026-02-12 / Codex

## Outcomes & Retrospective

This plan has not been implemented yet. Expected outcome after implementation is one canonical workout creation path with no duplicated `LiveWorkout` construction logic in app entry features.

## Context and Orientation

`LiveWorkout` is the in-progress workout model stored in SwiftData and used by live workout UI, history merging, and chat/workout actions. The app has multiple independent paths that create `LiveWorkout` instances:

1. App-intent/deep-link path: `StartWorkoutIntent` writes an `AppRoute` pending route, `MainTabView` consumes it, and `startWorkoutFromIntent` creates/saves a workout.
   - `/Users/nadav/Desktop/Trai/Trai/Core/Intents/StartWorkoutIntent.swift:27`
   - `/Users/nadav/Desktop/Trai/Shared/Contracts/AppRoute.swift:77`
   - `/Users/nadav/Desktop/Trai/Trai/ContentView.swift:234`

2. Dashboard CTA path: `DashboardView` creates custom/recommended workout directly.
   - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:547`
   - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:561`

3. Workouts tab path: `WorkoutsView` creates template/custom workout directly.
   - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:212`
   - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:230`

4. Chat path: accepting suggested workout or suggested workout log creates/saves workout directly.
   - `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:185`
   - `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:248`

Dependency highlights from repository reference scan (count of symbol mentions) show this domain is central: `LiveWorkout` (199), `UserProfile` (133), `WorkoutPlan` (97), `ChatMessage` (94), `LiveWorkoutEntry` (80).

Primary smell profile for this refactor:
- Duplicate abstraction: one concept (workout creation) exists as unrelated local implementations.
- Shotgun surgery: changing start behavior requires edits in 5+ files.
- Dead/unused ownership: a creation-focused service exists but is bypassed.

## Plan of Work

### Milestone 1: Define one canonical `LiveWorkout` creation API in `WorkoutTemplateService`

Expand `/Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift` so it is the single app-level source for creating `LiveWorkout` objects for these cases: custom start, template start (name + muscles), app-intent name lookup fallback, chat suggested workout, and chat suggested workout log. Keep existing progression-oriented helper logic intact; this refactor is about centralizing construction and persistence semantics, not deleting progression capability.

At the end of this milestone, feature code should be able to ask the service for fully built `LiveWorkout` values instead of manually assembling entries and fields.

### Milestone 2: Rewire app-intent/deep-link and workout-tab/dashboard starts to the canonical API

Replace local creation code in `/Users/nadav/Desktop/Trai/Trai/ContentView.swift`, `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift`, and `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift` with calls into `WorkoutTemplateService`. Preserve current behavior for fallback naming, template matching, tab switching, and sheet presentation.

This milestone removes duplicated constructor + save logic from the highest-frequency user entry points while preserving visible UX.

### Milestone 3: Rewire Chat suggestion acceptance to the same canonical API

Replace manual construction in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift` for both `acceptWorkoutSuggestion` and `acceptWorkoutLogSuggestion` with service calls. Preserve current conversion rules (string-to-enum mapping, set conversion, completed-at behavior for workout logs, and message state updates).

This ensures chat-created workouts obey the same central construction rules as dashboard/workouts/intent paths.

### Milestone 4: Remove duplicate paths and tighten guardrails

Delete or simplify now-redundant local helper logic and remove unused local service state (for example, any `WorkoutTemplateService` properties that become unnecessary after rewiring). Keep preview-only constructors in `#Preview` blocks unchanged unless they break compile checks.

Add grep-based guardrails to prove duplication removal.

### Milestone 5: Compile and behavior verification

Run focused project build validation for the `Trai` scheme and execute manual behavior checks for each start surface (intent/deep link, dashboard, workouts tab, chat suggestion/log acceptance). Record outputs and any environment blockers in this plan.

## Concrete Steps

All commands below run from `/Users/nadav/Desktop/Trai`.

1. Baseline duplicate detection before edits:

    rg -n "func startWorkoutFromIntent|func startCustomWorkout|func startWorkoutFromTemplate|acceptWorkoutSuggestion|acceptWorkoutLogSuggestion" Trai -g"*.swift"

2. Implement canonical API in service and migrate call sites listed in milestones.

3. Post-edit duplication guardrails:

    rg -n "let (workout|liveWorkout) = LiveWorkout\(" Trai/ContentView.swift Trai/Features/Dashboard/DashboardView.swift Trai/Features/Workouts/WorkoutsView.swift Trai/Features/Chat/ChatViewActions.swift -g"*.swift"

   Expected result: no production constructor call sites remain in those files except preview/test-only blocks.

4. Focused compile check:

    xcodebuild -project /Users/nadav/Desktop/Trai/Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiDerived CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

   Expected result: build succeeds, or failures are unrelated pre-existing environment/plugin issues and are documented.

## Validation and Acceptance

Acceptance is behavioral and compile-focused.

1. App-intent/deep-link path still works:
   - Trigger `StartWorkoutIntent` with and without workout name.
   - App opens to workouts flow and starts the expected workout with existing fallback behavior.

2. Dashboard start path still works:
   - "Start Workout" from Dashboard still creates and presents a workout.
   - Recommended workout still maps template muscle groups correctly.

3. Workouts tab path still works:
   - Starting from template and custom setup both open a workout sheet with expected metadata.

4. Chat acceptance path still works:
   - Accepting `SuggestedWorkoutEntry` starts a workout and marks message state (`workoutStarted`, `startedWorkoutId`).
   - Accepting `SuggestedWorkoutLog` creates a completed workout with entries and duration/notes behavior unchanged.

5. Compile safety:
   - `xcodebuild` command above completes without new compile errors in modified files.

Test-first note: this repository does not currently contain an automated Swift test target. For this plan, verification relies on focused compile checks plus deterministic runtime checks listed above. If a test target is introduced later, add unit tests around the canonical service mappings before rewiring call sites.

## Idempotence and Recovery

The refactor is idempotent because each migrated call site can repeatedly call pure creation helpers and one persistence helper without changing data schema. No migrations are required.

If a milestone regresses behavior, recovery is straightforward:
- Revert the affected call site to its prior local creation logic.
- Keep the canonical service additive until all call sites are verified.
- Re-run compile and behavior checks before removing old code.

## Artifacts and Notes

Evidence gathered during planning:

    rg -n "createWorkoutFromTemplate\(" /Users/nadav/Desktop/Trai/Trai -g"*.swift"
    -> only /Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift:28

    rg -n "func startWorkoutFromIntent|func startCustomWorkout|func startWorkoutFromTemplate|acceptWorkoutSuggestion|acceptWorkoutLogSuggestion" /Users/nadav/Desktop/Trai/Trai -g"*.swift"
    -> /Users/nadav/Desktop/Trai/Trai/ContentView.swift:234
    -> /Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:547
    -> /Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:561
    -> /Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:212
    -> /Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:230
    -> /Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:185
    -> /Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:248

## Interfaces and Dependencies

Canonical API surface to exist in `/Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift` after milestone 1:

- A creation function for custom starts that returns `LiveWorkout` with name/type/muscles.
- A creation function for template starts that maps `WorkoutPlan.WorkoutTemplate.targetMuscleGroups` into `[LiveWorkout.MuscleGroup]` and returns `LiveWorkout`.
- A creation function for app-intent name routing that resolves template-vs-custom fallback consistently.
- A creation function for `SuggestedWorkoutEntry` to `LiveWorkout` mapping.
- A creation function for `SuggestedWorkoutLog` to completed `LiveWorkout` mapping.
- A persistence helper that inserts/saves a created workout in `ModelContext` and either throws or returns a clearly handled failure state.

Dependencies this plan relies on:
- SwiftData `ModelContext` persistence (`insert`, `save`).
- Existing model types in `/Users/nadav/Desktop/Trai/Trai/Core/Models/LiveWorkout.swift`, `/Users/nadav/Desktop/Trai/Trai/Core/Models/LiveWorkoutEntry.swift`, `/Users/nadav/Desktop/Trai/Trai/Core/Models/WorkoutPlan.swift`.
- Existing chat suggestion models in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiTypes.swift`.

## Revision Note

- 2026-02-12 / Codex: Replaced prior pending plan with a consolidation-focused ExecPlan targeting duplicated `LiveWorkout` creation paths. Reason: user explicitly requested the `refactor-something` workflow and a single highest-value consolidation recommendation.
