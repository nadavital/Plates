# Food Recommendation Review Follow-up

Use this brief after `.agent/done/food-recommendations-observations-habits-replay.md`. The implementation is promising, but it is not ready until the review findings below are fixed and verified against real user-history replay.

## Goals

1. Fix the four review findings without broad rewrites.
2. Add regression tests that fail on the current implementation.
3. Add a real-data comparison path that can show whether the new recommender improves over the old memory-based suggestion path.
4. Do not commit private food history. Real-data tooling may print local diagnostics, but fixtures must remain synthetic or anonymized.

## Required Fixes

### 1. Filter Recommendations To The Target Instant

Problem: `FoodRecommendationEngine` receives all fetched entries, builds habits from every observation, and constructs `todayObservations` / `recentObservations` through the end of the target day. This can train on future logs or suppress suggestions because of logs that happen later than the requested recommendation time.

Implementation direction:

- In `FoodRecommendationEngine.recommendationsSync`, derive an eligible observation set before building habits and context.
- For habit training and ranking, ignore observations with `loggedAt >= request.targetDate`.
- In `FoodRecommendationContext`, bound `todayObservations` and `recentObservations` by `targetDate`, not end-of-day.
- `currentSessionObservations` should also only include observations before `targetDate`.
- Keep same-day repeat support, but make it reason about entries already logged before the target instant.

Required tests:

- Add an engine or integration test where a future same-day dinner exists and a noon recommendation is requested. The dinner must not suppress or influence the noon result.
- Add a test where a one-off future food exists after `targetDate`; it must not become a candidate, habit, or debug observation count for that target instant.
- Add a test where a valid earlier-today log suppresses an already-logged suggestion, proving the cutoff still preserves useful suppression.

### 2. Preserve Feedback For Observation-built Habit Suggestions

Problem: engine suggestions may use a synthetic stable habit UUID when no linked `FoodMemory` exists. `recordOutcomes` and `reconcileShownSuggestions` only update `FoodMemory` rows, so feedback for those suggestions is silently dropped.

Implementation direction:

- Pick one feedback model and make it explicit:
  - Preferred for now: ensure user-visible suggestions resolve to a real `FoodMemory` id before feedback is recorded. If a habit has no linked memory, materialize or link a candidate memory for the representative habit before returning it from `FoodSuggestionService`.
  - Alternative: introduce persisted habit-level feedback keyed by habit id, but this is broader and should only be done if it stays contained.
- Avoid returning IDs that cannot later be reconciled.
- Update `FoodSuggestionIntegrationTests.testCameraSuggestionsPreserveExistingOutcomeRecording` so it proves stats changed on a persisted row, not just that `recordOutcome` does not throw.

Required tests:

- For entries with no existing memories, request suggestions, record `.shown`, then verify a persisted record has `timesShown > 0`.
- Record `.accepted` through the normal reconcile path for an observation-built suggestion and verify positive feedback is stored.
- Verify feedback affects later ranking or suppression enough that the test would catch dropped feedback.

### 3. Require Macro Compatibility For Exact Component Matching

Problem: `FoodMemoryMatcher.matches(entry:memory:)` returns true for exact component-name sets before checking calories/macros. That can match a normal meal to a much larger version of the same components.

Implementation direction:

- Keep the component shortcut only if nutrition/macro compatibility also passes.
- Prefer canonical component names from `FoodNormalizationService` instead of raw `normalizedName` sets.
- Preserve the existing snapshot matcher behavior for fuzzy component/name/embedding matches.

Required tests:

- Add a matcher test with identical components but very different calories/macros; it must not match.
- Add a matcher test with identical components and compatible macros; it should match.
- Add a test where display/normalized component aliases normalize to the same canonical component set.

### 4. Make Replay Actually Exercise Session Context

Problem: `FoodRecommendationReplayConfig.includeSessionContext` is currently unused, and `FoodRecommendationEvaluator` always passes `sessionID: nil`. Session-completion behavior is therefore not evaluated by replay.

Implementation direction:

- Extend `FoodRecommendationReplayRunner.RecommendationProvider` to accept the hidden observation's session id and any available current-session prefix.
- When `includeSessionContext == true`, build replay cases that can include observations earlier in the same session before the hidden item while still hiding the target item and later items.
- When `includeSessionContext == false`, keep the current no-session behavior.
- Do not let same-day or same-session future items leak into training.

