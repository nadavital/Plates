# Product Issues Audit

Date: 2026-04-12
Project: Trai

## Purpose

This document captures the issues found during the investigation pass, the likely root cause in the current codebase, and the recommended fix direction. It is ordered roughly by implementation priority.

## In Progress Fix Batch

These are the current remaining workout-focused issues being tackled in code now:

1. Keep extending arbitrary workout split support beyond the plan editor into all workout surfaces.
2. Add richer specialized experiences only where they provide clear value over the general workout workspace.

## Issues

### 1. Add a specific Apple Health step during onboarding

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Profile/SettingsView.swift`
- Problem:
  - Onboarding has no dedicated HealthKit step. Health sync appears later as a settings preference, which does not match the desired onboarding experience.
- Fix direction:
  - Add a dedicated onboarding step for Health sync and request permissions intentionally there.
  - Persist the user’s choice into the profile during onboarding completion.

### 2. Clarify `Build Muscle` vs `Body Recomposition`

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/GoalCardComponents.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Models/UserProfile.swift`
- Problem:
  - The current copy does not clearly explain that muscle gain implies a surplus while recomposition is closer to maintenance with slower body-composition change.
- Fix direction:
  - Update goal descriptions and supporting copy in onboarding and plan-adjustment surfaces.
  - Consider adding a one-line decision hint under the goal grid.

### 3. Improve onboarding upsell copy and de-emphasize the standard-plan CTA

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/PlanGenerationChoiceSheet.swift`
- Problem:
  - The copy is serviceable but generic, and `Continue with Standard Plan` is visually too strong as a full-width CTA.
- Fix direction:
  - Rewrite the comparison copy to be more explicit about value.
  - Make the standard-plan action feel secondary in size and hierarchy.

### 4. Show Sign in with Apple before plan choice

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Account/AccountSetupView.swift`
- Problem:
  - Authentication is reactive and modal, not a deliberate onboarding step.
- Fix direction:
  - Add account setup as a first-class onboarding step before monetization/plan choice.

### 5. Support more workout types and more flexible workout-plan creation

- Status: Improved in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Core/Models/WorkoutPlanGenerationRequest.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Services/AIWorkoutPlanPrompts.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Models/WorkoutPlanDefaults.swift`
- Problem:
  - Inputs now cover more flexibility than before, the questionnaire is shorter, and cardio/flexibility-first fallback plans are better supported.
  - The app now has a general live-workout workspace for arbitrary sessions with notes, freeform activity items, and Trai chat context, plus improved history/detail/summary support for those sessions.
  - General-session workflows now also support lightweight workout goals and note-based progression surfaces, so arbitrary activities can be tracked without forcing PR/readiness-style logging.
  - The workout tab now includes a broader goals-and-signals section so users can review active goals and recent note-based progress without opening an individual workout first.
  - Those workout-tab goals now drill into a dedicated detail view with related sessions, momentum summaries, and recent note-based storytelling, which makes the system feel more like a real tracking layer instead of a summary-only card.
  - Related goals are now surfaced more explicitly inside completed workout detail and post-workout summary flows, so past sessions can more clearly answer what they were contributing toward.
  - Imported Apple Watch workouts can now be annotated afterward and are starting to feed the same goals/signals and chat-coaching context, instead of being treated as disconnected history.
  - The dashboard trend layer now emphasizes universal session metrics like workouts, items, minutes, and session types, while only showing strength volume when it is actually relevant.
  - The proposal and completed-workout detail surfaces now summarize flexible sessions more naturally, so mixed/custom plans are less likely to be framed as "missing exercises."
  - The custom session quick-start, plan overview/history cards, and planner question copy have also been softened so custom modalities are less likely to feel like a strength flow with an escape hatch.
  - The remaining gap is mostly polish and breadth: more specialized modality affordances where useful, and a few more legacy surfaces still worth reviewing for strength-first wording.
- Fix direction:
  - Keep broadening prompt/output expectations for cardio/flexibility-first plans.
  - Preserve and display custom focus areas end to end.
  - Use the general workout workspace as the default fallback for any session type.
  - Keep building lightweight progression on top of passive data, recent notes, and optional goals rather than introducing mandatory manual scoring.
  - Add specialized overlays only where they materially improve logging quality, such as structured cardio intervals or strength sets.

### 6. `Use This Plan` does not exit onboarding workout-plan creation

- Status: Fixed in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanChatFlow.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanProposalCard.swift`
- Problem:
  - Accepting a plan only flips local accepted state. Onboarding users expect that action to finish and return to onboarding immediately.
- Fix direction:
  - Make `Use This Plan` complete onboarding workout-plan selection directly when `isOnboarding == true`.

### 7. Save onboarding state if the user leaves mid-flow

