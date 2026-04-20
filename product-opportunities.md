# Product Opportunities

## Purpose

Working reference for high-ROI feature ideas and why they may matter.

This is intentionally opinionated:

- prioritize repeated user behavior over novelty
- prefer tightening existing loops over adding new surfaces
- avoid ideas that increase complexity without clear day-to-day value

## Current Priority Order

### 1. One-Tap Repeat Food Logging

Why it looks high ROI:

- food logging is one of the highest-frequency actions in the app
- the current flow is strong, but still often starts from scratch
- reducing repeated logging friction should improve retention and lower AI cost

Evidence in the codebase:

- primary food flow is camera/photo/text/manual in [FoodCameraView.swift](/Users/navital/Desktop/Trai/Trai/Features/Food/FoodCameraView.swift)
- entries already support grouped meal sessions via `sessionId` in [FoodEntry.swift](/Users/navital/Desktop/Trai/Trai/Core/Models/FoodEntry.swift)
- the dashboard already renders grouped food sessions in [DailyFoodTimeline.swift](/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DailyFoodTimeline.swift)

Why it may save AI cost:

- repeated or near-repeated meals should not need a fresh analysis every time
- many users likely rotate between a small set of breakfasts, lunches, snacks, and drinks
- cloning a known item or meal session is much cheaper than running food analysis again

### 2. Execute Workout Plans Inside the Live Session

Why it looks high ROI:

- Trai presents itself as plan-first
- the live workout should feel like execution of the plan, not a fresh build-it-yourself flow

Evidence in the codebase:

- workout templates are central in [WorkoutsView.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift)
- the richer template-to-workout path already exists in [WorkoutTemplateService.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/WorkoutTemplateService.swift)
- the live flow currently does not fully use template exercises in [LiveWorkoutViewModel.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/LiveWorkoutViewModel.swift)

### 3. Shorter Onboarding + Better Account Timing

Why it looks high ROI:

- current onboarding is long
- some later steps are already editable elsewhere
- account setup is optional early but blocks valuable actions later

Evidence in the codebase:

- 10-step onboarding in [OnboardingView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift)
- account blockers later in [ChatView.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatView.swift), [AddFoodView.swift](/Users/navital/Desktop/Trai/Trai/Features/Food/AddFoodView.swift), and [WorkoutPlanChatFlow.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanChatFlow.swift)

### 4. Make Reminders Launch Directly Into Action

Why it looks worthwhile:

- reminders are already configurable and scheduled well
- the current tap path is weaker than it could be

Evidence in the codebase:

- scheduling exists in [NotificationService.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/NotificationService.swift)
- notification taps currently mostly route to reminders UI in [NotificationDelegate.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/NotificationDelegate.swift)

### 5. Make Plan Review More Structured

Why it looks worthwhile:

- the review loop already exists
- the product opportunity is improving the quality and clarity of the review outcome

Evidence in the codebase:

- trigger logic in [PlanAssessmentService.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/PlanAssessmentService.swift)
- suggestion application in [ChatViewActions.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatViewActions.swift)

## What Not To Prioritize Yet

- broad social or gamified systems
- another dashboard surface just to display AI recommendations
- heavier adaptive-plan computation without evidence it improves accepted changes
- giant food-search infrastructure before repeated-meal friction is reduced
- more workout analytics before the start-live-summary loop is tighter

## One-Tap Repeat Food Logging

### Product Goal

Let users log common foods or entire repeated meals in one tap, with optional lightweight edits, while reusing known nutrition data instead of invoking AI analysis.

### Important Product Distinction

There are two different versions of this feature:

1. a lightweight `recents` shortcut layer
2. a real `saved food / saved meal memory` system

The first one is useful.
The second one is what makes the feature robust and trustworthy long term.

If Trai is already asking the model to reason about meal composition, but the app only persists a flat display name plus macros, then the system is losing structure that would be valuable for:

- repeated meal logging
- matching similar meals across naming variation
- editing part of a meal instead of the whole thing
- building user-specific canonical meals over time

So if we want this feature to work properly, we should think about the storage layer, not only the UI shortcut.

### UX Principles

- optimize for repeatability, not discovery
- one tap should be enough for the common case
- edits should be optional, not required
- make this feel like a shortcut layer on top of the current logging stack, not a replacement for camera logging

### Best UX

Use three shortcut types, in this order:

1. `Log Again`
   For the exact item or meal session the user logged recently.

