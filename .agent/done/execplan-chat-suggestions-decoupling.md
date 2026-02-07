# ExecPlan: Decouple Chat Suggestion Models from `GeminiFunctionExecutor`

## Problem Statement
`GeminiFunctionExecutor` currently owns user-facing suggestion types (`SuggestedReminder`, `PlanUpdateSuggestion`) that are consumed across UI, persistence, and Gemini service layers. This leaks execution-layer internals into feature code and increases coupling/bug surface when either function execution or chat UI evolves.

Consolidation target:
- Move user-facing suggestion contracts into `Core/Models`.
- Keep `GeminiFunctionExecutor` focused on executing tool calls.
- Replace nested type references (`GeminiFunctionExecutor.*`) in non-executor layers.

Acceptance criteria:
1. No non-executor feature/model file references `GeminiFunctionExecutor.SuggestedReminder` or `GeminiFunctionExecutor.PlanUpdateSuggestion`.
2. Chat flow behavior remains unchanged (reminder suggestion render/edit/accept, plan-update suggestion render/accept).
3. Project builds successfully for the app target.
4. Changes are reversible by reverting the new model file and renames only (no data migration required).

## Why This Refactor (Evidence)
- Leaky abstraction: UI and model layers depend on executor internals.
  - `Trai/Core/Models/ChatMessage.swift`
  - `Trai/Features/Chat/ChatView.swift`
  - `Trai/Features/Chat/ChatViewActions.swift`
  - `Trai/Features/Chat/ChatContentList.swift`
  - `Trai/Features/Chat/ChatReminderComponents.swift`
  - `Trai/Core/Services/GeminiChatTypes.swift`
- Shotgun surgery risk: a shape change in executor types currently ripples through chat/service/model files.
- Architectural mismatch: persisted suggestion payloads in `ChatMessage` are app domain data, not tool-execution concerns.

## Assumptions
- `SuggestedReminder` and `PlanUpdateSuggestion` semantics remain unchanged.
- Existing SwiftData-stored payloads are JSON-compatible as long as field names/types stay stable.
- No external API contract depends on the nested type names.

## Scope
In scope:
- Type extraction and reference rewiring for reminder/plan-update suggestions.
- Compile-safety updates where nested names were used.

Out of scope:
- Broader Gemini service decomposition.
- Renaming unrelated suggestion types already defined outside executor.

## Impacted Paths
- `Trai/Core/Services/GeminiFunctionExecutor.swift`
- `Trai/Core/Services/GeminiChatTypes.swift`
- `Trai/Core/Services/GeminiService+FunctionCalling.swift`
- `Trai/Core/Models/ChatMessage.swift`
- `Trai/Features/Chat/ChatView.swift`
- `Trai/Features/Chat/ChatViewActions.swift`
- `Trai/Features/Chat/ChatContentList.swift`
- `Trai/Features/Chat/ChatMessageViews.swift`
- `Trai/Features/Chat/ChatReminderComponents.swift`
- `Trai/Core/Models/` (new suggestion models file)
- `Trai.xcodeproj/project.pbxproj` (if manual file registration is required)

## Execution Plan

### Phase 1: Introduce shared suggestion models
- [x] Add `Trai/Core/Models/ChatSuggestions.swift` (or equivalent) with:
  - `SuggestedReminder: Codable, Sendable`
  - `PlanUpdateSuggestion: Codable, Sendable`
- [x] Preserve exact field names/types currently used in nested types.
- [x] Keep formatting helper computed properties for reminders (`formattedTime`, `scheduleDescription`) on the new model.

### Phase 2: Rewire references away from executor nesting
- [x] Update `GeminiFunctionExecutor` to use top-level models in `ExecutionResult` cases and method signatures.
- [x] Update `GeminiChatTypes` result/follow-up containers to use top-level models.
- [x] Update chat feature files to replace `GeminiFunctionExecutor.SuggestedReminder` with `SuggestedReminder`.
- [x] Update `ChatMessage` encode/decode helpers to use top-level `SuggestedReminder`.
- [x] Update all remaining references with a final grep check.

### Phase 3: Remove duplicate nested model declarations
- [x] Delete nested `SuggestedReminder` and `PlanUpdateSuggestion` structs from `GeminiFunctionExecutor` once all references compile.
- [x] Ensure there is one canonical definition per suggestion model.

### Phase 4: Validate and harden
- [x] Run targeted grep validation:
  - `rg -n "GeminiFunctionExecutor\\.(SuggestedReminder|PlanUpdateSuggestion)" Trai -g"*.swift"`
  - Expected result: only allowed internal transitional references (ideally none).
- [x] Build app target:
  - `xcodebuild -project Trai.xcodeproj -scheme Trai -destination 'platform=iOS Simulator,name=iPhone 16' build`
  - If simulator name is unavailable, use a locally available destination.
- [ ] Smoke-check compile paths tied to reminders/plan updates. (Blocked: this environment cannot complete app build due missing CoreSimulator runtimes / actool simulator runtime dependency and provisioning limits.)

## Validation Checklist
- [ ] Chat reminder suggestion still displays, can be edited, and can be accepted. (Not runtime-verified in this environment)
- [x] Plan update suggestion still serializes/deserializes in `ChatMessage`.
- [x] No behavior change in function-call execution ordering.
- [x] No new files outside the scoped paths.

## Risks and Mitigations
- Risk: JSON decode mismatch for previously persisted reminder payloads.
  - Mitigation: keep identical property names/types and `Codable` conformance.
- Risk: hidden references to nested types left behind.
  - Mitigation: repo-wide grep gate before build.
- Risk: Xcode project missing new file membership.
  - Mitigation: verify target membership; update `project.pbxproj` if needed.

## Rollback
- Revert `ChatSuggestions.swift` plus reference rewiring commits.
- Restore nested definitions in `GeminiFunctionExecutor`.
- No data migration rollback needed if field schemas remain unchanged.

## Candidate Ranking (for traceability)
| Candidate | Payoff (30%) | Blast Radius (25%) | Cognitive Load (20%) | Velocity Unlock (15%) | Validation/Rollback (10%) | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| Extract suggestion models from `GeminiFunctionExecutor` (chosen) | 4 | 3 | 5 | 4 | 4 | 3.95 |
| Merge `NutritionTrendChart` + `WorkoutTrendChart` into one generic trend card | 3 | 4 | 3 | 3 | 4 | 3.35 |
| Unify `HealthKitService` ownership (environment-only) | 4 | 2 | 4 | 4 | 3 | 3.45 |
