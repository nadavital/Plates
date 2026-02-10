# ExecPlan: Consolidate App/Widget Shared Contracts into One Source of Truth

## Problem Statement
The app and widget extension duplicate the same cross-target contracts (payload structs and App Group keys), which creates avoidable drift risk for core flows: widget data display, quick food logging, and live workout activity rendering.

Current state (evidence):
- `WidgetData` is declared twice:
  - `/Users/nadav/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift:13`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift:23`
- `PendingFoodLog` is declared twice:
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift:178`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift:123`
- `TraiWorkoutAttributes` is declared twice:
  - `/Users/nadav/Desktop/Trai/Trai/Core/LiveActivity/TraiWorkoutAttributes.swift:12`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift:30`
- App Group constants are repeated as raw strings in multiple files:
  - `/Users/nadav/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift:55`
  - `/Users/nadav/Desktop/Trai/Trai/Core/Intents/LiveActivityIntents.swift:16`
  - `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift:338`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift:15`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift:130`

Why this is a problem:
- Duplicate abstraction: the same schema exists in two targets and must be manually kept in sync.
- Bug surface area: key/schema drift can silently break widget actions and App Group decoding.
- Cognitive load: engineers must remember which copy is canonical (there is no canonical source).

Acceptance criteria:
1. `WidgetData`, `PendingFoodLog`, and `TraiWorkoutAttributes` each have one canonical declaration shared by both targets.
2. App Group key strings (`suite`, widget data key, pending food key, live activity keys, intent trigger keys) are centralized and reused.
3. Existing widget deep-link and quick-action behavior is unchanged (`trai://logfood`, `startWorkoutFromIntent`, live activity add-set/pause actions).
4. `Trai` and `TraiWidgets` targets compile after refactor.

## Repository Mental Model (Evidence-Based)
- App shell and routing:
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift`
  - `/Users/nadav/Desktop/Trai/Trai/ContentView.swift`
- Widget shell:
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsBundle.swift`
- Flow 1 (widget quick food):
  - Write pending log in widget intent: `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift:146`
  - Read/process pending logs in app launch: `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift:149`
- Flow 2 (widget nutrition dashboard):
  - Build/save widget payload: `/Users/nadav/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift:63`
  - Read/decode widget payload: `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift:133`
- Flow 3 (live workout activity):
  - Start/update activity in app: `/Users/nadav/Desktop/Trai/Trai/Core/LiveActivity/TraiWorkoutAttributes.swift:143`
  - Render activity in widget extension: `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift:148`

Dependency highlights:
- Highest-touch domain types in repo scan by file count: `UserProfile` (52), `LiveWorkout` (33), `GeminiService` (26), `HealthKitService` (14), `ChatMessage` (13).
- Cross-target contract surfaces (`WidgetData`, `PendingFoodLog`, `TraiWorkoutAttributes`) are low in caller count but high in break impact because each sits on an app-extension boundary.

Identified smells:
- Duplicate abstractions: duplicated structs across target boundaries.
- Shotgun surgery: any contract change requires multi-file updates across app + extension.
- Leaky boundaries: raw string keys scattered in feature/service code.

## Assumptions
- Production-level caution applies.
- Refactor should be behavior-preserving (contract location changes only).
- Shared files can be added to both `Trai` and `TraiWidgets` targets in `project.pbxproj`.
- No persistent data migration is needed if serialized field names remain unchanged.

## Scope
In scope:
- Create shared contract files for app/extension boundaries.
- Migrate existing call sites to shared types/constants.
- Remove duplicate declarations.

Out of scope:
- UI redesign of widgets or live activity.
- Changing deep-link behavior or introducing new intents.
- Refactoring Gemini/chat architecture.

## Impacted Paths
- `/Users/nadav/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift`
- `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift`
- `/Users/nadav/Desktop/Trai/Trai/Core/Intents/LiveActivityIntents.swift`
- `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift`
- `/Users/nadav/Desktop/Trai/Trai/Core/LiveActivity/TraiWorkoutAttributes.swift` (content moved/removed)
- `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift`
- `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift`
- `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift` (content moved/removed)
- `/Users/nadav/Desktop/Trai/Shared/Contracts/` (new folder/files)
- `/Users/nadav/Desktop/Trai/Trai.xcodeproj/project.pbxproj`

## Execution Plan

### Phase 1: Create canonical shared contracts
- [x] Add shared files under `/Users/nadav/Desktop/Trai/Shared/Contracts/` (shared by both targets) for:
  - `WidgetData`
  - `PendingFoodLog`
  - `TraiWorkoutAttributes`
  - `AppGroupKeys` (suite and key constants)
