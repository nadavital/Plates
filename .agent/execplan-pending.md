# ExecPlan: Deliver High-Utility Trai Pulse Personalization Without Context Bloat

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository has `.agent/PLANS.md`; this plan must be maintained in accordance with that file.

## Purpose / Big Picture

After this change, Trai Pulse should feel like a useful daily copilot instead of a decorative dashboard block. The user should open Dashboard and see one recommendation that matches their real behavior patterns (when they usually work out, which meals they actually log, what recent constraints matter), one quick question they can answer in under 5 seconds, and action buttons that save steps.

The core outcome is not “more AI text.” The core outcome is faster execution and better adherence. Users should need less thinking and fewer taps to decide what to do next, and Trai chat should already know the recent context when they continue the conversation.

This plan intentionally limits model context size and token cost by sending compact, ranked signals rather than raw history.

## Progress

- [x] (2026-02-12 03:13Z) Audited current Pulse, chat context, short-term signal, and dashboard wiring to anchor this plan in existing files.
- [x] (2026-02-12 03:13Z) Confirmed repo has no XCTest target and no Beads setup (`.beads/` is absent), so milestone verification uses focused build + deterministic/manual behavior checks.
- [x] (2026-02-12 03:56Z) Implemented Milestone 1: added deterministic pattern-learning extraction service and profile contracts, then wired profile generation into dashboard recommendation context.
- [x] (2026-02-12 03:56Z) Implemented Milestone 2: added compact context packet assembler with slot limits, token estimation, and truncation budget handling; wired packet generation into Pulse path and chat prompt context.
- [ ] (2026-02-12 06:16Z) Implement Milestone 3 (completed: response interpreter, supportive post-answer “what changed” feedback, recent-answer carryover in Pulse message/reasons, dynamic action overrides from recent answers; remaining: explicit utility-score abstraction and stricter question ranking).
- [ ] (2026-02-12 06:16Z) Implement Milestone 4 (completed: richer Dashboard-to-chat seeded handoff prompt built from current recommendation + recent answer; remaining: additional role/prompt tightening in `GeminiService+FunctionCallingHelpers`).
- [ ] (2026-02-12 06:16Z) Implement Milestone 5 (completed: local interaction tracking for Pulse actions and Pulse question answers via `SuggestionUsage`; remaining: impression tracking + follow-through summaries).
- [ ] Run full validation flows, tune thresholds, and document outcomes.

## Surprises & Discoveries

- Observation: The app already contains most infrastructure needed for temporary context (`CoachSignal`, `CoachSignalService`, tool calls for save/clear short-term context), so this plan should focus on ranking and compression rather than net-new memory primitives.
  Evidence: `Trai/Core/Models/CoachSignal.swift`, `Trai/Core/Services/CoachSignalService.swift`, `Trai/Core/Services/GeminiFunctionDeclarations.swift`, `Trai/Core/Services/GeminiFunctionExecutor+Memory.swift`.

- Observation: Chat already includes a dedicated `pulseContext` field in function-calling prompt assembly, which is the correct insertion point for compact context packets.
  Evidence: `Trai/Core/Services/GeminiChatTypes.swift`, `Trai/Features/Chat/ChatViewMessaging.swift`, `Trai/Core/Services/GeminiService+FunctionCallingHelpers.swift`.

- Observation: Dashboard Pulse behavior is deterministic and trend-aware but largely template-based, which explains “useful but still hardcoded” feedback.
  Evidence: `Trai/Core/Services/TraiPulseEngine.swift`, `Trai/Core/Services/DailyCoachEngine.swift`.

- Observation: The codebase already tracks interaction timing in `SuggestionUsage`, which can be reused for engagement and habit timing without introducing an external analytics stack.
  Evidence: `Trai/Core/Models/SuggestionUsage.swift`, `Trai/Features/Chat/ChatViewActions.swift`.

- Observation: Existing dashboard trend computation duplicated logic that is now needed by chat context too, so moving trend/profile extraction to a shared service reduced duplication and keeps scoring consistent across surfaces.
  Evidence: `Trai/Core/Services/TraiPulsePatternService.swift`, `Trai/Features/Dashboard/DashboardView.swift`, `Trai/Features/Chat/ChatViewMessaging.swift`.

- Observation: A full project build remains the practical compile-safety check in this repo; latest validation after Milestone 1/2 changes succeeded.
  Evidence: `xcodebuild -project Trai.xcodeproj -scheme Trai ... build` ended with `** BUILD SUCCEEDED **` on 2026-02-12.

- Observation: A dedicated response-interpretation layer was needed because UI feedback, short-term signal writes, and durable-memory extraction were diverging when coded ad hoc in each surface.
  Evidence: `Trai/Core/Services/TraiPulseResponseInterpreter.swift` now centralizes domain/severity/ttl, acknowledgement copy, carryover parsing, and memory-candidate rules.

