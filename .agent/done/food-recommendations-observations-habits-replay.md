# Rebuild Food Suggestions Around Observations, Habits, and Replay Evaluation

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This plan follows `.agent/PLANS.md` in this repository. If you revise this plan, keep it self-contained: a future agent should be able to read only this file and implement the feature without prior conversation context.

## Purpose / Big Picture

Trai should proactively suggest foods that are as close as possible to what the user would actually log. The current food-memory-based system can surface low-value or one-off items because it tries to recommend individual `FoodMemory` rows, and real user data can fragment repeated foods into many near-duplicate memories. The rebuilt system should instead learn from accepted food logs as observations, group repeated behavior into habits, and rank those habits using repetition, time, session context, recency, usefulness, and feedback.

After this work, opening the food camera or food logging surface should show suggestions that feel like "Trai noticed what I usually eat" rather than "Trai remembered a random food once." For example, if a user repeatedly logs chicken and rice under slightly different names, the top suggestions should include a useful chicken/rice meal; if the user logged Katz's pastrami sandwich one time, it should not appear as a proactive suggestion unless the user later repeats or pins it.

The implementation must be measurable. Before replacing the visible suggestion engine, build an offline replay evaluator that uses existing accepted food logs as test data. The evaluator hides historical logs one at a time, asks the recommender what it would have suggested at that time, and reports hit-rate and failure diagnostics. The long-horizon agent should iterate until synthetic tests pass and real-device replay metrics clearly beat the old/current suggestion behavior.

## Progress

- [x] (2026-05-05 12:10Z) Authored this ExecPlan and saved it at `.agent/execplan-pending.md`.
- [x] (2026-05-05 19:05Z) Milestone 1: Added `FoodRecommendationEvaluator` replay support with hit-rate, usefulness, duplicate, one-off, beverage, and complete-meal diagnostics.
- [x] (2026-05-05 19:15Z) Milestone 2: Added observation and habit domain types derived from `FoodEntry.acceptedSnapshot` through `FoodObservationBuilder` and `FoodHabitBuilder`.
- [x] (2026-05-05 19:35Z) Milestone 3: Implemented candidate generators for repeat staples, time context, session completion, semantic variants, and recent repeated items.
- [x] (2026-05-05 20:05Z) Milestone 4: Implemented deterministic ranking and suppression for repeated habits, usefulness, already-logged items, negative feedback, duplicates, and beverage dominance.
- [x] (2026-05-05 20:30Z) Milestone 5: Wired the new recommender into `FoodSuggestionService` first, with the old memory candidate path and a compatibility fallback retained for empty-engine cases and debug comparison.
- [x] (2026-05-05 20:45Z) Milestone 6: Added a gated device/debug replay test workflow that can run locally without committing private food data. It was not run against private device history in this environment.
- [x] (2026-05-05 20:55Z) Milestone 7: Kept `FoodMemory` compatibility for persistence/matching while removing memory rows as the primary proactive suggestion primitive.
- [x] (2026-05-05 21:31Z) Milestone 8: Ran focused recommendation tests, food-memory regression tests, final simulator app build, and `git diff --check`.

## Surprises & Discoveries

- Observation: Prior device debug showed severe memory fragmentation: 452 accepted food entries produced 363 memories, and only 82 entries were matched to a memory.
  Evidence: The device maintenance debug output printed `totalEntries=452 tracked=452 legacy=0 memories=363 matched=82 candidates=370`.

- Observation: Scoring-only changes are insufficient if the data layer splits repeated staples into many low-evidence rows.
  Evidence: After maintenance, suggestions were still beverage-heavy: breakfast showed `Low-fat Latte | Low-fat Iced Latte`, lunch showed `Cappuccino | Barebells Protein Bar | Low-fat Iced Latte`, and dinner/late suggestions showed only `Latte`.

- Observation: Simulator tests involving `NLContextualEmbedding` can skip because NaturalLanguage model assets fail to load in the simulator environment.
  Evidence: Simulator logs can include `Failed to load embedding model` and permission errors under `/var/db/com.apple.naturallanguaged`. Treat clean skips for live embedding tests as acceptable, but deterministic embedding math and ranking tests must still run.

- Observation: Repeated complete-meal habits need to be allowed across coarse meal buckets, but low-utility single-item foods need stricter time/context suppression.
  Evidence: Integration tests cover strong habits crossing meal buckets, morning-only suggestions being suppressed late at night, and active-session completion suppression when the historical session usually ends after the current item.

- Observation: Historical session completion data is sparse in synthetic and early-user cases, so the session generator needs a fallback for repeated multi-component habits when the current session contains a strict subset of the habit.
  Evidence: `FoodRecommendationCandidateTests.testSessionCompletionGeneratorUsesCurrentSessionAnchors` now covers chicken implying chicken/rice without treating exact duplicates as completion candidates.

## Decision Log

- Decision: Build the new recommender from `FoodEntry.acceptedSnapshot` observations first, not from new persisted SwiftData models.
  Rationale: Existing accepted snapshots are already the best source of truth for what the user actually confirmed. Avoiding a new SwiftData model in the first milestone reduces migration risk and lets us prove ranking quality before changing storage.
  Date/Author: 2026-05-05 / Codex

- Decision: Keep `FoodMemory` as compatibility infrastructure during the rebuild, but stop treating it as the primary suggestion primitive.
  Rationale: `FoodMemory` is still used by matching, reconciliation, stats, and existing tests. Removing it immediately would create a broad migration and regression risk. The user-visible suggestion engine should move to learned habits first; old memory concepts can be retired later once tests and metrics prove the new path.
  Date/Author: 2026-05-05 / Codex

- Decision: Use deterministic scoring before any learned model.
  Rationale: The app has one user's rich local history but not enough labeled suggestion outcomes for a trained ranker. A deterministic model can be made transparent, testable, and tunable with replay metrics. Later, suggestion accept/dismiss/refine feedback can train or calibrate a small learned ranker.
  Date/Author: 2026-05-05 / Codex

- Decision: Treat food suggestions as a next-log recommender, similar to next-basket recommendation, but optimized for one user's repeated food logging.
  Rationale: Food logging is mostly repeated behavior with context. Research on next-basket recommendation highlights long-term preference, short-term/session behavior, repetition, time, and feedback. In Trai, the most important first-party signal is repeated accepted logs.
  Date/Author: 2026-05-05 / Codex

- Decision: Keep the new recommendation engine deterministic and synchronous in the visible path, while preserving an async wrapper for future embedding-backed work.
  Rationale: The camera suggestion path should be fast and testable. Semantic support can participate through precomputed embeddings and compatibility data without making NaturalLanguage model loading a runtime dependency for every suggestion.
  Date/Author: 2026-05-05 / Codex