2. `Recent Foods`
   Fast chips/cards for individual foods the user logs often.

3. `Recent Meals`
   Fast chips/cards for grouped sessions like a usual breakfast or lunch.

Recommended placement:

- dashboard, near `Today's Food` or inside its header/actions
- food camera entry screen as a pre-capture shortcut row
- widgets later, only after in-app behavior validates the feature

### Phase 1 UX

Start with the simplest useful version:

- show up to 5 recent/frequent shortcuts
- support:
  - one-tap clone of a single `FoodEntry`
  - one-tap clone of a grouped meal `sessionId`
- preserve current timestamp, but copy nutrition, name, serving, emoji, and input metadata
- after tap:
  - immediately log
  - show undo/toast
  - optionally allow “Edit” from the toast or row

This should be much higher ROI than adding a full “saved meals” management surface first.

### Recommended Data Approach

Do not start with a separate “favorites” system.

Use existing data first:

- `FoodEntry` already contains the nutrition payload needed to clone an item
- `sessionId` already groups entries into a meal session
- `DailyFoodTimeline` already understands grouped sessions

Phase 1 can be query-based and derived:

- recent single foods:
  - based on recent entries
  - deduped by normalized name + serving fingerprint
- recent meals:
  - based on recent sessions with 2+ entries
  - deduped by normalized entry-name composition

Possible later data model if Phase 1 works:

- `SavedFoodShortcut`
- `SavedMealTemplate`

But this should only happen after proving usage.

### Better Long-Term Data Model

If we want a proper saved-foods feature, the app likely needs another layer.

Recommended distinction:

- `FoodEntry`
  - an accepted historical log for a specific moment in time
- `SavedFoodMemory`
  - a canonical reusable food or drink the user logs repeatedly
- `SavedMealMemory`
  - a canonical reusable meal composed of multiple saved food components
- `MealComponent`
  - structured component data inside a meal memory

This matters because the AI-generated display name should not be the identity of the food.

Instead:

- `FoodEntry.name` is a display label
- the saved-memory layer owns matching identity
- repeated accepted logs strengthen that identity over time

### Why Names Alone Are Not Enough

LLM-generated labels will drift:

- `chicken rice bowl`
- `grilled chicken bowl`
- `teriyaki chicken rice bowl`

These may all be the same practical meal for the user.

If matching relies on the saved name, the feature will feel inconsistent.

The app should instead build identity from a combination of:

- component composition
- serving pattern
- macro profile
- time-of-day context
- repeated user acceptance

### Recommended Matching Strategy

Treat matching as a confidence system, not a binary exact-name comparison.

For a single reusable food, similarity can come from:

- normalized display name tokens
- serving size and serving quantity
- macro profile rounded into a coarse nutritional signature
- input context like breakfast/snack/drink

For a reusable meal, similarity should prioritize:

1. component composition
2. approximate total macro signature
3. time-of-day pattern
4. name similarity

This ordering is important because the meal name is the least stable part.

### Structured Components

If Trai is going to reason about multiple meal components, those components should be saveable.

A good future shape would be:

- `MealComponent`
  - `displayName`
  - `normalizedName`
  - `category`
    - protein
    - carb
    - fat
    - vegetable
    - sauce
    - drink
    - other
  - `servingQuantity`
  - `servingUnit`
  - `calories`
  - `proteinGrams`
  - `carbsGrams`
  - `fatGrams`
  - optional `confidence`

Then:

- a repeated breakfast can be matched as `eggs + toast + coffee`
- even if AI renames it
- and the user can reuse the whole meal or only one part of it

### Source Of Truth

The important rule should be:

- only accepted user logs strengthen saved memories
- raw AI output alone should not create canonical meal identity

This avoids letting model variance pollute the reusable-food layer.

Suggested flow:

1. AI proposes a meal
2. user accepts or edits it
3. accepted result is stored as a historical `FoodEntry`
4. background matching logic decides whether it:
   - strengthens an existing saved memory
   - creates a new saved memory candidate
   - stays only as a one-off log

### Suggested Architecture

For a proper implementation, introduce a service layer such as:

- `FoodMemoryService`

Responsibilities:

- derive and update canonical saved foods and meals from accepted logs
- compute similarity between a new accepted log and existing saved memories
- keep alias/display names for the same canonical memory
- expose:
  - recent exact clones
  - likely saved foods
  - likely saved meals

Possible helper concepts:

- `FoodMemoryFingerprint`
- `MealMemoryFingerprint`
- `FoodSimilarityScore`
- `MealSimilarityScore`

### Recommended Rollout

#### Phase 1

- exact clone shortcuts from accepted historical entries and sessions
- no canonicalization required

#### Phase 2

- introduce canonical saved-food and saved-meal memory models
- cluster accepted logs into reusable memories
- use conservative matching thresholds

#### Phase 3

- persist structured meal components
- support component-aware meal similarity and partial reuse
- allow explicit user actions like:
  - rename saved meal
  - pin meal
  - save just one component

### UX Recommendation

The best UX is likely a combination of:

- `Log Again`
  - exact recent accepted log
- `Usual Foods`
  - canonical saved foods
- `Usual Meals`
  - canonical saved meals built from repeated accepted sessions

That gives users:

- immediate convenience
- eventually smarter memory
- and a system that feels consistent even when AI wording varies

### Suggested Implementation Plan

#### Step 1: Add derivation helpers, not new models

Introduce a small service, for example:

- `RecentFoodShortcutService`

Responsibilities:

- load recent `FoodEntry` rows for a window like 21 to 30 days
- derive:
  - recent single-food shortcuts
  - recent meal-session shortcuts
- rank by:
  - recency
  - repeat count
  - time-of-day relevance

Outputs should be compact view models, not SwiftData models.

Example outputs:

- `RecentFoodShortcut`
- `RecentMealShortcut`

### Step 2: Implement cloning from existing entries

For a single-food shortcut:

- create a new `FoodEntry`
- copy:
  - `name`
  - `calories`
  - `proteinGrams`
  - `carbsGrams`
  - `fatGrams`
  - `fiberGrams`
  - `sugarGrams`
  - `servingSize`
  - `servingQuantity`
  - `emoji`
- set:
  - new `id`
  - `loggedAt = now`
  - `inputMethod = .manual` or a new shortcut-like value later if needed
  - no image reuse in Phase 1

For a meal-session shortcut:

- generate a new session UUID
- clone all entries from the source session
- preserve relative `sessionOrder`
- apply the new `loggedAt` to all items in the cloned session

### Step 3: Surface shortcuts in one place first

Best first placement:

- inside or just above `DailyFoodTimeline`

Why:

- close to the existing food log
- low navigation overhead
- easiest place for users to understand “repeat this meal”

Suggested first UI:

- horizontal chip row or compact cards
- separate sections only if needed:
  - `Log Again`
  - `Recent Meals`
  - `Recent Foods`

Keep it compact and card-system-aligned.

### Step 4: Instrument usage carefully

Track:

- shortcut shown
- shortcut tapped
- type:
  - single food
  - full meal
- follow-up edit performed
- undo/delete shortly after

This is important because the feature is only worth expanding if:

- it gets used often
- the undo/delete rate is not high
- it reduces AI-triggered food analyses

### Step 5: Only then consider expansion

If Phase 1 works, possible Phase 2 additions:

- time-of-day smart sorting
- “pin this meal”
- widget support for user-specific meal shortcuts
- quick quantity adjust before save
- meal-level macro preview before tap

## Technical Notes

### Deduping Heuristics

For individual-food shortcuts:

- normalize name
  - lowercase
  - trim whitespace
  - collapse punctuation
- include serving size/quantity when available

For meal-session shortcuts:

- sort by `sessionOrder`
- normalize names
- hash the list of normalized names plus approximate quantities

The goal is “good enough grouping,” not perfect nutrition identity.

### Cost Strategy

Treat this feature as a cache hit on known user data.

Do not:

- re-run AI when the user taps a remembered meal
- upload the old meal image again
- attach the feature to backend cost unless the user explicitly edits via AI afterward

### Risk Areas

- users may want to adjust quantity
- meal identity can drift over time
- some remembered items may become stale or misleading

Mitigations:

- make edits easy after logging
- prioritize recent over old shortcuts
- allow long-press or overflow menu for `Edit Before Save` later if needed

## Suggested Build Order

1. derive recent single-food + meal-session shortcuts
2. add one-tap clone flow on dashboard food area
3. add tracking and measure usage/undo rate
4. expand to food entry surfaces if the numbers justify it

## Success Criteria

This idea is working if:

- repeated food logs shift from camera/AI to shortcut logging
- users log more often overall
- AI food analysis volume per active logger decreases
- undo/delete after shortcut logging stays low
- users continue to use camera logging for novel meals while using shortcuts for repeat meals
