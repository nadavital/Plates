# Trai Notes Implementation Tracker

Last updated: 2026-02-13

## Status Legend
- `OPEN`: Not implemented
- `PARTIAL`: Implemented in part, still gaps
- `DONE`: Implemented
- `VERIFY`: Needs runtime verification
- `IN PROGRESS`: Currently being implemented

## Master Checklist
| # | Note | Status | Primary Area |
|---|---|---|---|
| 1 | Select exercise sheet ordering is whack | DONE | Workouts / Add Exercise |
| 2 | Trai tab latency for typing and interactions | VERIFY | Chat / Trai tab |
| 3 | Trai not able to get workouts accurately | DONE | Gemini function executor |
| 4 | Live Activity shows first exercise only; watch look/icon/theme mismatch | DONE | Live Activity + Widgets |
| 5 | Edit preset workout days/templates (PPL), include abs preference | DONE | Workout plan editing |
| 6 | Custom exercises not in muscle category unless searched | DONE | Workouts / Add Exercise |
| 7 | Target muscle chips (text add exercise sheet) unequal height | DONE | Add custom exercise UI |
| 8 | Suggestion for weight increase threshold (e.g. 3x12) | DONE | Progression logic |
| 9 | Typing and adding latency too slow | VERIFY | Chat / input flows |
| 10 | Edit warm-up; add/remove sets and exercises from edit workout sheet | DONE | Workout editing |
| 11 | Food image analysis logs unwanted partial items | DONE | Vision + food prompts |
| 12 | Block multiple taps for food logging in Trai tab | DONE | Chat meal logging |
| 13 | Recently used exercises should match targeted muscles | DONE | Add Exercise recent list |
| 14 | Live Activity rounding issue (200 shows 199) | DONE | Live Activity state |
| 15 | Logging weight with Trai didn’t work/respond | DONE | Chat function calling |
| 16 | Replace weight-history log sheet with quick actions sheet | DONE | Weight logging UI |
| 17 | Differentiate similar machines from image (vision prompt) | DONE | Exercise vision prompt |
| 18 | Switch target muscle groups mid-workout | DONE | Live workout UI |
| 19 | Show PRs in workout detail view | DONE | Workout detail UI |
| 20 | Rethink train symbol | DONE | Brand/iconography |
| 21 | Better custom workout title from selected muscle groups | DONE | Workout naming |
| 22 | Calorie breakdown top ring text overflow | DONE | Dashboard calorie UI |

## Implementation Queue
1. #2/#9 Runtime verify typing/interaction latency on device/simulator
2. Runtime QA sweep for #1/#8/#10 on device/simulator
3. #15 Optional extra QA: direct-message edge cases in production-style usage

## Runtime QA Checklist
| Area | Scenario | Expected | Status |
|---|---|---|---|
| App launch | Launch on iPhone simulator after clean build | App launches and stays alive | PASS (smoke) |
| #15 log weight | Message: "log 182 lbs" | Weight saved, explicit confirmation text shown | PENDING |
| #15 log weight | Message: "82 kg" (no explicit command) | Quick fallback logs weight if model no-response | PENDING |
| #15 log weight | Message with bad value (e.g., "log my weight as ???") | User sees explicit error fallback text | PENDING |
| #2/#9 latency | Type rapidly in Trai tab with long chat history | No perceptible keyboard/input lag | PENDING |
| #2/#9 latency | While AI is streaming, interact with input/menu/buttons | Interactions remain responsive | PENDING |
| #1 ordering | Open add-exercise sheet with target muscles set | Target muscle groups and recent usage appear in deterministic priority order | PENDING |
| #8 progression | Generate next workout after prior `3x12` style completion | Weight increases only when rep-trigger criteria are met across working sets | PENDING |
| #10 edit workout | In completed workout edit: toggle warm-up, add/remove sets/exercises | Changes persist and history sync reflects edits | PENDING |