- Decision: Use a gated XCTest debug workflow for local private-history replay instead of adding committed fixtures or printing private logs by default.
  Rationale: The replay evaluator needs to be able to run against real local data, but user food history should remain on device/local machine only. The default simulator suite should stay deterministic and privacy-safe.
  Date/Author: 2026-05-05 / Codex

## Outcomes & Retrospective

Implemented a verified replacement for proactive food suggestions centered on accepted-log observations and grouped habits. The camera suggestion path now tries `FoodRecommendationEngine` first, maps habits to `FoodSuggestion`, records existing shown feedback, and falls back to legacy memory candidates only when the new engine returns nothing. Debug summaries now expose observation, habit, candidate, and suppression counts so future tuning can explain why a suggestion appeared or failed.

The implementation adds canonical component normalization, exact component compatibility in memory matching, replay evaluation, deterministic ranking, session/time/repetition candidate generation, and tests for habit clustering, candidate generation, replay matching, ranking suppression, legacy snapshot compatibility, and `FoodSuggestionService` integration.

Validation completed:

- `xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiFoodRecommendationFocusedFinal3 -resultBundlePath /private/tmp/TraiFoodRecommendationFocusedFinal3.xcresult CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:TraiTests/FoodRecommendationEvaluatorTests -only-testing:TraiTests/FoodRecommendationHabitTests -only-testing:TraiTests/FoodRecommendationCandidateTests -only-testing:TraiTests/FoodRecommendationRankerTests -only-testing:TraiTests/FoodSuggestionIntegrationTests -only-testing:TraiTests/FoodRecommendationLegacyCleanupTests test`
  Result: 29 tests, 0 failures.

- `xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiFoodRecommendationMemoryFinal4 -resultBundlePath /private/tmp/TraiFoodRecommendationFoodMemoryFinal4.xcresult CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:TraiTests/FoodMemoryFoundationTests -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodMemoryMatcherTests test`
  Result: 59 tests, 0 failures.