- Status: Improved in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView+Completion.swift`
- Problem:
  - Partial onboarding data is only held in `@State`.
- Fix direction:
  - Persist a lightweight onboarding draft.
  - Restore the last in-progress step and entered values on relaunch.

### 8. Default onboarding weight to `lbs`

- Status: Fixed in current pass
- Severity: Low
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift`
- Problem:
  - New onboarding sessions default to metric weight.
- Fix direction:
  - Change the default onboarding state to imperial weight units.

### 9. Goal selection scroll feels sticky/awkward

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/GoalsStepView.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/GoalCardComponents.swift`
- Problem:
  - Full-card interactive goal buttons compete with scroll gestures.
- Fix direction:
  - Remove or soften custom press gesture handling on these cards.
  - Validate scroll/tap interaction on device.

### 10. Recomposition plan review can imply the plan “fits” while forecasting slight gain

- Status: Improved in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Core/Models/NutritionPlan.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Services/AIPlanPrompts.swift`
- Problem:
  - Recomposition is modeled near maintenance, but the surfaced weekly-change messaging previously felt contradictory to weight-loss expectations.
- Fix direction:
  - Tighten prompt guidance and UI wording so recomposition messaging is more explicit.
  - Keep validating that generated assistant copy stays aligned with the more careful near-maintenance framing.

### 11. Plan adjustment flows ask too many questions

- Status: Improved in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Core/Services/AIPlanPrompts.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Services/AIWorkoutPlanPrompts.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanChatFlow.swift`
- Problem:
  - Both nutrition and workout refinement prompts previously biased toward more clarifying questions. That bias has been reduced, but the experience still needs validation for edge cases.
- Fix direction:
  - Prefer direct proposals when intent is already clear.
  - Keep trimming mandatory questionnaire length for workout creation where it is still not pulling its weight.

### 12. `Tap to edit` on the onboarding daily-targets card does not do anything

- Status: Fixed in current pass
- Severity: Low
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Onboarding/PlanReviewCards.swift`
- Problem:
  - The UI implies a direct action, but there is no edit affordance behind the label.
- Fix direction:
  - Make it an actual button that focuses the first editable field or opens a more explicit editing mode.

### 13. 5-macro layouts do not rebalance well

- Status: Improved in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Profile/ProfileView+Cards.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DashboardCards.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DashboardHelperComponents.swift`
- Problem:
  - The worst cases have been rebalanced and label overflow was tightened, but these layouts still need device-level visual verification.
- Fix direction:
  - Keep the balanced multi-row layouts.
  - Validate spacing and edge padding on device, especially with all 5 macros enabled.

### 14. Meal suggestion edit saves the right data but the chat UI does not reflect it

- Status: Fixed in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatMealComponents.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift`
- Problem:
  - Edited suggestions are recreated with a new id, while the chat state is keyed to the original suggestion id.
- Fix direction:
  - Preserve the original suggestion id and metadata when editing.

### 15. Consecutive `Log` taps should only log once

- Status: Fixed in current pass
- Severity: Medium
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift`
- Problem:
  - There is already a processing guard, but it can be made more robust by also checking logged-state before insert.
- Fix direction:
  - Keep the processing guard and add an already-logged guard before writing a new `FoodEntry`.

### 16. Widget macro totals do not update after normal in-app food logging

- Status: Fixed in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Core/Services/WidgetDataProvider.swift`
  - `/Users/navital/Desktop/Trai/Trai/TraiApp.swift`
  - normal food-save flows under `/Users/navital/Desktop/Trai/Trai/Features/Food`
- Problem:
  - Widgets refresh on background or widget-intent flows, but not after common in-app food saves.
- Fix direction:
  - Refresh widget data from normal app food-save and food-edit paths.

### 17. Sugar tracking is conceptually supported, but some save paths drop it

- Status: Improved in current pass
- Severity: High
- Evidence:
  - `/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift`
  - `/Users/navital/Desktop/Trai/Trai/Features/Food/AddFoodView.swift`
  - `/Users/navital/Desktop/Trai/Trai/Core/Models/FoodEntry.swift`
- Problem:
  - The model supports sugar, but some UI flows never assign it to `FoodEntry`.
- Fix direction:
  - Ensure every food-save path stores all available nutrient fields, not just the currently displayed ones.

## Recommended Next Batch After Current Fixes

1. Validate the new general workout workspace and dashboard trend changes on device and refine any rough edges in live session editing.
2. Decide whether progression and readiness should remain explicitly strength/muscle-based, or whether they should get first-class modality-aware models.
3. Review the last legacy workout surfaces for any lingering strength-first wording or icons.
4. Run visual verification on 5-macro layouts across dashboard/profile/onboarding.
5. Audit any remaining nutrient save paths so sugar/fiber handling is truly consistent end-to-end.
6. Verify the new onboarding account/Health steps and workout-plan acceptance flow on device/simulator.