## Decision Log

- Decision: Build a lean personalization layer first (behavior features + ranking + compact context) before broad AI generation.
  Rationale: This maximizes practical utility and minimizes token/cost risk while keeping behavior debuggable.
  Date/Author: 2026-02-12 / Codex.

- Decision: Use a memory pyramid: durable profile signals, short-lived overlays, and request-scoped context packets.
  Rationale: This prevents prompt bloat while preserving personalization continuity across app surfaces.
  Date/Author: 2026-02-12 / Codex.

- Decision: Keep Pulse deterministic for recommendation selection and use AI generation only as optional language enhancement with deterministic fallback.
  Rationale: Reliability and latency are more important than fully generated prose for this surface.
  Date/Author: 2026-02-12 / Codex.

- Decision: Treat ROI as a product gate, not an assumption.
  Rationale: This feature occupies significant screen real estate; it must prove engagement and execution lift or be reduced.
  Date/Author: 2026-02-12 / Codex.

- Decision: Share one deterministic pattern/trend extraction service between dashboard and chat context assembly.
  Rationale: This avoids divergent behavior between Pulse and Trai chat and keeps context packets stable as history grows.
  Date/Author: 2026-02-12 / Codex.

- Decision: Keep context packet serialization compact (`key=value` lines) and enforce budget by dropping lower-priority snippets first.
  Rationale: This minimizes token cost while preserving high-utility constraints/patterns.
  Date/Author: 2026-02-12 / Codex.

- Decision: Introduce a deterministic Pulse response interpreter shared by Dashboard write path and Pulse render path.
  Rationale: This creates one source of truth for how answers map to short-term signals, durable memory, and user-facing adaptation feedback.
  Date/Author: 2026-02-12 / Codex.

## Outcomes & Retrospective

Milestones 1 and 2 are implemented and compiling. Milestone 3/4/5 each now have partial implementation progress: responses are interpreted through a shared deterministic layer, post-answer feedback is adaptive and supportive, recent answers influence recommendations/actions, seeded chat handoff is richer, and local Pulse interactions are tracked through `SuggestionUsage`.

Remaining gap to purpose: formal utility scoring/ranking in `TraiPulseEngine`, role-prompt refinement for chat carryover, impression/follow-through ROI summaries, and final manual validation scenarios.

## Context and Orientation

The implementation spans Dashboard recommendation generation, temporary context capture, and chat prompt assembly.

The main dashboard composition is in `Trai/Features/Dashboard/DashboardView.swift`, and the Pulse UI surface is `Trai/Features/Dashboard/TraiPulseHeroCard.swift`. Recommendation generation currently routes through `Trai/Core/Services/DailyCoachEngine.swift` and `Trai/Core/Services/TraiPulseEngine.swift`, with core contracts in `Trai/Core/Services/TraiPulseTypes.swift`.

Temporary context storage is modeled by `Trai/Core/Models/CoachSignal.swift` and persisted via `Trai/Core/Services/CoachSignalService.swift`. Post-workout capture already exists in `Trai/Features/Workouts/PostWorkoutPulseCheckInSheet.swift` and `Trai/Features/Workouts/LiveWorkoutView.swift`.

Chat already consumes memory and pulse context via `Trai/Features/Chat/ChatViewMessaging.swift`, `Trai/Core/Services/GeminiChatTypes.swift`, and `Trai/Core/Services/GeminiService+FunctionCallingHelpers.swift`. Function tools for short-term context are defined in `Trai/Core/Services/GeminiFunctionDeclarations.swift` and executed in `Trai/Core/Services/GeminiFunctionExecutor+Memory.swift`.

Interaction telemetry available today is local and model-based through `Trai/Core/Models/SuggestionUsage.swift`.

Definitions used in this plan:

- Pattern profile: compact learned behavior summary (for example likely workout window, frequent protein anchors, logging consistency by time of day).
- Overlay signal: short-lived constraint or state that should expire automatically (for example shoulder discomfort, poor sleep last night).
- Context packet: strict, slot-limited payload assembled per request for Pulse and chat prompting.
- Utility score: ranking score used to decide which insight/question/action is worth showing now.

## Plan of Work

### Milestone 1: Build pattern-learning profile from existing data

Create a new service at `Trai/Core/Services/TraiPulsePatternService.swift` that reads existing entities and returns a compact `TraiPulsePatternProfile` (added to `Trai/Core/Services/TraiPulseTypes.swift`). This profile should be built from the last 28 days and include:

- likely workout windows (probability by hour bands),
- frequent meal timing windows,
- common high-protein meal anchors (top normalized meal names),
- adherence tendencies (for example protein misses clustered on certain weekdays),
- action affinity from `SuggestionUsage` (which quick actions are usually accepted).