- `xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/TraiFoodRecommendationFinalBuild CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
  Result: build succeeded.

- `git diff --check`
  Result: passed.

Remaining product validation boundary: the private-history replay/debug workflow was added, but it was not run against the user's real device food history in this environment. That should be the next tuning step before claiming real-device replay metrics beat the old/current behavior.

## Context and Orientation

This repository is the Trai iOS app. App code lives under `Trai/`, tests live under `TraiTests/`, and the Xcode project is `Trai.xcodeproj`. Existing food suggestion behavior is centered around these files:

- `Trai/Core/Models/FoodEntry.swift`: SwiftData model for a logged food. It stores name, macros, timestamp, session id, input method, and an `acceptedSnapshot` encoded as data.
- `Trai/Core/Models/FoodMemory.swift`: SwiftData model representing a remembered food. It stores display name, aliases, component summaries, nutrition profile, time profile, suggestion stats, and optional embedding data.
- `Trai/Core/Models/FoodMemoryTypes.swift`: Shared codable types for accepted food snapshots, components, fingerprints, time profiles, suggestion stats, and related food-memory concepts.
- `Trai/Core/Services/FoodSnapshotBuilder.swift`: Builds an `AcceptedFoodSnapshot` when the user confirms a food log. A snapshot is an immutable description of what the user accepted at that moment: display name, components, macros, serving, timestamp, and edit state.
- `Trai/Core/Services/FoodMemoryService.swift`: Resolves food entries into memories, creates or updates `FoodMemory` rows, consolidates duplicates, and performs maintenance/backfill.
- `Trai/Core/Services/FoodMemoryMatcher.swift`: Decides whether a food entry or accepted snapshot matches a memory using names, components, macros, and embeddings.
- `Trai/Core/Services/FoodSuggestionService.swift`: Builds proactive food suggestions. This is the main user-facing suggestion service today.
- `Trai/Core/Services/FoodNormalizationService.swift`: Normalizes food names, components, serving text, and time labels.
- `Trai/Core/Services/FoodEmbeddingService.swift`: Wraps `NLContextualEmbedding` and embedding math for semantic similarity.
- `TraiTests/FoodMemoryServiceTests.swift`, `TraiTests/FoodMemoryMatcherTests.swift`, `TraiTests/FoodEmbeddingServiceTests.swift`, and `TraiTests/FoodMemoryFoundationTests.swift`: Existing tests for food memory storage, matching, suggestions, embeddings, and snapshot compatibility.
- `Trai/Features/Profile/DeveloperSettingsView.swift`: Developer/debug surface for maintenance and food-memory inspection.
- `Trai/Features/Food/FoodCameraView.swift`, `Trai/Features/Food/AddFoodView.swift`, `Trai/Features/Food/ManualFoodEntrySheet.swift`, and `Trai/Features/Chat/ChatViewActions.swift`: Save/logging flows that create accepted snapshots and resolve memories.

Definitions used in this plan:

An observation is one accepted food log. In this repository, an observation should initially be a new plain Swift struct derived from `FoodEntry` plus `AcceptedFoodSnapshot`; it should not be a new persisted model at first. It represents what the user actually confirmed.

A habit is a learned repeated pattern over observations. A habit is not a single saved memory row. A habit can represent multiple accepted logs with different names but similar components, macros, serving, and timing, such as "Chicken Rice Bowl", "Grilled Chicken With Rice", and "Chicken Breast and Brown Rice."

A candidate generator is code that proposes possible suggestions from one signal. For example, a repeat-staple generator proposes frequently repeated habits, while a session-completion generator proposes foods often logged with the current session.

A ranker is code that sorts candidate suggestions by usefulness and likelihood. It uses numeric features such as distinct days, decayed frequency, time support, session support, macro stability, positive feedback, negative feedback, and suppression rules.

Replay evaluation means testing the recommender against historical data by hiding a past log, building candidates from only earlier logs, and checking whether the hidden log or a close equivalent appears in the top suggestions.

Close equivalent means a suggestion would have saved the user meaningful work even if its display name is not identical. For this feature, a suggestion matches a hidden log when one of these is true: same linked memory id, same normalized display name, canonical component Jaccard similarity at least 0.67 with compatible macros, or embedding/name similarity above a threshold and macro distance within tolerance. Jaccard similarity is intersection size divided by union size for component sets.

## Research and Product Principles

This plan is informed by context-aware and next-basket recommender patterns, but it does not require the implementing agent to read external papers. The relevant ideas are embedded here.

Context should be modeled directly. Rigid meal buckets such as breakfast, lunch, and dinner should not be the source of truth. Time of day, weekday/weekend, recent session contents, source, and feedback should be numeric features in the ranking model.

Repetition matters. For a personal food logger, repeated behavior is usually the strongest signal. A simple personalized frequency model can outperform complex sequence models when repeat behavior dominates. Trai should first learn what the user repeats.

Short-term session state matters. If the user is currently logging a multi-item meal, the next suggestion should consider what usually appears with already logged session items. For example, if a user logs eggs and toast together, logging eggs should increase the score for toast.

Feedback matters. Accepted suggestions are positive feedback. Dismissed, ignored, or refined suggestions are negative feedback. Do not overreact to one dismissal, but repeated ignored/dismissed suggestions with no engagement should be suppressed.

Usefulness matters, not just probability. A latte may be frequent, but a full repeated meal can be more useful as a proactive suggestion. The ranker must prevent beverages, protein bars, and sweet snacks from crowding out complete meals unless those items are truly the best context-specific suggestion.

The app should not explain suggestions in the UI unless the product explicitly asks for explanations. Internal debug tools should explain why a suggestion appeared or failed, but user-facing rails should simply show better suggestions.

## Target Architecture

Build this as a staged architecture. Do not add persistent SwiftData models until the in-memory/domain layer proves quality and performance.

Create `Trai/Core/Services/FoodObservationBuilder.swift`. It should define:

    struct FoodObservation: Identifiable, Sendable, Equatable {
        let id: UUID
        let entryID: UUID
        let linkedMemoryID: UUID?
        let displayName: String
        let normalizedName: String
        let emoji: String?
        let kind: FoodMemoryKind
        let source: AcceptedFoodSource
        let inputMethod: FoodEntry.InputMethod
        let loggedAt: Date
        let sessionID: UUID?
        let sessionOrder: Int
        let servingText: String?
        let servingQuantity: Double?
        let servingUnit: String?
        let calories: Int
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double?
        let sugarGrams: Double?
        let components: [FoodObservationComponent]
        let wasUserEdited: Bool
        let userEditedFields: Set<String>
    }

    struct FoodObservationComponent: Identifiable, Sendable, Equatable, Hashable {
        let id: String
        let displayName: String
        let normalizedName: String
        let canonicalName: String
        let role: FoodComponentRole
        let calories: Int
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double?
        let sugarGrams: Double?
        let source: FoodComponentSource
    }

`FoodObservationBuilder` should expose:

    struct FoodObservationBuilder {
        func observations(from entries: [FoodEntry]) -> [FoodObservation]
        func observation(from entry: FoodEntry) -> FoodObservation?
    }

Only entries with `acceptedSnapshot` should become observations at first. Legacy entries without snapshots can be handled by existing backfill before evaluation. If an entry has no accepted snapshot, return nil rather than inventing a weak observation.

Create `Trai/Core/Services/FoodHabitBuilder.swift`. It should define:

    struct FoodHabit: Identifiable, Sendable, Equatable {
        let id: String
        let signature: FoodHabitSignature
        let representativeTitle: String
        let emoji: String?
        let kind: FoodMemoryKind
        let observations: [FoodObservation]
        let componentProfile: [FoodHabitComponent]
        let nutritionProfile: FoodHabitNutritionProfile
        let servingProfile: FoodHabitServingProfile?
        let timeProfile: FoodHabitTimeProfile
        let feedbackProfile: FoodHabitFeedbackProfile
        let lastObservedAt: Date
        let distinctDays: Int
        let observationCount: Int
    }

    struct FoodHabitSignature: Hashable, Sendable {
        let canonicalComponents: [String]
        let normalizedNameKey: String?
        let macroBucket: String
    }

    struct FoodHabitTimeProfile: Sendable, Equatable {
        let hourCounts: [Int]
        let weekdayCount: Int
        let weekendCount: Int
        let sessionPositionCounts: [Int: Int]
    }

The first version of `FoodHabitBuilder` should group observations primarily by canonical component signature, not by display name. The component signature should be sorted canonical component names after normalization. It should strip descriptors like grilled, roasted, white, brown, breast, thigh, bowl, plate, serving, and similar container/descriptor words. This logic belongs in `FoodNormalizationService`, not in ad hoc string manipulation inside the builder.

The habit builder should not merge everything that shares one component. It should require substantial overlap. A chicken rice habit and a chicken salad habit should stay separate because their component signatures differ. A chicken rice bowl and grilled chicken with rice should merge because the canonical components are the same or near-equivalent. Use macro bounds as guardrails: if calories or protein differ wildly and there are enough observations to know this, split the group rather than hiding meaningful differences.

Create `Trai/Core/Services/FoodRecommendationEngine.swift`. It should define:

    struct FoodRecommendationRequest: Sendable {
        let now: Date
        let targetDate: Date
        let sessionID: UUID?
        let limit: Int
        let entries: [FoodEntry]
        let memories: [FoodMemory]
    }

    struct FoodRecommendationCandidate: Sendable, Equatable {
        let habit: FoodHabit
        let source: FoodRecommendationCandidateSource
        let features: FoodRecommendationFeatures
        let suggestedEntry: SuggestedFoodEntry
    }

    enum FoodRecommendationCandidateSource: String, Sendable {
        case repeatStaple
        case timeContext
        case sessionCompletion
        case semanticVariant
        case recentRepeated
    }

    struct FoodRecommendationResult: Sendable, Equatable {
        let suggestions: [FoodSuggestion]
        let debugReport: FoodRecommendationDebugReport
    }

    struct FoodRecommendationEngine {
        func recommendations(for request: FoodRecommendationRequest) async throws -> FoodRecommendationResult
    }

The engine should be internally composed of a builder, candidate generators, a ranker, suppressors, and a mapper from `FoodHabit` to `SuggestedFoodEntry`. Keep the initial implementation synchronous unless embeddings are needed; if embeddings are used, expose async APIs and keep NaturalLanguage work off the main actor.

Create `Trai/Core/Services/FoodRecommendationEvaluator.swift`. It should support offline replay from local entries. It must not commit user food data. It should define:

    struct FoodRecommendationReplayConfig: Sendable {
        let minimumTrainingObservations: Int
        let maximumCases: Int?
        let limits: [Int]
        let includeSessionContext: Bool
    }

    struct FoodRecommendationReplayMetrics: Sendable, Equatable {
        let evaluatedCases: Int
        let hitAt1: Double
        let hitAt3: Double
        let hitAt5: Double
        let meanReciprocalRank: Double
        let oneOffFalsePositiveRate: Double
        let beverageDominationRate: Double
        let completeMealCoverageRate: Double
        let duplicateSuggestionRate: Double
    }

    struct FoodRecommendationEvaluator {
        func evaluate(entries: [FoodEntry], memories: [FoodMemory], config: FoodRecommendationReplayConfig) async throws -> FoodRecommendationReplayMetrics
    }

Replay should sort observations chronologically. For each observation after enough training data exists, build recommendations from only earlier entries, then compare the top suggestions to the hidden observation. This is crucial: the evaluator must not allow future logs to influence past recommendations.

## Plan of Work

Milestone 1 creates the evaluator and diagnostics first. This is the main safety harness. Implement it against the current `FoodSuggestionService` before the new engine exists. The output should establish a baseline, even if the baseline is bad. This milestone must also add synthetic replay fixtures that demonstrate the known failure: a repeated chicken/rice habit is fragmented while a one-off restaurant sandwich is recent.

Milestone 2 creates the observation and habit domain layer. This layer should be testable without SwiftData persistence. It should convert existing entries into observations, normalize components, and build habits that represent repeated patterns. It should prove that chicken/rice variants cluster and chicken salad stays separate.

Milestone 3 adds candidate generators. Each generator should be independently testable. Repeat-staple candidates come from high-frequency habits. Time-context candidates use hour-window support. Session-completion candidates use co-occurrence within session ids and session order. Semantic-variant candidates use embedding/name similarity as support, not as the only signal. Recent-repeated candidates allow a recently repeated item only if it appears on multiple days or has explicit positive feedback.

Milestone 4 adds the deterministic ranker and suppressors. This ranker should combine likelihood and usefulness. It should prefer repeated complete meals over one-off restaurant items and over low-utility beverages unless the context strongly supports the beverage. Suppressors should remove already-logged-today items, repeated ignored/dismissed items, stale low-evidence habits, and exact duplicates.

Milestone 5 wires the new engine into `FoodSuggestionService`. Keep the old path as a private comparator or debug-only fallback while the new engine stabilizes. The public API of `FoodSuggestionService.cameraSuggestions(...)` should continue returning `[FoodSuggestion]` so UI code does not need a broad rewrite.

Milestone 6 adds real-device evaluation. Extend the armed local-device tests in `TraiTests/FoodEmbeddingServiceTests.swift` or create a new `TraiTests/FoodRecommendationDeviceDebugTests.swift` if the scheme supports it. The test should print baseline-vs-new metrics and top suggestions at breakfast, lunch, snack, dinner, and late-night target times. It should be skipped unless armed by a marker file or environment variable. It must not write private food data into the repo.

Milestone 7 cleans up legacy concepts. Once the new engine passes synthetic tests and improves real-data replay metrics, remove or reduce meal-bucket-driven suggestion rules. Keep fields like `mealTimeBucket` only where needed for decoding existing snapshots. Do not expose food buckets as product concepts.

Milestone 8 validates and prepares review. Run focused tests, broader food-memory tests, a build for simulator, and, when possible, the armed device replay. Document metrics in this plan's `Outcomes & Retrospective`.

## Concrete Steps

Start in the repository root:

    cd /Users/nadav/Desktop/Trai
    git status --short

If there are unrelated local changes, do not revert them. Work on a new branch or worktree if the current tree is risky:

    git switch -c codex/rebuild-food-recommendations

If the branch already exists, use a new branch with a distinct suffix. Do not use destructive commands such as `git reset --hard`.

Before editing, run the current focused food-memory tests to understand the baseline:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=343702CB-BE8E-4A8C-BA86-67898FFCDD7C' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationBaseline.xcresult -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodMemoryMatcherTests test

If the simulator id is unavailable, list devices with:

    xcrun simctl list devices available

Then substitute any bootable iOS simulator id. If simulator NaturalLanguage embedding tests skip because the embedding model cannot load, that is acceptable only for the live embedding tests. Ranking, habit, and evaluator tests must pass.

For each milestone, write the tests first and confirm they fail for the expected reason. Then implement the code, rerun the milestone tests, and commit when they pass. Keep this plan updated after each milestone.

## Milestone 1: Baseline Replay Evaluation and Debug Reports

At the end of this milestone, the repo has an evaluator that can run the existing suggestion service against historical observations and report concrete metrics. This milestone does not change user-facing suggestions.

Tests to write first:

In `TraiTests/FoodRecommendationEvaluatorTests.swift`, add `FoodRecommendationEvaluatorTests` with these tests:

- `testReplayEvaluatorHidesFutureObservations`: create five dated `FoodEntry` rows with accepted snapshots. Use a spy recommender or debug hook that records the training entries passed to each replay case. Assert that when the hidden observation is on day N, no entries from day N or later are included in the training set.
- `testReplayEvaluatorCountsCanonicalComponentHit`: create training entries for chicken/rice and a hidden entry named "Grilled Chicken With Rice." Make a suggestion named "Chicken Rice Bowl" with canonical components chicken and rice. Assert Hit@1 is 1.0 even though display names differ.
- `testReplayEvaluatorRejectsOneOffFalsePositive`: create a one-off Katz pastrami suggestion when the hidden entry is chicken/rice. Assert this is not counted as a hit and increments or contributes to the false-positive diagnostic.
- `testReplayMetricsIncludeUsefulnessDiagnostics`: build a case where all top suggestions are beverages while a complete meal is hidden. Assert `beverageDominationRate` is greater than zero and `completeMealCoverageRate` is zero.

Implementation details:

Create `Trai/Core/Services/FoodRecommendationEvaluator.swift`. It can initially accept a closure for generating recommendations so it can evaluate the current `FoodSuggestionService` and later the new engine. The first API can be:

    struct FoodRecommendationReplayRunner {
        typealias RecommendationProvider = @MainActor (_ trainingEntries: [FoodEntry], _ memories: [FoodMemory], _ now: Date, _ limit: Int) async throws -> [FoodSuggestion]
        func evaluate(observations: [FoodObservation], entries: [FoodEntry], memories: [FoodMemory], provider: RecommendationProvider, config: FoodRecommendationReplayConfig) async throws -> FoodRecommendationReplayMetrics
    }

If `FoodObservation` does not exist yet, create the minimal private version in the test file or evaluator and replace it in Milestone 2. Prefer adding the public observation type in Milestone 2, but do not block Milestone 1 if the evaluator can be written in a minimal way.

The evaluator should output a debug report that includes failed cases. Each failed case should include target date, hidden display name, hidden canonical components, top suggestion titles, top suggestion canonical components, and miss reason. The report should be local in memory or printed in tests; do not write private data to tracked files.

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationEvaluatorTests.xcresult -only-testing:TraiTests/FoodRecommendationEvaluatorTests test

Expect the new evaluator tests to fail before implementation because the types do not exist. After implementation, expect all `FoodRecommendationEvaluatorTests` to pass.

Commit:

    git add Trai/Core/Services/FoodRecommendationEvaluator.swift TraiTests/FoodRecommendationEvaluatorTests.swift .agent/execplan-pending.md
    git commit -m "Milestone 1: Add food recommendation replay evaluator"

## Milestone 2: Observation and Habit Domain Layer

At the end of this milestone, accepted food entries can be converted into normalized observations and grouped into habits. The new code should not persist new models yet.

Tests to write first:

In `TraiTests/FoodRecommendationHabitTests.swift`, add:

- `testObservationBuilderUsesAcceptedSnapshotAsSourceOfTruth`: create a `FoodEntry` whose parent name differs from the accepted snapshot display name. Assert the observation uses the accepted snapshot's display name, components, macros, source, edit fields, and logged date.
- `testObservationBuilderSkipsEntriesWithoutAcceptedSnapshot`: create an entry with no accepted snapshot and assert it produces no observation.
- `testHabitBuilderClustersChickenRiceVariants`: create observations for "Chicken Rice Bowl", "Roasted Chicken Breast With Rice", and "Grilled Chicken With Brown Rice". Assert one habit is produced with canonical components `chicken` and `rice`, observation count 3, distinct days 3, and a representative title of either the most common accepted title or the most recent common title.
- `testHabitBuilderDoesNotMergeChickenRiceAndChickenSalad`: create repeated chicken/rice and chicken/salad observations. Assert two habits.
- `testHabitBuilderSplitsWildlyDifferentMacroProfiles`: create same component names with one profile around 500 calories and another around 1200 calories, with enough observations on each side. Assert they are split or flagged as unstable according to the implementation decision.

Implementation details:

Create `Trai/Core/Services/FoodObservationBuilder.swift` and `Trai/Core/Services/FoodHabitBuilder.swift`. Reuse `FoodNormalizationService` for canonical names. If needed, extend `FoodNormalizationService` with:

    func normalizeComponentName(_ name: String) -> String
    func canonicalComponentSignature(for components: [AcceptedFoodComponent]) -> [String]

Avoid local string splitting outside `FoodNormalizationService` unless there is no helper yet. The point is to centralize normalization so future fixes apply everywhere.

The habit builder should derive:

- `observationCount`
- `distinctDays`
- `lastObservedAt`
- median calories/protein/carbs/fat
- lower/upper macro bounds
- component observation counts and median component macros
- hour counts across 24 hours
- weekday/weekend counts
- session position counts, where session position is `FoodEntry.sessionOrder`

Habit ids should be deterministic. Use a stable string like `components:<component1>|<component2>|macro:<bucket>`. Do not use random UUIDs for derived habits, because deterministic ids make tests and feedback mapping easier.

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationHabitTests.xcresult -only-testing:TraiTests/FoodRecommendationHabitTests test

Expected result after implementation: all habit tests pass.

Commit:

    git add Trai/Core/Services/FoodObservationBuilder.swift Trai/Core/Services/FoodHabitBuilder.swift Trai/Core/Services/FoodNormalizationService.swift TraiTests/FoodRecommendationHabitTests.swift .agent/execplan-pending.md
    git commit -m "Milestone 2: Build observations and learned food habits"

## Milestone 3: Candidate Generators

At the end of this milestone, the system can produce multiple candidate types from habits before ranking them. This makes the recommendation logic easier to test than one monolithic function.

Tests to write first:

In `TraiTests/FoodRecommendationCandidateTests.swift`, add:

- `testRepeatStapleGeneratorRequiresMultipleDays`: a habit observed three times on three days is generated; a one-off habit is not generated.
- `testTimeContextGeneratorUsesContinuousHourWindow`: a habit observed around 12:00 is generated at 12:30 and weak or absent at 23:00. Do not use breakfast/lunch/dinner buckets as the deciding factor.
- `testSessionCompletionGeneratorUsesCurrentSessionAnchors`: if historical sessions often contain chicken plus rice and the current session contains chicken, rice is proposed or the combined habit is boosted.
- `testSemanticVariantGeneratorUsesEmbeddingAsSupportNotSoleSignal`: similar names with incompatible components or macros do not become candidates solely because embeddings are close. If live embeddings are unavailable, use deterministic injected embedding vectors.
- `testRecentRepeatedGeneratorRejectsSingleRecentObservation`: one recent Katz log is not generated, but an item repeated on two days can be generated.

Implementation details:

Create `Trai/Core/Services/FoodRecommendationCandidateGenerators.swift`. Define a protocol only if it reduces duplication; otherwise simple structs are fine:

    protocol FoodRecommendationCandidateGenerating {
        func candidates(habits: [FoodHabit], context: FoodRecommendationContext) async throws -> [FoodRecommendationCandidate]
    }

Candidate generators should produce unranked candidates with source labels and raw feature values. Do not suppress or cap families here unless it is source-specific. Final suppression and family caps belong in the ranker/selection stage.

Define `FoodRecommendationContext` in `FoodRecommendationEngine.swift` or a separate file. It should include target date, current session observations, today observations, recent observations, and optional memory lookup. It should be built from entries once and passed around.

For time support, use weighted hour windows. A suggested default:

- current hour weight 1.0
- ±1 hour weight 0.75
- ±2 hours weight 0.45
- ±3 hours weight 0.20

Normalize by total observations for that habit. This is continuous time support; do not map to meal buckets.

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationCandidateTests.xcresult -only-testing:TraiTests/FoodRecommendationCandidateTests test

Commit:

    git add Trai/Core/Services/FoodRecommendationCandidateGenerators.swift Trai/Core/Services/FoodRecommendationEngine.swift TraiTests/FoodRecommendationCandidateTests.swift .agent/execplan-pending.md
    git commit -m "Milestone 3: Add food recommendation candidate generators"

## Milestone 4: Ranking, Suppression, and Suggested Entry Construction

At the end of this milestone, candidates are ranked into useful suggestions, not merely likely suggestions. This is the milestone that should make the Katz-vs-chicken/rice failure impossible in tests.

Tests to write first:

In `TraiTests/FoodRecommendationRankerTests.swift`, add:

- `testRankerPrefersRepeatedCompleteMealOverRecentOneOff`: repeated chicken/rice across several days beats a single recent Katz pastrami sandwich.
- `testRankerCapsBeverageDominance`: if multiple beverages and complete meals are candidates, at most one beverage appears in top 3 unless no complete meals are eligible.
- `testRankerSuppressesAlreadyLoggedToday`: if a habit has already been logged today and the repeat profile does not support multiple same-day uses, it is absent.
- `testRankerAllowsLegitimateSameDayRepeats`: if historical data shows the user often logs the same protein shake twice per day with a reasonable gap, it can appear again after the gap.
- `testRankerSuppressesRepeatedlyIgnoredSuggestion`: repeated shown-but-not-engaged suggestions are suppressed for a cooldown period.
- `testRankerDeduplicatesEquivalentHabits`: chicken/rice variants do not occupy multiple top slots.
- `testSuggestedEntryUsesMedianAcceptedMacrosAndCommonComponents`: generated `SuggestedFoodEntry` uses habit medians and common components, not arbitrary latest values.

Implementation details:

Create `Trai/Core/Services/FoodRecommendationRanker.swift`. Define:

    struct FoodRecommendationFeatures: Sendable, Equatable {
        let decayedFrequency: Double
        let distinctDayScore: Double
        let recencyScore: Double
        let hourSupport: Double
        let dayTypeSupport: Double
        let sessionSupport: Double
        let componentStability: Double
        let macroStability: Double
        let positiveFeedback: Double
        let negativeFeedbackPenalty: Double
        let usefulnessScore: Double
        let sourceBoost: Double
    }

    struct FoodRecommendationRanker {
        func rank(_ candidates: [FoodRecommendationCandidate], context: FoodRecommendationContext) -> [FoodRecommendationCandidate]
    }

The initial scoring formula should be deterministic and easy to tune. Start with:

    score =
      0.18 * decayedFrequency +
      0.14 * distinctDayScore +
      0.10 * recencyScore +
      0.18 * hourSupport +
      0.06 * dayTypeSupport +
      0.12 * sessionSupport +
      0.08 * componentStability +
      0.06 * macroStability +
      0.12 * usefulnessScore +
      0.06 * positiveFeedback +
      sourceBoost -
      negativeFeedbackPenalty

Normalize every feature to 0...1 before scoring. Clamp the final score to a reasonable range for debug output. This exact formula can change if tests and replay metrics show a better weighting, but update this plan's Decision Log if it changes.

Usefulness family rules:

- Complete meal: high usefulness. A complete meal has protein plus carb/vegetable/fruit/mixed base, or calories at least 450 with multiple meaningful components.
- Staple protein/carb meal: high usefulness even if calories are under 450.
- Produce: medium usefulness.
- Protein bar: medium-low usefulness unless repeated strongly in context.
- Beverage: low usefulness unless it has strong repeat evidence in that time window or enough protein/calories to be meal-like.
- Sweet treat: low usefulness unless repeated strongly and not crowding out meals.

Suppression rules:

- Single observation proactive suggestions are suppressed unless explicitly pinned later. Do not add pinning in this milestone unless already present.
- Stale low-evidence habits are suppressed. Suggested default: if distinct days < 3 and last observed more than 30 days ago, suppress.
- Already logged today is suppressed unless repeat profile supports same-day repeats and enough time has passed since last log.
- Repeated ignored/dismissed without engagement is suppressed for at least 12 hours, longer if dismissals accumulate.
- Do not show duplicate component signatures in the same rail.

Suggested entries should be generated from `FoodHabit`, not `FoodMemory`. Use median macros and common serving text. Components should come from the habit component profile. Preserve useful display names by choosing the most common accepted display name, with a recency tie-break.

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationRankerTests.xcresult -only-testing:TraiTests/FoodRecommendationRankerTests test

Commit:

    git add Trai/Core/Services/FoodRecommendationRanker.swift Trai/Core/Services/FoodRecommendationEngine.swift TraiTests/FoodRecommendationRankerTests.swift .agent/execplan-pending.md
    git commit -m "Milestone 4: Rank food habits into useful suggestions"

## Milestone 5: Replace the User-Facing Suggestion Path

At the end of this milestone, `FoodSuggestionService.cameraSuggestions(...)` uses the new engine by default while the old path remains available only for debug comparison during this rollout.

Tests to write first:

Update `TraiTests/FoodMemoryServiceTests.swift` or create `TraiTests/FoodSuggestionIntegrationTests.swift` with:

- `testCameraSuggestionsUseHabitEngineForFragmentedStaples`: build several accepted entries with fragmented memories and assert `FoodSuggestionService.cameraSuggestions` returns the repeated staple.
- `testCameraSuggestionsDoNotRequireFoodMemoryObservationCounts`: create entries whose linked memories each have observation count 1, but whose observations form a repeated habit. Assert suggestions still appear.
- `testCameraSuggestionsPreserveExistingOutcomeRecording`: shown suggestion ids can still be recorded as accepted/dismissed/tapped/refined without crashing. If habit ids are not UUIDs, map the suggestion to a representative memory id for compatibility or introduce a stable suggestion outcome key.
- `testDebugCameraSuggestionsReportsNewEngineStages`: debug summary should include habit count, candidate count by source, suppression counts, final shown titles, and old-vs-new comparison when enabled.

Implementation details:

Modify `Trai/Core/Services/FoodSuggestionService.swift`. Keep the public API:

    @MainActor
    func cameraSuggestions(limit: Int, now: Date = .now, targetDate: Date? = nil, sessionId: UUID? = nil, modelContext: ModelContext) throws -> [FoodSuggestion]

Because the new engine may need embeddings, decide whether this API should remain synchronous. The safest transition is:

1. Keep the existing synchronous API for UI compatibility.
2. Add an async API:

       @MainActor
       func cameraSuggestionsWithHabits(limit: Int, now: Date = .now, targetDate: Date? = nil, sessionId: UUID? = nil, modelContext: ModelContext) async throws -> [FoodSuggestion]

3. Make the synchronous API call a no-embedding deterministic engine path.
4. Use the async API from save/maintenance/debug paths where embeddings are desired.

If adding async to UI call sites is straightforward and improves correctness, do it, but do not block the milestone on broad UI refactoring.

`FoodSuggestion` currently requires `memoryID: UUID`. Habits have deterministic string ids. For compatibility, choose a representative memory id when available. If no memory exists, create a deterministic UUID from the habit id using UUID v5-like hashing or add a new field to `FoodSuggestion` while preserving `id`. Prefer the smallest compatibility-preserving change that keeps `recordOutcome` working.

Update `debugCameraSuggestions(...)` to return richer diagnostics. If changing `FoodSuggestionDebugSummary`, update all tests that construct or assert it. Include:

- total observations
- habit count
- candidate count by source
- suppressed one-off count
- suppressed already-today count
- suppressed negative-feedback count
- suppressed low-usefulness count
- final shown titles

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodSuggestionIntegrationTests.xcresult -only-testing:TraiTests/FoodSuggestionIntegrationTests -only-testing:TraiTests/FoodMemoryModelStorageTests/testCameraSuggestionsAggregateFragmentedStaplesFromAcceptedSnapshots -only-testing:TraiTests/FoodMemoryModelStorageTests/testCameraSuggestionsPreferRepeatedStapleOverRecentOneOff test

Then run the broader food-memory tests:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodMemoryClassesAfterEngine.xcresult -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodMemoryMatcherTests test

Commit:

    git add Trai/Core/Services/FoodSuggestionService.swift Trai/Core/Services/FoodRecommendationEngine.swift TraiTests/FoodSuggestionIntegrationTests.swift TraiTests/FoodMemoryServiceTests.swift .agent/execplan-pending.md
    git commit -m "Milestone 5: Use habit engine for camera food suggestions"

## Milestone 6: Real-Device Replay and Debug Workflow

At the end of this milestone, an agent can run an armed test on Nadav's iPhone or a local dev install and get privacy-preserving metrics showing whether the new engine improves suggestions on real history.

Tests and debug workflow to add:

In `TraiTests/FoodEmbeddingServiceTests.swift` or a new `TraiTests/FoodRecommendationDeviceDebugTests.swift`, add an armed test:

    @MainActor
    func testLocalDeviceFoodRecommendationReplayWhenArmed() async throws

The test should skip unless one of these is true:

- `TRAI_DEBUG_FOOD_RECOMMENDATION_REPLAY=1` is visible in `ProcessInfo.processInfo.environment`, or
- a marker file named `debug-food-recommendation-replay.txt` exists in the app Documents directory, or
- the test is running on a physical device and the test is explicitly selected by `-only-testing`.

Environment variables sometimes do not propagate to physical device XCTest runs. Therefore, for physical devices, allow the selected test to run without requiring an environment variable, but keep simulator runs guarded. This mirrors the existing maintenance-test lesson.

The output should print aggregate metrics only, plus top titles and reason codes. Do not print full private histories. Example output:

    Food recommendation replay:
    observations=452 habits=74 cases=180
    oldHitAt3=0.21 newHitAt3=0.43 oldMRR=0.12 newMRR=0.28
    oneOffFalsePositiveRate=0.03 beverageDominationRate=0.08 completeMealCoverageRate=0.61
    breakfast_08 shown=Low-fat Latte | Greek Yogurt Bowl | Eggs and Toast
    lunch_12 shown=Chicken Rice Bowl | Turkey Sandwich | Barebells Protein Bar
    dinner_19 shown=Chicken Rice Bowl | Salmon Rice Bowl | Steak and Potatoes

The exact titles will depend on the user's data. The important part is that the test prints enough to compare before and after. If the new metrics do not beat old metrics, do not force the milestone closed; update the plan with the failure and iterate on candidate generation/ranking.

Recommended physical-device command:

    TRAI_DEBUG_FOOD_RECOMMENDATION_REPLAY=1 xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS,id=00008150-000445911140401C' -derivedDataPath /private/tmp/TraiFoodRecommendationDevice -resultBundlePath /private/tmp/TraiFoodRecommendationReplayDevice.xcresult -only-testing:TraiTests/FoodRecommendationDeviceDebugTests/testLocalDeviceFoodRecommendationReplayWhenArmed test

If the output says `Unlock Nadav's iPhone to Continue`, the build may have succeeded but the test did not execute. Do not claim real-device test execution until the test case starts and prints metrics.

