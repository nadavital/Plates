# Trai Free/Pro Monetization and Upsell Execution Plan

## Goal

Ship a simple, low-risk monetization model that protects Gemini spend without making Pro feel metered.

Target product model:

- `Free`: no AI features at all
- `Pro ($3.99/month)`: all AI features included
- Backend quotas remain hidden and generous for abuse protection only

This plan assumes:

- we do **not** want to profit-maximize
- we do **not** want to subsidize free AI usage
- we do **not** want paying users thinking about "AI units"
- we do want a premium, brand-forward upsell flow that sells Trai as a smart coach powered by the lens identity

## Product Decisions

### 1. Free Tier

Free users should be able to use Trai as a manual tracking app.

Included:

- onboarding
- dashboard
- workout tracking
- manual food logging
- weight tracking
- HealthKit-connected history and metrics
- widgets, reminders, live workout, and normal non-AI app flows

Excluded:

- chat with Trai
- food photo analysis
- AI food parsing / AI meal understanding
- nutrition plan generation
- nutrition plan refinement/review with Trai
- workout plan generation
- workout plan refinement/review with Trai
- exercise analysis/photo analysis
- any Gemini-backed assistant flow

### 2. Pro Tier

Pro should feel like "all of Trai unlocked."

Included:

- unlimited-feeling access to all AI features
- full Trai chat
- food photo analysis
- personalized nutrition planning
- workout plan creation and refinement
- AI exercise understanding
- future premium AI surfaces by default

Important:

- do not show user-facing usage counters
- do not show "units left"
- do not show monthly budget language
- do not make normal Pro users feel constrained

### 3. Hidden Fair Use

Backend should still enforce generous caps to protect unit economics.

Rules:

- limits are server-side only
- limits are not marketed in the UI
- limits are tuned high enough that normal users will never see them
- if a user does hit them, the app shows a temporary service/fair-use message rather than an in-product meter

### 4. Trials

Recommendation for v1:

- do **not** offer a trial initially
- let the free manual-tracking app serve as the product trial

If we ever add a trial:

- use Apple-managed introductory offers only
- do not build a custom backend/email-based trial system

Reason:

- Apple subscription-group eligibility is a much stronger anti-abuse mechanism than email or CloudKit identity
- email is weak because of Hide My Email and disposable accounts
- CloudKit data identity is not a reliable trial-enforcement boundary

## Core UX Strategy

### Free Experience

Free should not feel broken. It should feel intentionally useful.

Messaging:

- "Track your food, workouts, and progress for free"
- "Upgrade to unlock Trai's AI coaching and planning"

Free users should always understand:

- the app works without AI
- AI is the premium upgrade
- upgrading unlocks an actual new level of help, not just extra capacity

### Pro Experience

Pro should feel calm and premium.

Messaging:

- "Unlock Trai"
- "Your adaptive coach for food, training, and planning"

Avoid:

- quota bars
- budget language
- "X requests left"
- transactional/cheap-feeling paywall copy

### Upsell Triggers

Primary upsell moments:

- opening Chat tab as a free user
- tapping "Chat with Trai" from the dashboard
- trying to analyze food from camera/add food flows
- trying to create a nutrition plan in onboarding
- trying to create/refine a workout plan
- trying to review plans with Trai from profile/chat shortcuts

Secondary upsell moments:

- dedicated Settings/Profile subscription area
- occasional dashboard card for free users

## The Upsell Surface

We should build a dedicated branded paywall, not just a settings section with product rows.

### Visual Direction

Use the existing Trai lens and warm palette.

Primary design ingredients:

- large `TraiLensView` hero
- warm gradient background using Trai oranges/corals/embers
- premium but calm spacing
- concise, confidence-building copy
- one clear CTA
- subdued secondary "Not now" dismissal

Relevant brand building blocks:

- [TraiLensView.swift](/Users/navital/Desktop/Trai/Trai/Shared/Components/TraiLens/TraiLensView.swift)
- [TraiColors.swift](/Users/navital/Desktop/Trai/Trai/Shared/DesignSystem/TraiColors.swift)
- [TraiBackgrounds.swift](/Users/navital/Desktop/Trai/Trai/Shared/DesignSystem/TraiBackgrounds.swift)

### Paywall Content

Headline options:

- `Unlock Trai`
- `Your adaptive coach, unlocked`
- `Turn Trai into your personal coach`

Subheadline:

- `Get AI coaching, food analysis, and personalized plans built around your goals.`

Core benefit bullets:

- `Chat with Trai anytime for guidance`
- `Analyze food photos in seconds`
- `Create and refine nutrition plans`
- `Build workouts tailored to your goals`

Price block:

- `Trai Pro`
- `$3.99 / month`
- `Cancel anytime`

Primary CTA:

- `Start Pro`
- or `Unlock Pro`

Secondary actions:

- `Restore Purchases`
- `Manage Subscription` when applicable
- dismiss action

Legal/support footer:

- privacy / terms links
- restore purchases
- App Store managed billing copy

### Paywall Behavior

Present as a sheet/full-screen cover depending on entry point:

- full-screen for onboarding AI moments
- sheet for in-app gated actions

The paywall should accept a source/context so copy can adapt:

- chat
- food camera
- nutrition plan
- workout plan
- settings
- dashboard

This lets us personalize the supporting line:

- `Unlock chat coaching from Trai`
- `Unlock food photo analysis`
- `Unlock personalized planning`

## Architecture Changes

## 1. Monetization Rules

Update the shared entitlement model so free means "no paid AI access."

Relevant files:

- [MonetizationModels.swift](/Users/navital/Desktop/Trai/Trai/Core/Models/MonetizationModels.swift)
- [MonetizationService.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/MonetizationService.swift)
- [BillingService.swift](/Users/navital/Desktop/Trai/Trai/Core/Services/BillingService.swift)
- [config.mjs](/Users/navital/Desktop/Trai/Backend/src/config.mjs)
- [monetization.mjs](/Users/navital/Desktop/Trai/Backend/src/monetization.mjs)

Changes:

- set `SubscriptionPlan.free.monthlyAIUnits` to `0`
- keep Pro/Elite hidden limits server-side
- remove user-facing quota copy for non-debug builds
- add premium gating semantics:
  - `free` cannot use any AI feature
  - `pro`, `elite`, `developer` can use AI
- keep backend hidden quotas for paid plans only

Desired behavior:

- free users are blocked before any Gemini-backed action begins
- Pro users proceed normally
- over-limit states for paid users are exceptional and phrased as temporary service/fair-use pauses, not metering

## 2. Dedicated Premium Gate Model

Introduce a reusable paywall presentation model.

Suggested new types:

- `PremiumFeatureGateSource`
- `PremiumFeatureDescriptor`
- `PaywallContext`

Suggested source enum cases:

- `chat`
- `foodAnalysis`
- `nutritionPlan`
- `workoutPlan`
- `exerciseAnalysis`
- `settings`
- `dashboard`

Responsibilities:

- identify which feature was requested
- decide title/subtitle/benefit emphasis
- give analytics context later

## 3. Paywall UI

Add a new reusable premium screen.

Suggested new file(s):

- `Trai/Features/Monetization/ProUpsellView.swift`
- `Trai/Features/Monetization/ProUpsellModel.swift`
- optional helper components:
  - `ProUpsellHero.swift`
  - `ProUpsellBenefitList.swift`
  - `ProUpsellCTASection.swift`

Design requirements:

- use `TraiLensView` as hero
- visually consistent with onboarding polish
- strong but not shouty color usage
- mobile-first, one-screen readable
- no cluttered comparison table for v1

## 4. Centralized Feature Gating

We should not sprinkle random `if plan == .free` checks everywhere.

Create a shared gate helper that can be called from any AI entry point.

Suggested responsibility:

- ask `MonetizationService` for access decision
- if blocked, return a `PaywallContext`
- caller presents the paywall instead of starting AI

Possible shape:

- `PremiumAccessController`
- or helper on `MonetizationService`

## 5. App Entry Points To Gate

These are the high-priority AI entry points in the current repo.

### Chat

Files:

- [ChatView.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatView.swift)
- [ChatViewMessaging.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatViewMessaging.swift)
- [DashboardHelperComponents.swift](/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DashboardHelperComponents.swift)

Behavior:

- free user opening Chat tab or sending first message gets the paywall
- dashboard "Chat with Trai" card should upsell free users instead of routing straight into AI chat

### Food AI

Files:

- [FoodCameraView.swift](/Users/navital/Desktop/Trai/Trai/Features/Food/FoodCameraView.swift)
- [AddFoodView.swift](/Users/navital/Desktop/Trai/Trai/Features/Food/AddFoodView.swift)
- [LogFoodTextIntent.swift](/Users/navital/Desktop/Trai/Trai/Core/Intents/LogFoodTextIntent.swift)

Behavior:

- manual food logging remains available
- AI food analysis is Pro-only
- free users see paywall before image analysis begins

### Nutrition Plan AI

Files:

- [OnboardingView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift)
- [PlanReviewStepView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/PlanReviewStepView.swift)
- [OnboardingView+PlanGeneration.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView+PlanGeneration.swift)
- [PlanChatView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/PlanChatView.swift)

Behavior:

- free users can complete onboarding
- free users do not get AI-generated nutrition plans
- instead, show a branded paywall when they reach the planning step
- optionally offer a lightweight fallback summary without AI generation

### Workout Plan AI

Files:

- [WorkoutPlanDecisionView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/WorkoutPlanDecisionView.swift)
- [WorkoutPlanChatFlow.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutPlanChatFlow.swift)
- [ProfileView+Cards.swift](/Users/navital/Desktop/Trai/Trai/Features/Profile/ProfileView+Cards.swift)

Behavior:

- free users can track workouts
- free users cannot create AI workout plans
- tapping plan creation/customization triggers the paywall

### Exercise Analysis

Files:

- [AddCustomExerciseSheet.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/AddCustomExerciseSheet.swift)
- [ExerciseListView.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/ExerciseListView.swift)

Behavior:

- free users can still add exercises manually
- AI exercise analysis/photo analysis is Pro-only

## 6. Settings/Profile Cleanup

Current Settings currently exposes internal billing/quota detail, which is useful for development but not right for shipping.

Relevant file:

- [SettingsView.swift](/Users/navital/Desktop/Trai/Trai/Features/Profile/SettingsView.swift)

Shipping goals:

- show simple plan state
- show `Upgrade to Pro` for free users
- show `Restore Purchases`
- show `Manage Subscription` for paying users
- remove visible usage/quota text in release

Debug-only:

- keep quota sync/debug surfaces behind `#if DEBUG`

## 7. Backend Policy

Relevant files:

- [config.mjs](/Users/navital/Desktop/Trai/Backend/src/config.mjs)
- [monetization.mjs](/Users/navital/Desktop/Trai/Backend/src/monetization.mjs)
- [routes.mjs](/Users/navital/Desktop/Trai/Backend/src/routes.mjs)

Changes:

- set free plan limit to `0`
- keep Pro hidden limit generous
- retain admin credits/reset for support
- change backend error semantics for paid overuse from "quota exhausted" to a softer service/fair-use pause message if desired

Potential hidden defaults:

- `free = 0`
- `pro = 1200`
- `elite = 2400`

These remain operational numbers only, not marketing copy.

## 8. Trial Policy

Recommended v1:

- no trial
- free manual app + Pro AI upgrade

If later needed:

- use App Store intro offer only
- backend records Apple-linked user/account history for support visibility
- do not rely on CloudKit profile presence or email uniqueness for trial enforcement

Why:

- CloudKit data is tied to the user’s iCloud/app data, not a strong monetization identity
- Sign in with Apple `appleUserID` is a better backend identity
- App Store subscription-group intro eligibility is better than any custom email rule

## 9. Analytics

Even though users should not see metering, we still need internal analytics.

Track internally:

- paywall impressions by source
- paywall conversion rate by source
- restore purchase taps
- plan state distribution
- AI request counts by paid users
- hidden quota/fair-use limit hits

Per-user support visibility should include:

- plan
- subscription status
- recent purchases/notifications
- current backend quota period
- recent AI usage

Do not expose this to end users in the product UI.

## Execution Order

## Phase 1: Product Rule Lock-In

1. Set free plan AI access to zero.
2. Remove user-facing quota language from the intended production UX.
3. Decide no-trial v1 policy and document it in repo docs.

Acceptance:

- free users cannot use any AI feature
- Pro users still can
- no shipped UI suggests visible metering

## Phase 2: Shared Gating Infrastructure

1. Add paywall context/source types.
2. Add centralized premium gate helper.
3. Add a shared presentation hook for upsell screens.

Acceptance:

- any AI feature can trigger the same paywall with different context
- gating logic is not duplicated across many views

## Phase 3: Build Branded Upsell

1. Create the branded Pro upsell screen.
2. Hook it up with StoreKit purchase/restore/manage actions.
3. Add source-specific copy variants.

Acceptance:

- the paywall looks intentional and on-brand
- purchase flow works from the paywall
- restore/manage flows are available

## Phase 4: Gate AI Entry Points

1. Chat
2. Food AI
3. Nutrition plan generation
4. Workout plan generation/refinement
5. Exercise analysis

Acceptance:

- free users are intercepted before Gemini requests start
- manual tracking still works
- no hidden AI path remains accessible to free users

## Phase 5: Settings/Dashboard Polish

1. Simplify Settings billing UI for release
2. Add free-user upgrade affordances in dashboard/profile
3. Keep debug controls internal-only

Acceptance:

- no production-facing quota UI
- upgrade entry point exists without being obnoxious

## Phase 6: QA

Test matrix:

- free user fresh install
- free user completes onboarding
- free user attempts every AI entry point
- Pro user purchase from paywall
- Pro user restore purchase
- Pro user manage subscription
- paid user hidden fair-use overflow behavior
- sign in/out and backend bootstrap consistency

Acceptance:

- free tier always remains useful
- Pro unlock is obvious and smooth
- Pro feels unlimited in normal use

## Suggested Copy Direction

### Free User Messaging

- `Track your food, workouts, and progress for free.`
- `Upgrade to unlock Trai's AI coaching, food analysis, and personalized plans.`

### Pro Messaging

- `Unlock Trai`
- `Get AI coaching, food analysis, and personalized plans that adapt to your goals.`
- `Everything that makes Trai feel like a personal coach.`

### Hard Edge Case Messaging

Only for rare backend fair-use trips:

- `AI is temporarily unavailable for this account right now. Please try again later.`

Avoid:

- `You ran out of units`
- `You used your monthly allowance`
- `You have X remaining`

## Definition of Done

This work is done when:

- free users have no AI access
- free users can still use Trai as a manual tracker
- Pro users see a premium, branded upsell flow
- Pro users are not shown quota/usage UI
- all major AI entry points are gated consistently
- backend limits remain hidden safety rails
- StoreKit purchase/restore/manage flows work from the paywall
- the app messaging clearly distinguishes manual tracking from AI coaching

