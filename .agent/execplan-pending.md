# Rebuild Food Suggestions Around Learned Food Patterns

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This plan follows `.agent/PLANS.md` in this repository. If this plan is revised, keep it self-contained: a future coding agent should be able to read only this file and implement the feature without prior conversation context.

## Purpose / Big Picture

Trai should suggest foods that feel like personal shortcuts for what the user would actually log, even when the AI names the same food differently across days. The current implementation moved in the right direction by deriving suggestions from accepted food observations, but it still carries old concepts such as food memory kind, beverage/snack/complete-meal special cases, a "semantic variant" generator, and one-off recent meal fallbacks. Those concepts make the system harder to reason about and can surface suggestions that are technically derived from history but do not feel like real user habits.

After this work, the food suggestion rail should behave like a personal food autocomplete. It should show compact suggestions such as "Chicken curry + rice" or "Greek yogurt" because the user repeatedly accepted similar logs before, not because the app placed foods into hardcoded meal buckets or composed new meals. A suggestion must always trace back to accepted user history. Embeddings should be used only to decide whether two accepted historical logs are basically the same food pattern despite naming drift. Embeddings must not be used to invent foods.

The visible user experience should be simple: when the user opens the food camera or food logging surface, Trai quietly offers a few high-confidence foods or meal continuations. The user taps one to log it, edits it if needed, or ignores/dismisses it. The app learns from that behavior without exposing labels such as habit, semantic variant, beverage, snack, complete meal, pattern, or recommendation source in the normal UI.

The implementation must prove that it works. The agent must add tests that fail against the old behavior, add an offline replay evaluator that compares the new pattern recommender to the current build using historical accepted logs, and run local/private device replay without committing real user food history. The work is not complete until the new system shows better suggestion quality than the current engine on synthetic tests and real-history replay slices.

## Progress

- [x] (2026-05-06 14:40Z) Authored this ExecPlan and saved it at `.agent/execplan-pending.md`.
- [ ] Milestone 1: Add failing tests that define the desired pattern recommender behavior and expose the current hardcoded/special-case leakage.
- [ ] Milestone 2: Add the `FoodPattern` domain layer and identity scoring without wiring it to the UI.
- [ ] Milestone 3: Add embedding-backed identity resolution for accepted observations, with deterministic fallback when NaturalLanguage embeddings are unavailable.
- [ ] Milestone 4: Replace current candidate generators with a single pattern-based recommendation engine.
- [ ] Milestone 5: Wire the pattern recommender into `FoodSuggestionService` and remove materialization of synthetic memories before user acceptance.
- [ ] Milestone 6: Retire old recommendation abstractions and remove hardcoded beverage/snack/complete-meal logic from the proactive suggestion path.
- [ ] Milestone 7: Expand replay comparison so the agent can prove improvement over the current engine on real accepted-history data without committing private data.
- [ ] Milestone 8: Run focused tests, build, device replay, and document the final quality results.

## Surprises & Discoveries

- Observation: The current visible suggestion path is already based on accepted observations, but it still emits suggestions through `FoodHabit` and `FoodMemoryKind`, and still computes `mealKind` on `SuggestedFoodEntry`.
  Evidence: `Trai/Core/Services/FoodHabitBuilder.swift` defines `FoodHabit.kind`, and `Trai/Core/Services/FoodRecommendationCandidateGenerators.swift` maps `mealKind: habit.kind.rawValue`.

- Observation: There are no hardcoded meal suggestions such as chicken/rice, curry, Katz, or pastrami in the recommendation code, but there are hardcoded food category heuristics.
  Evidence: `FoodRecommendationSpecialCases.isRecentMorningBeverageRepeat`, `FoodRecommendationSpecialCases.isCompleteMeal`, `FoodRecommendationFeatureBuilder.usefulnessScore`, and `FoodRecommendationRanker.isLowUtilityBeverage` check strings such as `latte`, `coffee`, `cappuccino`, and `protein bar`.

- Observation: The current `RecentCompleteMealFoodCandidateGenerator` can allow one-off recent complete meals when no repeated complete-meal habit exists.
  Evidence: It checks for absence of repeated complete meals, then emits any recent complete meal passing `FoodRecommendationSpecialCases.isRecentCompleteMeal`, which does not require `distinctDays >= 2`.

- Observation: Previous real-device replay showed the current path became more conservative and reduced beverage/duplicate issues, but did not improve Hit@1/3/5 or MRR over legacy.
  Evidence: A prior 20-case local device replay reported Hit@1/3/5 and MRR tied at `0.100`, beverage domination improved from `0.100` to `0.050`, duplicate suggestions improved from `0.100` to `0.000`, and noSuggestions rose to `0.550`.

## Decision Log

- Decision: Replace the user-facing recommendation abstraction with `FoodPattern`, not another candidate generator.
  Rationale: The core product problem is identity resolution across AI naming drift. A user-specific learned pattern is the right abstraction because it groups accepted observations that are actually the same reusable food for this user. Additional special-case generators would continue the current non-convergent design.
  Date/Author: 2026-05-06 / Codex