Acceptance criteria for real data:

- The test executes on device or a dev install with local history.
- It prints observation count, habit count, replay case count, hit metrics, and top suggestions for several times of day.
- New Hit@3 is greater than old/current Hit@3 by at least 20 percent relative, or the absolute new Hit@3 is at least 0.35 for histories with at least 100 observations. If these thresholds are unrealistic after inspection, update the Decision Log with why and choose a defensible threshold.
- One-off false-positive rate is below 0.05.
- Beverage domination rate is below 0.25 for top-3 suggestions when complete-meal habits exist.
- Manual spot-check of printed top suggestions shows repeated complete meals or staples appearing at lunch/dinner if the user's history contains them.

Commit:

    git add TraiTests/FoodRecommendationDeviceDebugTests.swift TraiTests/FoodEmbeddingServiceTests.swift Trai/Core/Services/FoodRecommendationEvaluator.swift .agent/execplan-pending.md
    git commit -m "Milestone 6: Add real-device food recommendation replay"

## Milestone 7: Retire or Reduce Legacy Suggestion Concepts

At the end of this milestone, the code no longer depends on meal buckets or memory row eligibility for proactive suggestions. Compatibility fields can remain for decoding and older features.

Tests to write first:

Add or update tests:

- `testMealBucketDoesNotControlRecommendationEligibility`: two habits with identical hour distributions but different legacy meal bucket strings rank the same.
- `testFoodKindMismatchDoesNotBlockHabitSuggestion`: if accepted observations form a repeated habit, `FoodMemoryKind.food` vs `.meal` on representative memories does not prevent suggestion.
- `testLegacyAcceptedSnapshotStillDecodes`: existing snapshot payloads with `mealTimeBucket` still decode.
- `testMemoryResolutionStillRunsAfterSuggestionEngineSwitch`: saving an entry still sets accepted snapshot and queues/resolves memory as before, even though suggestions no longer depend on memory rows.