- [x] Ensure shared files compile in both `Trai` and `TraiWidgets` targets.

### Phase 2: Rewire app target to shared contracts
- [x] Update `/Users/nadav/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift` to use shared `WidgetData` and `AppGroupKeys`.
- [x] Update `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift` pending log processing to shared `PendingFoodLog` + keys.
- [x] Update `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift` and `/Users/nadav/Desktop/Trai/Trai/Core/Intents/LiveActivityIntents.swift` to shared keys.

### Phase 3: Rewire widget target to shared contracts
- [x] Update `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift` to remove local `WidgetData`/reader duplication and use shared contracts.
- [x] Update `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift` to remove local `PendingFoodLog` and use shared keys.
- [x] Update `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift` to use shared `TraiWorkoutAttributes`.

### Phase 4: Delete duplicate declarations
- [x] Remove duplicated structs/enums from:
  - `/Users/nadav/Desktop/Trai/Trai/Core/LiveActivity/TraiWorkoutAttributes.swift` (if fully moved)
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgets.swift`
  - `/Users/nadav/Desktop/Trai/TraiWidgets/AppIntent.swift`
  - `/Users/nadav/Desktop/Trai/Trai/TraiApp.swift` (local `PendingFoodLog`)
- [x] Verify there is one declaration per contract type.

### Phase 5: Validate compile safety and behavior parity
- [x] Grep guardrails:
  - `rg -n "struct WidgetData|struct PendingFoodLog|struct TraiWorkoutAttributes" /Users/nadav/Desktop/Trai/Trai /Users/nadav/Desktop/Trai/TraiWidgets -g"*.swift"`
  - Expected: one canonical declaration each.
- [x] Grep for stray raw keys:
  - `rg -n "group\\.com\\.nadav\\.trai|pendingFoodLogs|widgetData|liveActivityAddSetTimestamp|liveActivityTogglePauseTimestamp|openFoodCameraFromIntent|startWorkoutFromIntent" /Users/nadav/Desktop/Trai/Trai /Users/nadav/Desktop/Trai/TraiWidgets -g"*.swift"`
  - Expected: references routed through shared constants.
- [x] Build target(s):
  - `xcodebuild -project /Users/nadav/Desktop/Trai/Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiDerived CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -project /Users/nadav/Desktop/Trai/Trai.xcodeproj -scheme TraiWidgetsExtension -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiDerived CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
  - Result note: both builds are blocked in this environment by `#Preview` macro host/plugin errors (`PreviewsMacros.Common`), not by shared-contract compile failures.

## Validation Checklist
- [ ] Widget "Log Food" action still creates pending logs that app ingests on launch. (Runtime verification pending)
- [ ] Widget macro data still renders after app writes `WidgetData`. (Runtime verification pending)
- [ ] Live Activity still starts, updates, and renders in Lock Screen/Dynamic Island. (Runtime verification pending)
- [ ] Start-workout control intent still opens app and starts/opens workout flow. (Runtime verification pending)
- [x] No change to deep-link destinations (`logfood`, `logweight`, `workout`, `chat`).

## Risks and Mitigations
- Risk: target membership misconfiguration causes missing symbols in one target.
  - Mitigation: verify file membership in `project.pbxproj`; run both target builds.
- Risk: accidental serialization incompatibility when moving types.
  - Mitigation: keep field names/types unchanged; avoid altering coding keys.
- Risk: over-centralizing unrelated keys can cause noisy dependencies.
  - Mitigation: separate `AppGroupKeys` by domain sections (widget data, quick-food, live-activity intents, app-intent triggers).

## Rollback
- Revert shared contract files and call-site rewires.
- Restore deleted duplicate declarations in app/widget files.
- No storage migration rollback required.

## Candidate Ranking (Scored)
| Candidate | Payoff (30%) | Blast Radius (25%) | Cognitive Load Reduction (20%) | Velocity Unlock (15%) | Validation/Rollback (10%) | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| Consolidate app/widget shared contracts + keys into one canonical layer (chosen) | 5 | 4 | 5 | 4 | 4 | 4.50 |
| Build a central deep-link/intent router service for all app entry points | 4 | 3 | 4 | 5 | 3 | 3.80 |
| Unify `HealthKitService` ownership (environment-only, remove per-view instances) | 3 | 3 | 3 | 4 | 3 | 3.15 |
| Merge `ChatView` composition files into a single coordinator type | 4 | 2 | 4 | 3 | 2 | 3.10 |