Keep this profile deterministic and lightweight. No LLM call is needed in this milestone.

Wire profile generation in `DashboardView` and pass it into `DailyCoachContext` so Pulse can reason over real habit patterns rather than only same-day status.

### Milestone 2: Add context assembler with strict budgets

Create `Trai/Core/Services/TraiPulseContextAssembler.swift` that turns profile + active signals + near-term state into a request-scoped `TraiPulseContextPacket`.

Use fixed slot limits and drop low-utility items when over budget. Initial packet shape:

- 1 active goal,
- up to 2 active constraints,
- up to 3 high-confidence patterns,
- up to 2 anomalies,
- up to 2 suggested next actions.

Add a lightweight token estimator (character or word-based heuristic) and enforce a hard cap (target 500-800 tokens equivalent when serialized). Context should be emitted in compact key/value style, not narrative prose.

Integrate assembler output into:

- Pulse recommendation path (`TraiPulseEngine` input),
- chat function context field (`pulseContext` in `ChatViewMessaging`).

This milestone is the main anti-bloat guardrail.

### Milestone 3: Improve Pulse content utility and engagement loop

Upgrade `TraiPulseEngine` and `TraiPulseHeroCard` so every displayed element has utility intent.

In `TraiPulseEngine`, replace static template priority with utility-scored candidate recommendations. Utility score should consider recency, confidence, actionability, novelty, and user affinity.

In `TraiPulseHeroCard`, keep one adaptive question at a time but improve engagement quality:

- always support quick answer (choice/slider) plus free-typed answer,
- add answer cooldown (do not repeat same question too frequently),
- show supportive copy and immediate “what changed” feedback after answer save,
- ensure action buttons are dynamic from current top recommendations, not static labels.

In `DashboardView`, when users answer Pulse questions, save short-term signals through `CoachSignalService` and, when confidence is high and durable, optionally save durable memory through existing memory paths.

### Milestone 4: Cross-surface carryover and role clarity (Pulse vs Trai chat)

Keep Pulse as proactive one-turn coaching and Trai tab as deeper multi-turn exploration.

Implement carryover behavior so “Discuss in Trai” opens chat with compact Pulse context and seeded prompt that references current recommendation and user response.

Update chat prompt section generation to consume only the assembled compact packet instead of raw signal summaries, and add instruction rules so the model prioritizes temporary overlays only for near-term recommendations.

Confirm this context influences responses in practical scenarios, especially temporary injury constraints and schedule constraints.

### Milestone 5: Add local ROI instrumentation and release guardrails

Extend `SuggestionUsage` usage points (or add a small `PulseInteraction` model if needed) to track:

- Pulse impression count,
- primary/secondary action taps,
- question response rate,
- follow-through proxy events (for example action tap followed by workout start or food log within session).

Add a simple local debug summary path (console output or existing developer surface) so the team can evaluate ROI during dogfooding.

Define keep/iterate/rollback criteria before broad rollout:

- keep if quick action completion lifts materially,
- keep if question response rate stays healthy,
- iterate or shrink if engagement is low and recommendation relevance is weak.

## Concrete Steps

All commands run from repository root: `/Users/nadav/Desktop/Trai`.

1. Confirm targets and schemes before edits.

    xcodebuild -list -project Trai.xcodeproj

    Expected signal: targets include `Trai` and `TraiWidgetsExtension`; no test target is expected unless added separately.

2. After each milestone that edits Swift files, run focused compile validation.

    xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TraiDerived CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

    Expected signal: command ends with `** BUILD SUCCEEDED **`.

3. Verify context assembler and profile usage wiring.

    rg -n "TraiPulsePatternProfile|TraiPulseContextPacket|TraiPulseContextAssembler|utilityScore" Trai

    Expected signal: references appear in services and dashboard/chat integration points.

4. Verify short-term and durable memory separation rules remain explicit.

    rg -n "save_short_term_context|clear_short_term_context|save_memory|pulseContext" Trai/Core/Services Trai/Features/Chat

    Expected signal: prompt and tool wiring clearly distinguish temporary context from durable memory.

5. Verify Pulse UI still has one primary question path and custom answer fallback.

    rg -n "questionSection|Submit Custom Answer|Type your own answer" Trai/Features/Dashboard/TraiPulseHeroCard.swift

    Expected signal: one-question flow with typed fallback remains present.

## Validation and Acceptance

The feature is accepted only if behavior and user-value criteria below are all met.

Behavioral acceptance:

1. Dashboard Pulse recommendation changes based on learned behavior patterns, not only same-day macro totals.
2. A temporary signal like “shoulder hurt during overhead press” influences next-day recommendation and chat suggestions, then naturally expires.
3. Pulse question flow supports both fast structured response and typed custom response every time.
4. “Discuss in Trai” navigates correctly and carries current Pulse context without forcing the user to restate details.
5. Context packet size remains capped and stable as user history grows.