## Progress Log
- 2026-02-07: Initialized tracker with baseline statuses from code audit.
- 2026-02-07: Started implementation of #3.
- 2026-02-07: Completed #3 by changing recent-workout ordering to sort by actual `Date` values (not formatted date strings) in `GeminiFunctionExecutor+PlanWorkout`.
- 2026-02-07: Build check still fails due pre-existing errors in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift` (missing `import os`), with no reported errors from the updated workout executor file.
- 2026-02-07: Started #4 by updating Live Activity progression logic in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift` to advance based on logged set data/cardio completion rather than `set.completed`.
- 2026-02-07: Verified no compile errors reported for `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift`; build still blocked by the same pre-existing `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift` errors.
- 2026-02-07: Updated Live Activity widget visuals in `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift` to use Trai’s existing symbol (`circle.hexagongrid.circle`) and app-aligned accent/neutral colors instead of the prior orange/green status styling.
- 2026-02-07: Verified no compile errors reported for `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift`; build remains blocked by the same pre-existing `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift` errors.
- 2026-02-07: Completed #6 by making quick-add custom exercises inherit category/muscle context in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/ExerciseListView.swift`, including backfilling missing muscle group on matching existing strength custom exercises when context is available.
- 2026-02-07: Completed #11 by updating food image prompts in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiPromptBuilder.swift` and `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiChatPrompts.swift` to prioritize intended meal items and ignore incidental/background items.
- 2026-02-07: Completed #18 by removing muscle selector expansion gating in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/MuscleGroupSelector.swift`, allowing target-muscle edits mid-workout.
- 2026-02-07: Consolidated filtered build check reported no errors in updated files (`LiveWorkoutViewModel.swift`, `TraiWidgetsLiveActivity.swift`, `ExerciseListView.swift`, `GeminiPromptBuilder.swift`, `GeminiChatPrompts.swift`, `MuscleGroupSelector.swift`); build remains blocked by pre-existing `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift` errors.
- 2026-02-07: Completed #7 by normalizing target-muscle chip height in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/AddCustomExerciseSheet.swift` with a fixed minimum content height for each muscle chip.
- 2026-02-07: Completed #22 by tightening center-ring text scaling/constraints in `/Users/nadav/Desktop/Trai/Trai/Features/Dashboard/CalorieDetailSheet.swift` to prevent overflow for larger values.
- 2026-02-07: Completed #19 by adding PR highlights (weight/reps/volume vs prior history) to `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutDetailSheet.swift`.
- 2026-02-07: Completed #20 symbol pass by replacing `circle.hexagongrid.circle` with `brain.head.profile` across Trai entry points (`ContentView`, `LiveWorkoutComponents`, widgets, and shortcuts) for a more coach-specific identity.
- 2026-02-07: Completed #4 Apple Watch/small-family Live Activity pass in `/Users/nadav/Desktop/Trai/TraiWidgets/TraiWidgetsLiveActivity.swift` by adding supplemental activity families and compact small-family presentation.
- 2026-02-07: Improved #15 by fixing chat non-response path for `log_weight` in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+FunctionCalling.swift` (added `log_weight` to fallback data-function summaries) and activity labeling in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewMessaging.swift`.
- 2026-02-07: Completed #5 with direct template-day editing controls in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanEditSheet.swift` (day focus presets like Push/Pull/Legs/Upper/Lower/Full Body/Core, per-day core toggle, and global “core in all workouts” toggle).
- 2026-02-07: Completed #21 by routing quick-start custom workouts through `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/CustomWorkoutSetupSheet.swift` from `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift`, so names default from selected muscle groups before workout start.
- 2026-02-07: Hardened #15 with a final safety fallback in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+FunctionCalling.swift` that always emits a local confirmation message after successful `log_weight` calls if model follow-up text is empty.
- 2026-02-07: Completed #17 by strengthening machine-photo prompt specificity in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+Exercise.swift` (explicit variant disambiguation and visible brand/model preference).
- 2026-02-07: Improved #2/#9 latency in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewMessaging.swift` by throttling streamed text UI updates to reduce re-render pressure during active responses.
- 2026-02-07: Completed #8 by tightening double-progression logic in `/Users/nadav/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift` to require rep-trigger completion across working set patterns (e.g., true `3x12`) before increasing weight.
- 2026-02-07: Completed #1 ordering pass in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/ExerciseListView.swift` with deterministic section ordering, target-muscle priority ordering, and recency-aware exercise ranking.
- 2026-02-07: Completed #10 in `/Users/nadav/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutDetailSheet.swift` by adding edit-mode controls for warm-up toggles, add/remove sets, add/remove exercises, and history sync for added/removed entries.
- 2026-02-07: Further improved #15 reliability by adding explicit weight-tool routing guidance in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+FunctionCallingHelpers.swift` and hardening `log_weight` argument parsing/date normalization in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiFunctionExecutor+PlanWorkout.swift`.
- 2026-02-07: Focused build check reported no errors for updated files (`WorkoutTemplateService.swift`, `ExerciseListView.swift`, `LiveWorkoutDetailSheet.swift`); build remains blocked by pre-existing `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift` (`import os` missing) errors.
- 2026-02-07: Additional #2/#9 latency pass in chat (`/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatInputBar.swift`, `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatView.swift`, `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewMessaging.swift`, `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatMessageViews.swift`) by isolating input draft state from the parent view and caching formatted AI markdown paragraphs to reduce typing/interaction re-render pressure.
- 2026-02-07: Removed the pre-existing build blocker by adding `import os` in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+PlanPipeline.swift`; project build now succeeds (`xcodebuild ... Trai`).
- 2026-02-07: Hardened #15 `log_weight` parsing in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiFunctionExecutor+PlanWorkout.swift` to accept integer/string values, infer units from strings like `"182 lbs"`, and fall back to profile unit preference when unit is omitted; updated `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiFunctionDeclarations.swift` to only require `weight`.
- 2026-02-07: Additional #2/#9 render-path cleanup in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatContentList.swift` by pre-filtering visible messages once before `ForEach` to reduce repeated branching work during updates.
- 2026-02-07: Full project build remains green after latest changes (`** BUILD SUCCEEDED **`).
- 2026-02-07: Additional #2/#9 stream-path optimization in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatViewMessaging.swift` by replacing per-chunk delayed task churn with direct 50ms render gating.
- 2026-02-07: Additional #15 safety in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+FunctionCalling.swift` to emit explicit fallback error text when `log_weight` fails and the model returns no follow-up message.
- 2026-02-07: Added quick no-response fallback for direct weight-entry messages in `/Users/nadav/Desktop/Trai/Trai/Core/Services/GeminiService+FunctionCalling.swift` to execute `log_weight` when the model returns no function/text, and marked #15 as DONE.
- 2026-02-07: Runtime smoke check completed on iOS simulator (`iPhone 16e`) by building, installing, launching, and confirming the app process stayed alive for 5s before explicit termination.
- 2026-02-07: Additional #2/#9 optimization by rendering the actively streaming AI bubble as plain text (skip markdown parsing until stream completion) in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatContentList.swift` and `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatMessageViews.swift`.
- 2026-02-07: Additional #2/#9 optimization in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatContentList.swift` + `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatMessageViews.swift` to limit text selection to the most recent AI messages, reducing interaction overhead in long chat histories.
- 2026-02-07: Additional #2/#9 optimization in `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatMessageViews.swift` + `/Users/nadav/Desktop/Trai/Trai/Features/Chat/ChatContentList.swift` to restrict heavy state animations to the newest visible message only, reducing update overhead in long threads.

### 2026-02-13: Trai Pulse Surface Expansion (Habit-aware + broader action routing)
- DONE: Added plan-review and habit context inputs to `DailyCoachContext`, `TraiPulseInputContext`, and context assembly (`reminderCompletionRate`, weight cadence fields, exercise timing, plan review metadata).
- DONE: Expanded Pulse action enums and schema to remove chat-style actions and add explicit navigation/actions (`open_weight`, `open_calorie_detail`, `open_macro_detail`, `open_profile`, `open_workouts`, `open_workout_plan`, `open_recovery`, `open_reminders`, `start_workout_template`, `log_food_camera`, `log_weight`).
- DONE: Wired action handling in Dashboard flow (`DashboardView`) for new action types and added missing sheet entry points where needed (`WeightTrackingView`, calorie/macro detail sheets).
- DONE: Added habit-aware context packet candidates for reminders/weight and plan review (weight cadence, plan age/weight flags), plus contextual suppression support by removing always-on detail actions.
- IN PROGRESS: Decide whether to add first-class Pulse prompts for reminder-window nudges and plan-edit timing nudges before finalizing model policy.