Implementation details:

Review these files:

- `Trai/Core/Services/FoodSuggestionService.swift`
- `Trai/Core/Services/FoodMemoryService.swift`
- `Trai/Core/Services/FoodMemoryIndex.swift`
- `Trai/Core/Services/FoodMemoryMatcher.swift`
- `Trai/Core/Models/FoodMemoryTypes.swift`

Remove meal-bucket-driven scoring or eligibility from suggestions. Keep `mealTimeBucket` in `AcceptedFoodSnapshot` decoding so old snapshots do not break. Keep memory matching if other parts of the app need it for consolidation, analytics, or outcome recording.

Do not delete `FoodMemory` unless a separate migration plan exists. For this plan, `FoodMemory` can remain as a cache/resolution layer and developer-inspection artifact.

Verification:

Run:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationPlan -resultBundlePath /private/tmp/TraiFoodRecommendationLegacyCleanup.xcresult -only-testing:TraiTests/FoodMemoryFoundationTests -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodRecommendationHabitTests -only-testing:TraiTests/FoodRecommendationRankerTests test

Commit:

    git add Trai/Core/Services Trai/Core/Models TraiTests .agent/execplan-pending.md
    git commit -m "Milestone 7: Remove legacy bucket dependence from food suggestions"

## Milestone 8: Final Validation and Review Readiness