User-value acceptance:

1. Users can complete a suggested next step with fewer taps than equivalent manual navigation.
2. Recommendations are time-appropriate (for example workout nudge near user’s learned workout window).
3. Meal guidance references foods the user commonly eats when possible, not generic suggestions by default.

Milestone verification workflow:

For each milestone, use this sequence:

1. Tests to write: If a `TraiTests` target is introduced, add deterministic tests for pattern extraction and context assembly outputs first. If no test target exists, create deterministic debug fixtures/previews and document expected outputs before implementation.
2. Implementation: Apply the milestone changes to the files named in this plan.
3. Verification: Run focused build command and milestone-specific manual scenario checks.
4. Commit: After verification passes, commit with message `Milestone N: <short description>`.

Manual scenario suite (required before final completion):

1. Simulate a user with evening workout habit and confirm Pulse at-risk messaging is delayed until near that window.
2. Save a post-workout discomfort signal and confirm next-day Pulse and chat adjust exercise guidance.
3. Log common protein meal patterns for multiple days and confirm Pulse proposes those anchors when protein gap exists.
4. Verify question response updates recommendation context immediately.
5. Confirm expired temporary signals no longer appear in Pulse/chat context.

## Idempotence and Recovery

This implementation is additive and safe to rerun. Pattern extraction reads existing data and does not mutate nutrition/workout history. Context assembly is computed output and should not corrupt persisted entities.

If a milestone fails:

- keep existing deterministic Pulse fallback active,
- disable new assembler usage behind a temporary flag and continue with prior `pulseSummary` output,
- keep short-term context writes enabled even if pattern profile generation is temporarily disabled,
- rerun build after each rollback step to isolate breakage.

No destructive data migration is required. Do not remove or rewrite historical `FoodEntry`, `WorkoutSession`, `LiveWorkout`, `CoachMemory`, or `CoachSignal` records.

## Artifacts and Notes

Capture concise evidence for each milestone:

- one screenshot of Pulse hero with behavior-informed recommendation,
- one screenshot of adaptive question with typed fallback,
- one short chat transcript showing carryover context in action,
- one short log snippet showing context packet slot selection and truncation.

Keep artifacts short and tied to acceptance criteria.

## Interfaces and Dependencies

By Milestone 2, the following interfaces must exist.

In `Trai/Core/Services/TraiPulseTypes.swift`, define compact personalization contracts similar to:

    struct TraiPulsePatternProfile: Sendable {
        let workoutWindowScores: [String: Double]
        let mealWindowScores: [String: Double]
        let commonProteinAnchors: [String]
        let adherenceNotes: [String]
        let actionAffinity: [String: Double]
        let confidence: Double
    }

    struct TraiPulseContextPacket: Sendable {
        let goal: String
        let constraints: [String]
        let patterns: [String]
        let anomalies: [String]
        let suggestedActions: [String]
        let estimatedTokens: Int
        var promptSummary: String
    }

In `Trai/Core/Services/TraiPulsePatternService.swift`, define a deterministic builder API:

    func buildProfile(
        now: Date,
        foodEntries: [FoodEntry],
        workouts: [WorkoutSession],
        liveWorkouts: [LiveWorkout],
        suggestionUsage: [SuggestionUsage],
        profile: UserProfile?
    ) -> TraiPulsePatternProfile

In `Trai/Core/Services/TraiPulseContextAssembler.swift`, define:

    func assemble(
        patternProfile: TraiPulsePatternProfile,
        activeSignals: [CoachSignalSnapshot],
        context: TraiPulseInputContext,
        tokenBudget: Int
    ) -> TraiPulseContextPacket

In `Trai/Core/Services/TraiPulseEngine.swift`, recommendation generation must accept context packet input and use utility scoring for action/question selection.

In `Trai/Features/Chat/ChatViewMessaging.swift` and `Trai/Core/Services/GeminiChatTypes.swift`, `pulseContext` population must come from `TraiPulseContextPacket.promptSummary`, not raw log dumps.

In `Trai/Features/Dashboard/DashboardView.swift`, pass pattern profile and active overlay context into Pulse generation at view update boundaries that already exist.

## Revision Note

Updated on 2026-02-12 by Codex to replace the prior pending plan with a lean, ROI-gated implementation plan centered on context-efficient personalization. This revision reflects newer product direction: maximize practical user utility and engagement while controlling AI context size and token cost.

Updated on 2026-02-12 by Codex to capture the new response interpreter implementation, seeded handoff improvements, and partial ROI telemetry wiring, plus the remaining work for Milestones 3-5.
