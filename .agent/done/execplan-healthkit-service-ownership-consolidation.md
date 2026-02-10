# ExecPlan: Consolidate HealthKit Ownership into One App-Scoped Service Surface

## Problem Statement
HealthKit behavior in the app currently uses multiple ownership patterns for the same concept, which increases drift risk and forces repeated edits for each HealthKit feature change.

Current state (evidence):
- App-level shared service exists:
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift:19`
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift:71`
- Multiple feature views create their own service instances instead of using app environment:
  - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift:29`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:38`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatView.swift:44`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Weight/WeightTrackingView.swift:20`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/LogWeightSheet.swift:25`
- Workout merge logic is duplicated across two call paths:
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:315`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel+HealthKit.swift:47`
- Authorization orchestration is repeated across files:
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift:273`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Weight/WeightTrackingView.swift:115`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift:71`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/LogWeightSheet.swift:188`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift:393`

Why this is a problem:
- Duplicate abstraction: app-scoped HealthKit state and per-view local HealthKit state both exist.
- Bug surface area: anchored-query state and auth flags can diverge between instances.
- Cognitive load: engineers must decide per screen whether to use environment service or instantiate a new one.
- Shotgun surgery: changes to HealthKit policy/error handling require edits in many feature files.

Acceptance criteria:
1. App UI/runtime uses one canonical `HealthKitService` instance from app environment (no per-view `@State` allocations).
2. Workout overlap matching logic has one canonical implementation reused by both live-workout merge and workouts history merge.
3. HealthKit authorization + error handling policy is centralized for app UI call sites (no repeated ad-hoc `requestAuthorization` orchestration in features).
4. Existing user behavior is preserved: dashboard activity card, workout sync, chat meal HealthKit save, weight sync/save, and live workout watch streaming.
5. `Trai` app target compiles after refactor.

## Repository Mental Model (Evidence-Based)
- App shell and service injection:
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift`
  - `/Users/nadav/Desktop/Trai/Trai/ContentView.swift`
- HealthKit domain service:
  - `/Users/nadav/Desktop/Trai/Trai/Core/Services/HealthKitService.swift`
- Primary HealthKit-consuming features:
  - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Weight/WeightTrackingView.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatView.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/LogWeightSheet.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel+HealthKit.swift`

Core flow traces:
1. Workout tab HealthKit import/merge:
   `WorkoutsView.syncHealthKit` -> `HealthKitService.fetchWorkouts` -> local dedupe -> local overlap matcher.
2. Live workout merge at completion:
   `LiveWorkoutViewModel+HealthKit.mergeWithAppleWatchWorkout` -> new `HealthKitService()` -> local overlap matcher.
3. Food/weight writes:
   chat meal acceptance and weight logging call `requestAuthorization`/save methods in feature-level code paths.

Dependency highlights (repo reference count scan):
- `LiveWorkout` (198), `UserProfile` (139), `Exercise` (136), `FoodEntry` (100), `WorkoutPlan` (97), `ChatMessage` (94), `GeminiService` (49), `HealthKitService` (14).

Identified smells:
- Duplicate abstractions: one shared service plus several local feature-owned services.
- Shotgun surgery: authorization/error/sync changes cut across 5+ files.
- Leaky abstractions: feature views implement HealthKit policy decisions that should live in service-level APIs.

## Assumptions
- Production-level caution applies; behavior must remain functionally equivalent.
- App Intents may still construct their own `HealthKitService` because they execute outside SwiftUI environment lifecycle.
- HealthKit permissions remain user-controlled; this refactor centralizes policy, not entitlement scope.
- No data migration is needed.

## Scope
In scope:
- Consolidate app UI HealthKit ownership to the app-injected service.
- Centralize duplicated workout overlap matching logic.
- Centralize reusable authorization/policy entry points used by views/view models.

Out of scope:
- Reworking widget extension behavior.
- Changing HealthKit data model fields or storage schema.
- Full rewrite of App Intent HealthKit flow.

## Impacted Paths
- `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift`
- `/Users/nadav/Desktop/Trai/Trai/Core/Services/HealthKitService.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatView.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Weight/WeightTrackingView.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/LogWeightSheet.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutView.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel+HealthKit.swift`

## Execution Plan