- Decision: Remove food-kind, beverage, snack, and complete-meal concepts from proactive recommendation eligibility and ranking.
  Rationale: These concepts were introduced as patches to suppress low-value suggestions, but they leak implementation detail into ranking and require hardcoded food names. Use observed behavior, component structure, nutrition compatibility, time, session co-occurrence, and feedback instead.
  Date/Author: 2026-05-06 / Codex

- Decision: Use embeddings only for identity resolution, not food generation.
  Rationale: Embeddings are useful for deciding whether "chicken curry with rice", "curry rice bowl", and "homemade chicken curry + jasmine rice" are close enough to belong to the same user-specific pattern. They should never create a suggestion whose ingredients or label cannot be traced to accepted user history.
  Date/Author: 2026-05-06 / Codex

- Decision: Keep `FoodMemory` as persistence compatibility during the migration, but do not let proactive suggestions depend on `FoodMemoryKind` or synthetic memory materialization.
  Rationale: `FoodMemory` is already part of the SwiftData schema and matching pipeline. Removing the model immediately would broaden risk. The pattern recommender can be domain-level first, then later decide whether patterns should be cached in existing memory fields or a new persistent model.
  Date/Author: 2026-05-06 / Codex

- Decision: Pattern suggestions require repeated evidence or explicit positive feedback; one-off observations may only contribute to session completion when anchored by current session context.
  Rationale: A single accepted log may be correct history but is often not a useful proactive suggestion. Repetition and engagement should be the default gate. One-off history is acceptable only when it helps complete something the user is actively logging.
  Date/Author: 2026-05-06 / Codex

## Outcomes & Retrospective

No implementation has been completed yet. This plan is the starting point for the rebuild. The expected outcome is a single, pattern-based food suggestion system that removes the current hardcoded food category heuristics, produces suggestions grounded in accepted user history, handles AI naming variance through identity clustering, and proves improvement through replay metrics before TestFlight rollout.

## Context and Orientation

This repository is the Trai iOS app. App code lives under `Trai/`, tests live under `TraiTests/`, and the Xcode project is `Trai.xcodeproj`.

The current food logging and suggestion code is spread across these files:

- `Trai/Core/Models/FoodEntry.swift`: SwiftData model for each logged food event. It stores the display name, macros, timestamp, session id, input method, accepted snapshot data, linked food memory id, and food-memory resolution metadata. `mealType` still exists for compatibility but is marked deprecated in favor of `sessionId`.
- `Trai/Core/Models/FoodMemory.swift`: SwiftData model for canonical remembered foods. It stores display name, aliases, components, nutrition profile, time profile, suggestion stats, repeat patterns, match stats, and status. It has `kindRaw`, which represents `food` or `meal`.
- `Trai/Core/Models/FoodMemoryTypes.swift`: Codable types for accepted snapshots, components, food memory profiles, suggestion stats, resolution state, component roles, and related concepts.
- `Trai/Core/Services/FoodObservationBuilder.swift`: Converts `FoodEntry.acceptedSnapshot` into an in-memory `FoodObservation`. Observations are currently sorted by `loggedAt` and `sessionOrder`.
- `Trai/Core/Services/FoodHabitBuilder.swift`: Groups observations by canonical component names and macro buckets into `FoodHabit` objects. This is the current "habit cluster" layer.
- `Trai/Core/Services/FoodRecommendationCandidateGenerators.swift`: Builds candidates from habits using several generator structs: repeat staple, time context, session completion, semantic variant, recent repeated, and recent complete meal. This file also contains `FoodRecommendationSpecialCases`, which includes hardcoded beverage/protein-bar logic.
- `Trai/Core/Services/FoodRecommendationRanker.swift`: Scores and suppresses recommendation candidates. This file currently applies one-off, already-logged, negative-feedback, low-usefulness, beverage, and non-meal family caps.
- `Trai/Core/Services/FoodRecommendationEngine.swift`: Orchestrates observation building, habit building, candidate generation, ranking, and conversion to `FoodSuggestion`.
- `Trai/Core/Services/FoodSuggestionService.swift`: User-facing service for camera suggestions, feedback recording, shown suggestion reconciliation, debug summaries, and materialization of engine suggestions into `FoodMemory` rows when necessary.
- `Trai/Core/Services/FoodRecommendationEvaluator.swift`: Offline evaluator for replaying historical accepted logs and scoring suggestions against hidden logs.
- `Trai/Core/Services/FoodRecommendationReplayComparisonService.swift`: Local/device debug service that compares recommendation providers on real local data and writes reports without committing private food history.
- `Trai/Core/Services/FoodEmbeddingService.swift`: NaturalLanguage embedding service used for semantic matching. It can be unavailable in simulator environments, so tests using live embeddings must skip cleanly or use deterministic stubs.
- `Trai/Core/Services/FoodMemoryMatcher.swift`: Existing matching logic for entries/snapshots/memories using names, components, macros, and embeddings.
- `Trai/Features/Profile/DeveloperSettingsView.swift`: Developer/debug surface that can expose maintenance and replay workflows.
- `TraiTests/FoodRecommendationCandidateTests.swift`, `TraiTests/FoodRecommendationRankerTests.swift`, `TraiTests/FoodRecommendationHabitTests.swift`, `TraiTests/FoodRecommendationEvaluatorTests.swift`, and `TraiTests/FoodSuggestionIntegrationTests.swift`: Current recommendation-focused tests.
- `TraiTests/FoodMemoryServiceTests.swift`, `TraiTests/FoodMemoryMatcherTests.swift`, and `TraiTests/FoodMemoryFoundationTests.swift`: Current food-memory tests that must remain green unless this plan explicitly changes them.