Required tests:

- Add a replay test where historical sessions repeatedly log `coffee -> bagel`; when hiding `bagel`, the session-aware replay with current `coffee` context should hit, while no-session replay should be weaker or miss.
- Add a test proving later items in the same session are not present in the provider training data.
- Add a test proving `includeSessionContext: false` passes `nil` session context.

## Real-data Improvement Verification

Synthetic tests prove invariants, not product quality. Add a local-only comparison workflow that can run against the user's actual accepted food history on the development build.

### Recommended Tooling

Add a debug-only Developer Settings action or gated debug command:

`Run Food Recommendation Replay Comparison`

It should:

- Fetch real local `FoodEntry` and `FoodMemory` data from the app's current `ModelContext`.
- Build replay cases from accepted snapshots only.
- Run both the new observation/habit recommender and the old memory-based suggestion path on the same hidden-log cases.
- Print and show aggregate metrics in a debug sheet or console.
- Save only aggregate metrics and anonymized diagnostics unless the developer explicitly opts into local detailed titles.

### Fair Old-vs-new Comparison

The old path must not receive future memory data. A fair replay needs training-only state for each hidden case:

1. Sort accepted entries by `loggedAt`.
2. For each hidden case, create an in-memory `ModelContext`.
3. Insert only training entries available before the hidden target instant, plus same-session prefix entries if session context is enabled.
4. Run the existing food-memory resolution/maintenance pipeline to build training-only `FoodMemory` rows.
5. Run the legacy memory suggestion provider against that in-memory context.
6. Run the new engine against the same training entries and training memories.
7. Compare each provider against the hidden observation using the same close-equivalent matcher.

If rebuilding memories per case is too slow, add a capped mode first, for example `maximumCases: 50`, and print runtime. Do not use all current persisted memories for historical old-path replay unless the report labels it as leaky and diagnostic-only.

### Metrics To Report

Report overall and by time slice:

- evaluated cases
- Hit@1, Hit@3, Hit@5
- mean reciprocal rank
- one-off false-positive rate
- beverage domination rate for hidden complete meals
- complete-meal coverage rate
- duplicate suggestion rate
- no-suggestion rate
- median and p95 runtime per case

Time slices:

- 5am-10am
- 10am-2pm
- 2pm-5pm
- 5pm-9pm
- 9pm-1am
- weekday vs weekend
- with session prefix vs without session prefix

### Current-moment Snapshot Comparison

Also add a debug report that asks both recommenders what they would suggest now for realistic target times using all current history:

- today at 8am
- today at noon
- today at 3pm
- today at 7pm
- today at 10pm
- tomorrow at the same five times

Print side-by-side top 5 suggestions:

```
target=2026-05-05 12:00
new: Chicken Rice Bowl | Greek Yogurt Bowl | ...
old: Latte | Cappuccino | ...
```

This is not a rigorous replay metric, but it is the fastest way to inspect whether the recommendations feel better with real data.

## Definition Of Done

- All four review findings are fixed.
- Each fix has a regression test that fails before the fix.
- Focused recommendation tests pass.
- Food-memory matcher/storage regression tests pass.
- A simulator or device build succeeds.
- The debug replay comparison runs on real local data.
- The final report includes old-vs-new metric tables plus a few representative failed cases.
- If new metrics do not clearly improve, do not mark the task complete. Use failed cases to tune ranking, suppression, habit grouping, or feedback handling and rerun.

## Suggested Validation Commands

Run focused tests:

```sh
xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiFoodRecommendationFocused -resultBundlePath /private/tmp/TraiFoodRecommendationFocused.xcresult CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:TraiTests/FoodRecommendationEvaluatorTests -only-testing:TraiTests/FoodRecommendationHabitTests -only-testing:TraiTests/FoodRecommendationCandidateTests -only-testing:TraiTests/FoodRecommendationRankerTests -only-testing:TraiTests/FoodSuggestionIntegrationTests -only-testing:TraiTests/FoodRecommendationLegacyCleanupTests test
```

Run food-memory regressions:

```sh
xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiFoodRecommendationMemory -resultBundlePath /private/tmp/TraiFoodRecommendationMemory.xcresult CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:TraiTests/FoodMemoryFoundationTests -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodMemoryMatcherTests test
```

Run a build:

```sh
xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/TraiFoodRecommendationBuild CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Run whitespace check:

```sh
git diff --check
```