At the end of this milestone, the branch is ready for review with objective evidence.

Run formatting and whitespace checks:

    git diff --check

Run focused food recommendation tests:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationFinal -resultBundlePath /private/tmp/TraiFoodRecommendationFinalFocused.xcresult -only-testing:TraiTests/FoodRecommendationEvaluatorTests -only-testing:TraiTests/FoodRecommendationHabitTests -only-testing:TraiTests/FoodRecommendationCandidateTests -only-testing:TraiTests/FoodRecommendationRankerTests -only-testing:TraiTests/FoodSuggestionIntegrationTests test

Run broader food memory and foundation tests:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -derivedDataPath /private/tmp/TraiFoodRecommendationFinal -resultBundlePath /private/tmp/TraiFoodRecommendationFinalFoodMemory.xcresult -only-testing:TraiTests/FoodMemoryFoundationTests -only-testing:TraiTests/FoodMemoryModelStorageTests -only-testing:TraiTests/FoodMemoryMatcherTests test

Run a compile/build check:

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/TraiFoodRecommendationFinalBuild CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

If a physical iPhone is available and unlocked, run the real-device replay test from Milestone 6. Record the output summary in this plan's `Outcomes & Retrospective`. If the phone is locked and the command stops at preflight, record that the device build reached launch but real-device XCTest did not execute.