Definitions used in this plan:

An accepted observation is one food log the user confirmed. It is derived from `FoodEntry.acceptedSnapshot`. The original AI draft is not enough; only the accepted snapshot represents what the user actually logged.

A food pattern is a user-specific learned identity built from accepted observations that appear to be the same reusable food or meal for this user. A pattern is not a bucket such as snack, beverage, breakfast, lunch, dinner, or complete meal. A pattern can represent logs with different AI names when the components, nutrition, serving, and embedding signals are compatible.

Identity resolution is the process of deciding whether an observation belongs to an existing pattern or starts a new pattern.

Provenance means the trace from a suggestion back to the accepted observations that caused it. Every proactive suggestion must have provenance.

Session completion means suggesting a pattern because the current in-progress logging session contains part of a pattern or a historically co-occurring companion. For example, if the user often logs "chicken" and "rice" together, and the current session already contains chicken, rice can be suggested even if rice alone would not normally be a proactive top suggestion.

Replay evaluation means hiding a past accepted log, training the recommender on logs before that instant, asking for suggestions at that instant, and checking whether a suggestion would have helped log the hidden item.

A close equivalent means the suggestion is not text-identical but would still save the user meaningful work. For this system, close equivalent should be judged by pattern identity first, then component overlap plus macro/serving compatibility, and only then embedding similarity.

## Product UX Specification

The normal UI should show a small set of suggestions in the food logging entry point. The user should not see technical source labels or explanations. The rail should look like the current compact food suggestion UI unless a later UI plan changes it. Each suggestion should include a name, emoji if available, and a concise macro/calorie detail if the current UI already does that. It should not display "habit", "pattern", "semantic", "beverage", "snack", "complete meal", or "because you often..." in the normal app surface.

Tap behavior should remain simple. Tapping a suggestion creates or stages a `SuggestedFoodEntry` using the pattern's canonical title, median nutrition, common serving, and representative components. If the user edits before saving, the edit is feedback that the pattern was close but not exact. If the user saves without edit, it is stronger positive feedback. If the user dismisses a suggestion or repeatedly sees it without using it, that is negative feedback.

The user-facing rail should prefer precision over fullness. Showing no suggestion is better than showing a strange one-off. The product should feel smarter over time because repeated accepted logs, accepted suggestion taps, and refined suggestions strengthen the right patterns.

Expected behavior examples:

- If the user logs "Chicken curry with rice", "Curry rice bowl", and "Homemade chicken curry + jasmine rice" on separate days with compatible macros and components, the system should learn one pattern and suggest the canonical title around similar times.
- If the user logs "Katz pastrami sandwich" once, it should not appear as a proactive suggestion merely because it is recent. It may become eligible if the user logs it again or accepts/refines it from a suggestion later.
- If the user logs "chicken" in the current session and prior sessions often include rice after chicken, the system may suggest rice or the full chicken/rice pattern as session completion, but only if the pattern is traceable to accepted history.
- If the AI alternates between "Greek yogurt bowl" and "Yogurt with berries and granola", the system should cluster them only if components, macros, serving, and embedding similarity all support that identity. If macros or components diverge strongly, keep separate patterns.

## Target Architecture

The final path should be:

    FoodEntry accepted snapshots -> FoodObservation -> FoodPattern -> FoodPatternSuggestion -> FoodSuggestion

The old path should not remain as a second recommendation engine. `FoodMemory` can stay for compatibility and persistence, but proactive suggestions should come from `FoodPattern` objects.

Create these domain files:

- `Trai/Core/Services/FoodPatternBuilder.swift`
- `Trai/Core/Services/FoodPatternIdentityScorer.swift`
- `Trai/Core/Services/FoodPatternEmbeddingDocument.swift`
- `Trai/Core/Services/FoodPatternRecommendationEngine.swift`
- `Trai/Core/Services/FoodPatternRanker.swift`
- `Trai/Core/Services/FoodPatternReplayComparator.swift` if the existing evaluator cannot cleanly compare current-vs-pattern providers.