### Phase 1: Make app-environment HealthKit the canonical app UI source
- [x] Replace per-view `@State private var healthKitService = HealthKitService()` in app feature views with `@Environment(HealthKitService.self)` access.
- [x] Ensure `TraiApp` remains the single creator/injector for app runtime HealthKit service.
- [x] Keep optional-safe behavior for previews and contexts where environment may be absent.

### Phase 2: Centralize HealthKit policy entry points
- [x] Add/normalize service-level helpers for common app policies (authorize-if-needed, safe fetch/save with typed errors).
- [x] Rewire feature call sites to these helpers instead of repeating inline `requestAuthorization` + `do/catch` policy.
- [x] Keep UI-specific messaging in feature layer, but keep auth/sync policy in service layer.

### Phase 3: Consolidate workout overlap matching logic
- [x] Move overlap matching algorithm and end-date fallback into one reusable implementation (service or dedicated helper).
- [x] Update both:
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel+HealthKit.swift`
  to call the canonical matcher.
- [x] Remove duplicate local matcher functions.

### Phase 4: Tighten live workout + watch integration wiring
- [x] Ensure `LiveWorkoutViewModel` always uses the injected app service instance for streaming and recent-sample seeding.
- [x] Preserve existing reliability behavior from current code: explicit auth request and immediate seed sample while anchored query warms up.

### Phase 5: Validate compile safety and behavior parity
- [x] Grep guardrails:
  - `rg -n "@State\\s+private\\s+var\\s+healthKitService\\s*=\\s*HealthKitService\\(" /Users/nadav/Desktop/Trai/Trai -g"*.swift"`
  - Expected: no app view-level allocations remain.
- [x] Grep for duplicate overlap matcher definitions:
  - `rg -n "findBestOverlappingWorkout|calculateEndDate|calculateHealthKitEndDate" /Users/nadav/Desktop/Trai/Trai/Features/Workouts -g"*.swift"`
  - Expected: one canonical implementation path.
- [x] Focused build check:
  - `xcodebuild -project /Users/nadav/Desktop/Trai/Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiDerived CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
  - Result note: build is blocked in this environment by existing simulator/plugin issues (`PreviewsMacros.Common` in widget previews and CoreSimulator runtime service availability), not by compile errors in modified HealthKit files.

## Validation Checklist
- [ ] Dashboard activity card still loads steps/calories/exercise values.
- [ ] Workouts tab still imports and de-duplicates HealthKit workouts.
- [ ] Completed live workouts still merge with best overlapping HealthKit workout.
- [ ] Chat meal acceptance still syncs calories to HealthKit when enabled.
- [ ] Weight logging/sync still works in `LogWeightSheet` and `WeightTrackingView`.
- [ ] Live workout HR/calorie streaming still starts and updates.

## Risks and Mitigations
- Risk: missing environment injection in preview or modal path leads to nil service at runtime.
  - Mitigation: optional-safe guards with explicit fallback messaging and preview coverage.
- Risk: centralizing authorization could unintentionally alter when permission prompts appear.
  - Mitigation: preserve current call timing semantics per feature and gate only duplicate calls.
- Risk: overlap matching behavior changes historical merges.
  - Mitigation: keep current buffer and strength-preference logic unchanged while relocating code.

## Rollback
- Revert service ownership rewires in feature views/view models.
- Restore local matcher functions in both workout files.
- Revert centralized HealthKit policy helpers if regressions appear.
- No schema/data migration rollback required.

## Candidate Ranking (Scored)
| Candidate | Payoff (30%) | Blast Radius (25%) | Cognitive Load Reduction (20%) | Velocity Unlock (15%) | Validation/Rollback (10%) | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| Consolidate app UI HealthKit ownership + canonical matcher (chosen) | 4 | 4 | 5 | 4 | 4 | 4.20 |
| Consolidate workout start/creation flow (`ContentView`, `DashboardView`, `WorkoutsView`, `ChatViewActions`) | 5 | 2 | 4 | 4 | 3 | 3.70 |
| Merge `GeminiService`/`GeminiFunctionExecutor` function-calling orchestration into one layer | 4 | 2 | 4 | 4 | 3 | 3.40 |
| Collapse thin widget quick-food intents into one parameterized intent surface | 2 | 5 | 2 | 2 | 5 | 3.05 |