Acceptance for the full plan:

- Synthetic tests prove repeated staples outrank one-offs.
- Synthetic tests prove beverages/protein bars cannot dominate complete meals unless no complete meals qualify.
- Replay evaluator proves the new engine can be measured without future leakage.
- Real-device or local persistent-history debug prints better new metrics than old/current metrics, or the plan records why metrics are not yet acceptable and continues iteration.
- `FoodSuggestionService.cameraSuggestions(...)` returns useful suggestions from learned habits while preserving existing UI call sites.
- Existing save flows still create accepted snapshots and do not crash.
- Existing food-memory matching tests still pass or are intentionally updated with rationale.

Commit final validation updates:

    git add .agent/execplan-pending.md
    git commit -m "Milestone 8: Document food recommendation validation"

## Validation and Acceptance

The strongest acceptance criterion is replay quality. The implementing agent should not declare this complete merely because tests compile. The feature is complete when both deterministic tests and real/local replay diagnostics show that suggestions are more useful.

Minimum deterministic acceptance:

- `FoodRecommendationEvaluatorTests` pass.
- `FoodRecommendationHabitTests` pass.
- `FoodRecommendationCandidateTests` pass.
- `FoodRecommendationRankerTests` pass.
- `FoodSuggestionIntegrationTests` pass.
- Existing `FoodMemoryFoundationTests`, `FoodMemoryModelStorageTests`, and `FoodMemoryMatcherTests` pass, except live embedding tests may skip when NaturalLanguage assets are unavailable.