The agent may choose slightly different file names if it keeps the one-engine architecture and updates this plan's `Decision Log`, but it must not create several parallel visible recommendation engines.

The core domain types should be plain Swift structs first, not SwiftData models. This keeps the first implementation deterministic, testable, and low-risk. After replay metrics prove quality, add an optional cache only if performance demands it. A cache may use existing `FoodMemory` JSON fields or a new model in a later plan, but the cache must not be the source of truth. Accepted observations remain the source of truth.

Recommended type shape:

    struct FoodPattern: Identifiable, Sendable, Equatable {
        let id: String
        let canonicalTitle: String
        let emoji: String?
        let observations: [FoodObservation]
        let aliases: [FoodPatternAlias]
        let componentProfile: [FoodPatternComponent]
        let nutritionProfile: FoodPatternNutritionProfile
        let servingProfile: FoodPatternServingProfile?
        let timeProfile: FoodPatternTimeProfile
        let sessionProfile: FoodPatternSessionProfile
        let feedbackProfile: FoodPatternFeedbackProfile
        let identityEvidence: FoodPatternIdentityEvidence
        let lastObservedAt: Date
        let distinctDays: Int
        let observationCount: Int
    }

    struct FoodPatternIdentityEvidence: Sendable, Equatable {
        let averageComponentAgreement: Double
        let averageMacroCompatibility: Double
        let averageServingCompatibility: Double
        let averageEmbeddingSimilarity: Double?
        let hasUserEditedObservation: Bool
        let representativeEntryIDs: [UUID]
    }

    struct FoodPatternSuggestion: Identifiable, Sendable, Equatable {
        let id: String
        let pattern: FoodPattern
        let source: FoodPatternSuggestionSource
        let score: Double
        let features: FoodPatternRankingFeatures
        let provenance: FoodPatternSuggestionProvenance
        let suggestedEntry: SuggestedFoodEntry
    }

    enum FoodPatternSuggestionSource: String, Sendable {
        case likelyNow
        case continueSession
        case recentAgain
    }

Do not expose `FoodPatternSuggestionSource` in normal UI. It exists for tests, replay, and debug summaries.

`FoodPatternSuggestionProvenance` must include enough information for a debug screen or log to explain any suggestion:

    struct FoodPatternSuggestionProvenance: Sendable, Equatable {
        let patternID: String
        let sourceObservationIDs: [UUID]
        let sourceEntryIDs: [UUID]
        let sourceTitles: [String]
        let sourceLoggedAt: [Date]
        let matchedCurrentSessionEntryIDs: [UUID]
        let reasonCodes: [String]
    }

Reason codes should be internal strings such as `repeated-history`, `time-match`, `session-cooccurrence`, `accepted-feedback`, and `recent-repeat`. Do not use food category reason codes such as `beverage`, `snack`, or `complete-meal`.

## Identity Resolution Specification

The hardest problem is AI naming variance. Solve it by clustering accepted observations into food patterns with a conservative weighted identity score.

For each observation, build an identity document:

    FoodPatternEmbeddingDocument(
        title: accepted display name,
        aliases: accepted snapshot aliases,
        components: canonical component names and display names,
        serving: serving text / quantity / unit when available,
        nutrition: coarse calorie and macro buckets,
        notes: accepted notes if available and not private free text
    )

This document is used for embeddings and text similarity. It must be derived only from accepted history. Do not ask the AI to generate new names or components during recommendation.

The identity score between an observation and a pattern should combine:

- Component agreement: exact/canonical component overlap. This is primary when components exist.
- Macro compatibility: calories, protein, carbs, and fat must be within tolerances. This is a gate, not just a boost, when component overlap is high.
- Serving compatibility: serving text/quantity/unit compatibility when available.
- Embedding similarity: semantic closeness of the embedding document, used to bridge naming drift.
- Alias/name similarity: normalized token overlap between accepted names and aliases.
- User edit signal: user-edited accepted observations should influence canonical labels and aliases more than untouched AI drafts, because they represent stronger user truth.

Suggested first-pass gates:

- If both sides have two or more canonical components, component Jaccard similarity must be at least `0.60`.
- If both sides have one canonical component, require either exact canonical component match or embedding similarity at least `0.82` plus macro compatibility.
- Macro compatibility should require calories within `max(160, 35%)`, protein within `max(12g, 45%)`, carbs within `max(18g, 45%)`, and fat within `max(10g, 50%)`. Tighten this in tests if false merges appear.
- Embedding similarity alone must never merge observations when macros are incompatible.
- If components are absent or weak, require stronger embedding similarity, stronger normalized-name overlap, and macro compatibility. Do not merge based only on display name.

False merges are worse than false splits. If two observations might be related but the score is ambiguous, keep them as separate patterns. Suggestions can still show the more repeated pattern; a later accepted/refined action can strengthen a merge.

Canonical title selection:

- Prefer the most common accepted display name among observations.
- If tied, prefer names from user-edited observations.
- If still tied, prefer the most recent accepted title.
- Do not invent a new canonical title with AI.
- Do not concatenate random components into a title unless that exact title or a very close accepted alias exists. If all names are noisy, use the most recent user-edited or accepted snapshot display name.

Component profile selection:

- Include components that appear in at least half of the pattern's observations, or in at least two observations for small clusters.
- Use median component nutrition.
- Preserve display names from the most recent high-confidence accepted observation for that component.

Nutrition profile:

- Use median calories and macros.
- Track lower/upper bounds for replay and matching.
- If macro range is very wide, split the pattern unless the wide range is explained by serving quantity and the serving profile can normalize it.

## Recommendation Specification

The new recommender should produce suggestions from one pattern-based engine. It may internally consider three source cases, but they all use the same `FoodPattern` corpus and same ranker.

Eligibility rules:

- A proactive `likelyNow` or `recentAgain` suggestion requires `distinctDays >= 2` and `observationCount >= 2`, or at least one prior accepted/refined suggestion outcome for that exact pattern.
- A `continueSession` suggestion can use a pattern with weaker standalone evidence only if the current session contains an anchored related observation and historical sessions show co-occurrence. One-off session completion must be conservative and should require either at least two historical session co-occurrences or one co-occurrence plus strong component/subset evidence from a repeated pattern.
- A suggestion must have at least one accepted observation before the target instant. Never train on future logs or later same-day logs.
- A pattern already logged in the current day should be suppressed unless the user has repeated it multiple times per day on at least two distinct days and at least two hours have passed since today's last matching log.
- A pattern with repeated shown/no-action feedback should be suppressed or strongly demoted.
- A pattern with dismissals greater than accepts should be suppressed for at least 12 hours after dismissal and demoted after that.

Ranking features:

- Repetition: distinct days and observation count.
- Recency: last observed date with decay.
- Time match: observed hours around the target instant. Use hour-of-day as a numeric distribution, not meal bucket labels.
- Weekday/weekend match.
- Session co-occurrence: whether current session observations historically co-occurred with this pattern.
- Pattern confidence: identity evidence, macro stability, component stability.
- Positive feedback: accepted/refined suggestions.
- Negative feedback: dismissed or repeatedly ignored suggestions.
- Usefulness by behavior: prefer patterns that saved meaningful user effort, measured by past accepts/refines and component count, not by hardcoded food categories.

Do not include hardcoded string checks for latte, coffee, cappuccino, protein bar, snack, beverage, complete meal, breakfast, lunch, or dinner in the recommendation path. The only acceptable place for strings like breakfast/lunch/dinner/snack is legacy `FoodEntry.mealType`, existing notification/reminder features, AI contract compatibility, or tests proving the recommender ignores those categories.

`SuggestedFoodEntry` creation:

- Use the pattern canonical title.
- Use median nutrition and common serving.
- Use the pattern component profile.
- Set `notes` to nil or a neutral internal/debug note. Do not show explanatory text in normal UI.
- Avoid `mealKind` if downstream code permits nil. If `mealKind` is required by existing types, set it only for compatibility and do not use it for ranking or eligibility.

## Migration and Cleanup Specification

This is a rebuild, not an additive experiment. At the end of the plan:

- `FoodRecommendationEngine` should either be replaced by `FoodPatternRecommendationEngine` or become a thin compatibility wrapper around it.
- `FoodRecommendationCandidateGeneratorSet`, `RepeatStapleFoodCandidateGenerator`, `TimeContextFoodCandidateGenerator`, `SessionCompletionFoodCandidateGenerator`, `SemanticVariantFoodCandidateGenerator`, `RecentRepeatedFoodCandidateGenerator`, `RecentCompleteMealFoodCandidateGenerator`, and `FoodRecommendationSpecialCases` should be deleted or removed from the visible path after tests are migrated.
- `FoodRecommendationRanker` should be deleted or converted into `FoodPatternRanker` with no hardcoded food category logic.
- `FoodHabitBuilder` may remain only if it becomes `FoodPatternBuilder` or an internal compatibility alias. Do not keep both a habit engine and a pattern engine in active use.
- `FoodSuggestionService.materializedEngineSuggestions` should stop creating `FoodMemory` rows merely because a suggestion has a synthetic id. A memory row should be created or updated only when the user accepts/logs the suggestion or normal post-save memory resolution runs.
- Existing food-memory matching and consolidation should remain for save-path reuse unless the plan explicitly replaces it. This plan changes proactive suggestions first.

## Plan of Work

Milestone 1 adds failing tests before implementation. Create or update tests in `TraiTests/FoodPatternIdentityTests.swift`, `TraiTests/FoodPatternRecommendationTests.swift`, `TraiTests/FoodSuggestionIntegrationTests.swift`, and `TraiTests/FoodRecommendationEvaluatorTests.swift`. The tests should prove that similarly named-but-not-identical curry/rice observations cluster, one-off foods do not appear proactively, hardcoded beverage/snack strings are irrelevant, session completion works from observed co-occurrence, and every suggestion has provenance. Run the focused tests and confirm the new tests fail for expected reasons before implementation.