Minimum behavioral acceptance:

- Repeated chicken/rice-like observations produce a chicken/rice suggestion even when names and memory rows are fragmented.
- A single Katz pastrami observation does not appear proactively.
- A user with frequent beverages still sees complete meals when complete meals have meaningful evidence.
- Already-logged-today foods are suppressed unless historical same-day repeat behavior supports them.
- Session context can promote co-logged foods without showing irrelevant extras after the session is likely complete.

Minimum real-data acceptance:

- Device/local replay prints observation count, habit count, case count, hit metrics, and family diagnostics.
- New top suggestions at lunch/dinner are not beverage-only when repeated complete meals exist.
- New Hit@3 improves over old/current Hit@3 or the agent documents a concrete reason and continues iteration.

## Idempotence and Recovery

All milestones are additive until Milestone 7. If a milestone fails, leave existing user-facing suggestions untouched and continue using the old `FoodSuggestionService` path. Do not delete `FoodMemory` or remove decoding fields until tests prove the new engine is stable.

The evaluator should never write private real food data into tracked files. Real-device debug tests may print aggregate titles and metrics to the test log. If an export script is added, it should write to `/private/tmp` by default and anonymize or aggregate data unless the user explicitly requests otherwise.

If SwiftData model changes become necessary, stop and update this ExecPlan with a migration strategy before implementing them. The preferred first implementation uses derived in-memory structs from existing `FoodEntry` rows and accepted snapshots.

If device tests block on `Unlock Nadav's iPhone to Continue`, record that the test did not execute. Do not mark real-device validation complete based on build output alone.

If simulator embedding tests skip because NaturalLanguage assets are unavailable, proceed only if deterministic ranking/evaluator tests pass and a physical-device or deterministic embedding substitute covers the relevant behavior.

## Artifacts and Notes

Prior useful evidence from this thread:

    Local device food memory maintenance:
    backfilled=0 resolved=0 totalEntries=452 tracked=452 legacy=0 memories=363 matched=82 candidates=370

    Post-maintenance suggestions before the aggregate/rebuild direction:
    breakfast_08 shown=Low-fat Latte | Low-fat Iced Latte
    lunch_12 shown=Cappuccino | Barebells Protein Bar | Low-fat Iced Latte
    snack_15 shown=Watermelon | Cappuccino | Low-fat Iced Latte
    dinner_19 shown=Latte
    late_22 shown=Latte

This evidence should shape validation. A good rebuild should reduce fragmentation sensitivity and should not produce beverage-only dinner suggestions if the user has repeated complete meal observations.

Suggested debug output format for candidate ranking:

    Food recommendation candidate:
    title=Chicken Rice Bowl source=repeatStaple score=0.78 frequency=0.86 distinctDays=0.80 hour=0.64 session=0.10 usefulness=1.00 suppressed=false

    Food recommendation suppressed:
    title=Katz's Pastrami Sandwich reason=singleObservation observationCount=1 distinctDays=1 lastObserved=2026-04-20

Keep debug output behind tests or developer settings. Do not show these explanations in the production suggestion rail.

## Interfaces and Dependencies

Use Swift and existing project types. Do not add third-party packages for the first implementation.

Use these existing dependencies:

- SwiftData `ModelContext` and `FetchDescriptor` for reading `FoodEntry` and `FoodMemory`.
- Existing `AcceptedFoodSnapshot`, `AcceptedFoodComponent`, `SuggestedFoodEntry`, and `SuggestedFoodComponent` types from `Trai/Core/Models/FoodMemoryTypes.swift` and `Trai/Core/Services/AITypes.swift`.
- Existing `FoodNormalizationService` for name/component normalization. Extend it if needed.
- Existing `NLFoodEmbeddingService.shared` and `FoodEmbeddingMath` only as optional support. The deterministic engine must work without live embedding assets.
- Existing Xcode scheme `Trai` and XCTest target `TraiTests`.

At the end of the plan, these public or internal interfaces should exist:

    struct FoodObservationBuilder {
        func observations(from entries: [FoodEntry]) -> [FoodObservation]
        func observation(from entry: FoodEntry) -> FoodObservation?
    }

    struct FoodHabitBuilder {
        func habits(from observations: [FoodObservation], memories: [FoodMemory]) -> [FoodHabit]
    }

    struct FoodRecommendationEngine {
        func recommendations(for request: FoodRecommendationRequest) async throws -> FoodRecommendationResult
    }

    struct FoodRecommendationEvaluator {
        func evaluate(entries: [FoodEntry], memories: [FoodMemory], config: FoodRecommendationReplayConfig) async throws -> FoodRecommendationReplayMetrics
    }

    struct FoodRecommendationRanker {
        func rank(_ candidates: [FoodRecommendationCandidate], context: FoodRecommendationContext) -> [FoodRecommendationCandidate]
    }

The existing API should continue to work:

    @MainActor
    func cameraSuggestions(limit: Int, now: Date, targetDate: Date?, sessionId: UUID?, modelContext: ModelContext) throws -> [FoodSuggestion]

If an async replacement becomes the primary path, preserve a compatibility wrapper or update all call sites in one milestone with tests.

## Revision Notes

2026-05-05 / Codex: Initial ExecPlan created from the product goal of rebuilding proactive food suggestions so they predict what the user would actually log. The plan intentionally starts with replay evaluation and in-memory domain types to avoid a risky persistence migration before quality is proven.