Milestone 2 creates the `FoodPattern` domain layer. Add `FoodPatternBuilder`, `FoodPatternIdentityScorer`, and support structs. It should consume `[FoodObservation]` and return `[FoodPattern]`. Start without live embeddings; use components, macros, serving, aliases, normalized names, and deterministic text similarity. Replace direct `FoodHabitBuilder` use in tests with the new pattern builder where appropriate.

Milestone 3 adds embedding-backed identity resolution. Add `FoodPatternEmbeddingDocument` and an abstraction such as `FoodPatternEmbeddingProvider` so tests can use deterministic vectors. The live provider can wrap `NLFoodEmbeddingService` or existing `FoodEmbeddingService`, but the recommendation hot path must not block on loading NaturalLanguage for every suggestion. If embeddings are unavailable, the system should still work conservatively with structural matching. Add tests that prove embeddings merge name variants only when macros/components are compatible.

Milestone 4 builds the new recommendation engine. Add `FoodPatternRecommendationEngine` and `FoodPatternRanker`. It should build observations filtered to `loggedAt < targetDate`, build patterns, compute current-session observations, rank eligible patterns, and return `FoodPatternSuggestion`s. It should replace the current source/generator model with the internal source cases `likelyNow`, `continueSession`, and `recentAgain`. Add debug output with counts and provenance.

Milestone 5 wires `FoodSuggestionService` to the pattern recommender. `cameraSuggestions` should call the new engine and map `FoodPatternSuggestion` to `FoodSuggestion`. Feedback should be recorded against a stable pattern id or linked memory id without materializing synthetic memories on show. If existing APIs require UUIDs, create a deterministic UUID from the pattern id for UI identity only, and store pattern feedback in a dedicated JSON payload or map it to a real memory only after acceptance. Update `reconcileShownSuggestions` so accepted/refined feedback updates the right pattern/memory after save.

Milestone 6 removes the old active recommendation path and hardcoded category logic. Delete or retire unused candidate generators and tests that assert beverage/protein-bar special cases. Replace them with behavior-based tests. Search the proactive recommendation path for `latte`, `coffee`, `cappuccino`, `protein bar`, `beverage`, `snack`, `completeMeal`, `MealTimeBucket`, and `FoodMemoryKind`; any remaining uses must either be outside proactive recommendation or documented as compatibility-only.

Milestone 7 strengthens replay comparison. Update the evaluator so it compares the current/legacy provider and the new pattern provider on the same cases. Add metrics for exact hit, pattern hit, close-equivalent hit, one-off false positives, unknown-provenance suggestions, synthetic-memory materialization, duplicate suggestions, no-suggestion rate, accepted/refined feedback lift, and runtime. Add slices by time of day using numeric hour ranges, not breakfast/lunch/dinner buckets. Keep real user history local-only and write reports to app caches or `/private/tmp`.

Milestone 8 validates and prepares for TestFlight. Run focused tests, broader food-memory tests, an iOS build, and device replay on Nadav's iPhone if available. The final report must say whether the pattern recommender beats the current build and where it still fails. Do not ship if the new system merely increases suggestion count without improving pattern/close-equivalent hits and lowering one-off false positives.

## Concrete Steps

Start from the repository root:

    cd /Users/nadav/Desktop/Trai

Before editing, inspect the current files:

    sed -n '1,220p' Trai/Core/Services/FoodRecommendationEngine.swift
    sed -n '1,260p' Trai/Core/Services/FoodRecommendationCandidateGenerators.swift
    sed -n '1,240p' Trai/Core/Services/FoodRecommendationRanker.swift
    sed -n '1,260p' Trai/Core/Services/FoodHabitBuilder.swift
    sed -n '1,220p' Trai/Core/Services/FoodSuggestionService.swift
    sed -n '1,220p' Trai/Core/Services/FoodRecommendationEvaluator.swift

If the local checkout's git status or file reads hang, use targeted file reads and continue. Do not run destructive git commands. If a fresh remote review is needed, clone to `/private/tmp` instead of modifying the main checkout.

Write tests first. Suggested new tests:

- `FoodPatternIdentityTests.testClustersAcceptedNameVariantsWithCompatibleStructure`
  Build three accepted entries named "Chicken curry with rice", "Curry rice bowl", and "Homemade chicken curry + jasmine rice" with overlapping chicken/rice/curry components and compatible macros. Assert `FoodPatternBuilder().patterns(from:)` returns one pattern with `distinctDays == 3`, aliases containing all names, and representative entry ids for all entries.

- `FoodPatternIdentityTests.testDoesNotMergeSameComponentsWhenMacrosAreIncompatible`
  Build "Chicken and rice" entries where one is a 450 calorie bowl and one is a 1200 calorie platter. Assert they become separate patterns or the identity score fails the merge gate.

- `FoodPatternIdentityTests.testEmbeddingCannotOverrideMacroIncompatibility`
  Use a deterministic embedding provider that returns high similarity for two observations with incompatible macros. Assert they do not merge.

- `FoodPatternRecommendationTests.testOneOffAcceptedFoodIsNotProactive`
  Build repeated chicken/rice observations and one Katz pastrami sandwich observation. At lunch target time, assert suggestions contain chicken/rice and do not contain Katz.

- `FoodPatternRecommendationTests.testRecentOneOffCanOnlyAppearAsSessionCompletionWithAnchor`
  Build a current session with an anchor food and historical session co-occurrence. Assert the completion suggestion appears only when the current session anchor is present, and does not appear in a blank proactive rail.

- `FoodPatternRecommendationTests.testNoHardcodedBeverageOrSnackSuppression`
  Build repeated observations named "Latte" and "Protein Bar" plus another repeated pattern. Assert eligibility is determined by evidence and feedback, not string special cases. The test should not require latte/protein bar to be always hidden or always shown; it should prove no special-case path is needed.

- `FoodPatternRecommendationTests.testEverySuggestionIncludesProvenance`
  Assert each returned suggestion includes source entry ids, titles, dates, and reason codes.

- `FoodSuggestionIntegrationTests.testPatternSuggestionsDoNotMaterializeFoodMemoryRowsOnShow`
  Insert accepted entries, fetch camera suggestions, and assert the number of `FoodMemory` rows does not increase until the user accepts/logs a suggestion.

- `FoodRecommendationEvaluatorTests.testReplayReportsPatternHitSeparatelyFromExactTitleHit`
  Hide a curry/rice variant and train on earlier variants. Assert exact title hit can be false while pattern hit or close-equivalent hit is true.

Run focused tests before implementation and record that they fail:

    xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiPatternSuggestionsTDD -only-testing:TraiTests/FoodPatternIdentityTests -only-testing:TraiTests/FoodPatternRecommendationTests -only-testing:TraiTests/FoodSuggestionIntegrationTests -only-testing:TraiTests/FoodRecommendationEvaluatorTests test

If the named simulator is unavailable, run:

    xcrun simctl list devices available

Then rerun with an available iPhone simulator destination. If simulator runtimes are unavailable but a physical device is connected, use the existing device flow and document the destination in `Progress`.

After implementing each milestone, rerun the focused tests. At the end, also run:

    xcodebuild -project Trai.xcodeproj -scheme TraiTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /private/tmp/TraiPatternSuggestionsFoodMemory -only-testing:TraiTests/FoodMemoryFoundationTests -only-testing:TraiTests/FoodMemoryMatcherTests -only-testing:TraiTests/FoodMemoryServiceTests test

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/TraiPatternSuggestionsBuild CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

    git diff --check

Run device replay only after unit/integration tests pass. Use the existing launch flags if still present:

    --run-food-recommendation-replay-comparison
    --food-recommendation-replay-cases 50

The report should be copied from app caches or written to `/private/tmp`. Do not commit private replay reports or raw food history.

## Validation and Acceptance

The feature is accepted only when these behaviors are true:

- The normal camera suggestion path uses one pattern-based recommender, not several overlapping engines.
- There are no hardcoded food-name checks for beverage/snack/protein-bar/complete-meal suppression in the proactive recommendation path.
- Suggestions are grounded in accepted observations and include debug provenance.
- AI naming variants cluster when structure, macros, serving, and embedding signals support the same identity.
- Similar names or embeddings do not merge incompatible foods.
- One-off foods do not appear as blank-context proactive suggestions.
- Session completion can suggest useful additions when anchored by current-session history.
- Showing suggestions does not create synthetic `FoodMemory` rows.
- Feedback from shown, accepted, dismissed, and refined suggestions affects the same learned pattern.
- Replay evaluation reports exact hit, pattern hit, close-equivalent hit, one-off false positives, duplicate suggestions, unknown-provenance suggestions, no-suggestion rate, and runtime.
- Real-history replay demonstrates improvement over the current build. Minimum bar: pattern/close-equivalent Hit@3 improves, one-off false positives decrease, unknown-provenance suggestions are zero, duplicate suggestions are zero, and runtime remains acceptable for the camera suggestion path. If exact Hit@1 does not improve, the final report must explain whether close-equivalent hits improved enough to justify the UX.

Each milestone must follow the test-first verification workflow:

1. Write the tests listed for the milestone.
2. Run the focused test command and confirm the new tests fail for the expected reason.
3. Implement the milestone.
4. Rerun the focused tests until they pass.
5. Update `Progress`, `Surprises & Discoveries`, and `Decision Log` in this file.
6. Commit the milestone with a message such as `Milestone 2: Add food pattern identity builder` after tests pass.

## Idempotence and Recovery

All implementation steps should be safe to repeat. Builders and evaluators should be pure or read-only over existing `FoodEntry` history. Do not mutate real food history during replay. Do not commit private reports, private food history fixtures, device cache dumps, or local app containers.

If a migration or schema addition becomes necessary, stop and update this plan before editing models. Prefer a domain-layer implementation first. SwiftData/CloudKit schema changes are higher risk and should be justified by performance or correctness evidence.

If NaturalLanguage embeddings are unavailable in simulator tests, live embedding tests may skip with a clear message, but deterministic provider tests must still pass. The recommender must remain conservative without embeddings.

If the new engine returns fewer suggestions than the old engine, that is acceptable only if replay quality improves and one-off false positives decrease. Do not tune for suggestion count alone.

If real-device replay fails because the app is killed during launch, keep the replay path cheap: skip routine maintenance during replay launches, limit case count, and write incremental reports to app caches so partial results can be recovered.

## Artifacts and Notes

Prior local evidence that motivated this rebuild:

    Current replay after earlier fixes:
    Hit@1/3/5 and MRR tied legacy at 0.100.
    Beverage domination improved from 0.100 to 0.050.
    Duplicate suggestions improved from 0.100 to 0.000.
    noSuggestions increased to 0.550.

This means the earlier engine got safer but not meaningfully smarter. This plan should be judged by whether it improves useful close-equivalent suggestions for real accepted logs, not merely whether it suppresses bad suggestions.

Useful search commands during cleanup:

    rg -n "latte|coffee|cappuccino|protein bar|beverage|snack|completeMeal|RecentCompleteMeal|SemanticVariant|FoodRecommendationSpecialCases" Trai/Core/Services TraiTests

Expected result after Milestone 6: any remaining matches are outside the proactive recommendation path, are legacy compatibility, or are tests asserting those concepts no longer drive recommendations.

Do not commit:

    /private/tmp/FoodRecommendationReplayComparison*.txt
    app container cache exports
    raw accepted food history
    screenshots or logs containing private food history

## Interfaces and Dependencies

Use Swift and the existing project structure. Do not add a third-party recommender library. The system should be deterministic and testable with XCTest.

Use existing types where possible:

- `FoodEntry`
- `AcceptedFoodSnapshot`
- `AcceptedFoodComponent`
- `SuggestedFoodEntry`
- `FoodObservation`
- `FoodObservationComponent`
- `FoodSuggestion`
- `FoodSuggestionOutcome`
- `FoodMemorySuggestionStats`
- `FoodEmbeddingService` or `NLFoodEmbeddingService`

Add an embedding abstraction for tests:

    protocol FoodPatternEmbeddingProvider: Sendable {
        func embedding(for document: FoodPatternEmbeddingDocument) async throws -> [Double]?
    }

If async embedding makes the visible path awkward, split pattern building into two paths:

- A synchronous structural path used by `cameraSuggestions`.
- An async enrichment/backfill path that precomputes embeddings and stores them on accepted observations or memory-compatible cache fields.

Do not block the camera suggestion path on expensive embedding generation for every launch. If embeddings are missing, use structural matching conservatively and let background maintenance enrich later.

The final public surface should be small:

    struct FoodPatternRecommendationEngine {
        func recommendationsSync(for request: FoodRecommendationRequest) -> FoodPatternRecommendationResult
    }

or, if async embedding is required:

    struct FoodPatternRecommendationEngine {
        func recommendations(for request: FoodRecommendationRequest) async throws -> FoodPatternRecommendationResult
        func recommendationsSync(for request: FoodRecommendationRequest) -> FoodPatternRecommendationResult
    }

The sync method must be safe for the current UI path and must not perform live NaturalLanguage loading. The async method may be used by debug/replay/backfill.

`FoodPatternRecommendationResult` should include:

    struct FoodPatternRecommendationResult: Sendable, Equatable {
        let suggestions: [FoodPatternSuggestion]
        let debugReport: FoodPatternRecommendationDebugReport
    }

`FoodPatternRecommendationDebugReport` should include:

    struct FoodPatternRecommendationDebugReport: Sendable, Equatable {
        let observationCount: Int
        let patternCount: Int
        let eligiblePatternCount: Int
        let suppressedOneOffCount: Int
        let suppressedAlreadyTodayCount: Int
        let suppressedNegativeFeedbackCount: Int
        let suppressedLowConfidenceCount: Int
        let finalShownTitles: [String]
        let provenanceByTitle: [String: FoodPatternSuggestionProvenance]
    }

The agent may refine these exact signatures while implementing, but the resulting interfaces must preserve the same capabilities: pattern identity, provenance, conservative eligibility, no hardcoded food categories, and replay/debug observability.

## Revision Note

2026-05-06 / Codex: Initial version. This plan replaces the prior observation/habit recommendation direction with a stricter user-specific `FoodPattern` architecture, removes hardcoded food category concepts from the proactive suggestion path, and defines replay gates for proving real improvement before TestFlight use.
