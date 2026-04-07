# Trai Public Testing Readiness Plan

This document captures the work needed to move Trai from a developer build to a public-testing-ready product.

Scope:
- External TestFlight / public beta readiness
- Subscription billing and AI cost protection
- Core app release hardening
- App Store Connect / Apple compliance setup

Assumptions based on the current repo:
- The app now supports Sign in with Apple, StoreKit purchase scaffolding, and backend session/bootstrap flows.
- The backend now exists in `Backend/` and owns entitlement, quota, App Store notification handling, and Gemini proxy paths.
- Production rollout still requires real App Store Connect product setup, production secrets, and ops hardening.
- The app uses CloudKit-backed app data for product data, but subscription and AI access should now defer to backend state.
- The app already has substantial product functionality, including widgets, HealthKit, live workouts, camera flows, and AI-powered features.

Current launch pricing assumption:

- `Trai Pro`: `3.99/month`
- Free trial/free usage should remain intentionally small
- Pricing is designed to avoid subsidizing Gemini usage, not to maximize margin

## 1. Launch Goal

Trai is ready for public testing when all of the following are true:

- A new user can install the app, onboard, and use core non-AI features without a crash or blocker.
- Paid and free users are clearly differentiated through subscriptions and entitlements.
- AI usage is enforced server-side so Gemini spend cannot scale uncontrolled.
- Widget and deep-link flows work reliably on cold launch and warm launch.
- The app meets Apple beta distribution requirements, privacy requirements, and subscription disclosure requirements.
- We have basic operational visibility into crashes, AI spend, subscription state, and quota failures.

## 2. Current Gaps Observed In This Repo

These are the highest-signal gaps observed during review:

- No StoreKit / subscription code exists in the app.
- No backend exists for AI proxying, entitlements, metering, quota enforcement, or admin operations.
- Gemini is called directly from the app in:
  - `Trai/Core/Services/GeminiService.swift`
  - `Trai/Core/Services/GeminiService+FunctionCalling.swift`
  - `Trai/Core/Services/GeminiService+FunctionCallingHelpers.swift`
- The app depends on a local `Secrets.swift` for the Gemini API key.
- The app defines `trai://` routes in `Shared/Contracts/AppRoute.swift`, but URL scheme registration was not found in project Info.plist settings.
- No `PrivacyInfo.xcprivacy` file is present.
- Deployment targets are set above the locally supported SDK range:
  - app target: `26.1`
  - widget target: `26.2`
- `remote-notification` background mode is declared, but APNs registration/handling was not found.
- Gemini debug logging is verbose and should not ship enabled in release builds.
- No crash reporting / production analytics stack is present.

## 3. Workstreams

The work breaks into 7 workstreams:

1. Release blockers in the iOS app
2. Billing and entitlement system
3. Backend for AI proxying and quota enforcement
4. Product and UX changes for subscriptions and limits
5. Reliability, monitoring, and support tooling
6. Apple compliance and App Store Connect setup
7. QA and staged rollout

## 4. Priority Order

Recommended execution order:

1. Fix app release blockers
2. Build backend identity + entitlement + quota foundation
3. Add StoreKit subscriptions in the app
4. Route Gemini through backend and enforce limits
5. Add paywall, quota UI, and degraded-state UX
6. Add monitoring, crash reporting, and admin tools
7. Complete App Store Connect setup and external TestFlight prep
8. Run internal beta, then limited external beta, then broader public testing

## 5. Detailed Plan

### A. App Release Blockers

These should be fixed before any real external beta.

- Register the `trai://` custom URL scheme in app Info settings.
  - Reason: widget and deep-link entry points depend on `Shared/Contracts/AppRoute.swift`.
  - Validate:
    - widget "Log Food" opens correctly on cold launch
    - workout deep links open correctly
    - chat deep link opens correctly

- Fix deployment targets to a real supported iOS version.
  - Choose an actual minimum supported version and align:
    - app target
    - widget target
    - tests where needed
  - Validate:
    - clean build
    - archive
    - install on intended minimum supported iOS version

- Add `PrivacyInfo.xcprivacy`.
  - Include required-reason API declarations for APIs the app uses.
  - Review app and future SDKs for manifest requirements.
  - Validate:
    - upload passes privacy manifest checks

- Remove or justify unused app capabilities / background modes.
  - Review `remote-notification`
  - Review entitlements and declared capabilities against actual features
  - Validate:
    - plist and capability set match shipped functionality

- Disable verbose Gemini logging in release builds.
  - No prompt / response dumps in production.
  - Keep structured error logging only.
  - Validate:
    - release build does not print model prompts/responses

- Confirm real app icons, launch assets, and branding are final.
  - App icon
  - Widget icon / extension naming
  - Any placeholder copy in onboarding/paywall

### B. Billing And Entitlements

This is mandatory if public testers will hit paid AI features.

- Add StoreKit 2 subscription support.
  - Load products
  - Purchase flow
  - Restore purchases
  - Current entitlement lookup
  - Upgrade / downgrade handling
  - Billing retry / expired state handling

- Define subscription products in App Store Connect.
  - Suggested structure:
    - Free tier: limited AI usage
    - Pro tier: higher monthly quota
    - Optional higher tier: power-user quota

- Decide monetization policy for AI features.
  - Choose what counts against quota:
    - text chat
    - image analysis
    - plan generation
    - function-calling / long sessions
  - Choose whether quota is:
    - requests-based
    - token-based
    - cost-weighted
    - hybrid

- Build entitlement states in product logic.
  - Free
  - Trial
  - Active paid
  - Grace period
  - Billing retry
  - Expired / revoked

- Add mandatory subscription UX.
  - Paywall
  - Restore purchases button
  - Manage subscription button
  - Clear explanation of what the subscription includes
  - Clear explanation of what happens when quota is reached

- Add subscription copy and legal disclosures.
  - Price
  - Billing cadence
  - Trial terms
  - Auto-renewal language
  - Privacy Policy
  - Terms of Use / EULA

Acceptance criteria:

- A tester can buy, restore, renew, expire, and recover a subscription in TestFlight.
- The app correctly reflects entitlement state after app relaunch.
- Locked features stay locked when entitlement is inactive.

### C. Backend For AI Proxying, Identity, And Quota Enforcement

This is the most important architectural gap.

Do not rely on client-side checks alone for AI cost control.

- Build a backend service that sits between the app and Gemini.
  - The app should call your server
  - The server should call Gemini
  - Gemini credentials should never be the source of truth on-device

- Add user identity.
  - Recommended: Sign in with Apple
  - Minimum requirement: stable server-recognized user identity
  - Need to support:
    - reinstall
    - new device
    - restoring purchases
    - quota continuity

- Add entitlement persistence on the server.
  - Store subscription state
  - Store source transaction identifiers
  - Store current plan / tier
  - Store quota policy version

- Add usage metering.
  - Per request:
    - user id
    - feature
    - model
    - input tokens
    - output tokens
    - image count
    - latency
    - estimated cost
    - success/failure
  - Aggregate:
    - daily usage
    - monthly usage
    - spend by user
    - spend by feature

- Add quota enforcement.
  - Hard cap by billing period
  - Optional daily cap
  - Optional abuse cap for rapid bursts
  - Different caps for different feature types

- Add anti-abuse controls.
  - Rate limiting
  - Burst limiting
  - IP / device anomaly detection if needed
  - Kill switch to disable high-cost features
  - Model fallback or cheap-mode fallback

- Add server-side policy controls.
  - Per-tier limits
  - Per-feature weights
  - Temporary promo access
  - Manual overrides

- Add App Store subscription validation and lifecycle handling.
  - Transaction verification
  - Renewal updates
  - Cancellation / revocation handling
  - Billing retry / grace period updates
  - Refund handling

- Add App Store Server Notifications integration.
  - Keep entitlement state accurate even when the app is not open

Acceptance criteria:

- All AI requests go through the backend.
- A user over quota cannot continue making paid AI calls even if they tamper with the client.
- Subscription expiration and renewal correctly update server-side entitlements.
- Gemini spend can be measured per user and per tier.

### D. Product UX For Public Testing

- Add a paywall entry point at natural moments.
  - On first premium feature use
  - At quota threshold
  - In profile/settings

- Add quota visibility.
  - Remaining monthly AI usage
  - Remaining daily allowance if used
  - Reset date
  - Current plan

- Add graceful quota exhaustion UX.
  - Explain why access stopped
  - Offer upgrade or wait-until-reset path
  - Preserve the user’s drafted prompt where practical

- Add graceful AI failure UX.
  - network unavailable
  - backend unavailable
  - Gemini failure
  - timeout
  - entitlement mismatch
  - billing retry

- Add feature flagging.
  - Ability to disable:
    - photo analysis
    - plan generation
    - chat
    - high-cost models
  - Helpful for public beta risk control

- Add user-facing account and billing screens.
  - current plan
  - restore purchases
  - manage subscription
  - privacy / terms links
  - contact / support

### E. Monitoring, Support, And Ops

- Add crash reporting.
  - Sentry / Crashlytics / equivalent

- Add production analytics.
  - onboarding completion
  - paywall views
  - purchase attempts
  - purchase success/failure
  - quota hit rate
  - AI error rate
  - widget deep-link open rate

- Add server and cost observability.
  - requests per minute
  - token usage
  - model cost
  - top-spending users
  - top-costing features
  - quota rejection counts

- Add alerts.
  - abnormal spend spike
  - failed subscription sync jobs
  - elevated AI failure rates
  - backend latency spike

- Add support tooling.
  - user lookup
  - entitlement state viewer
  - quota usage viewer
  - manual quota reset
  - complimentary access / admin grant

### F. Apple Compliance And App Store Connect Setup

- Create subscription products in App Store Connect.
- Configure pricing and territories.
- Add trial / introductory offers if desired.
- Add Privacy Policy URL.
- Add Terms of Use / EULA URL.
- Add subscription descriptions and screenshots if needed.
- Add TestFlight beta app review information.
  - what to test
  - contact email
  - test account instructions if any

- Prepare privacy disclosures.
  - App Privacy labels in App Store Connect
  - Privacy manifest in the app
  - Review all SDKs used now and later

- Validate capability setup in Apple Developer / App IDs.
  - App Groups
  - CloudKit
  - HealthKit
  - Live Activities
  - time-sensitive notifications
  - Sign in with Apple if added
  - In-App Purchase

- Prepare subscription review compliance.
  - Restore purchases present
  - Manage subscription path present
  - Price/term disclosure present
  - Subscription value clearly explained before purchase

### G. QA And Rollout Plan

#### Phase 1: Internal Engineering Readiness

- Build and archive cleanly
- No launch blockers
- All app capabilities configured
- AI requests proxied through backend
- Quotas enforced
- StoreKit test purchases working locally / sandbox

#### Phase 2: Internal TestFlight

Test the following with team members:

- onboarding
- purchase
- restore purchases
- plan changes
- quota exhaustion
- expired subscription
- billing retry behavior where possible
- widget actions
- HealthKit permission flows
- live workout and Live Activity flows
- camera and photo analysis
- offline behavior

#### Phase 3: Limited External Beta

- Small trusted cohort
- Lower quota limits initially
- Close monitoring of spend and crashes
- Daily review of:
  - AI cost
  - backend reliability
  - quota hit rates
  - subscription funnel

#### Phase 4: Broader Public Testing

- Raise limits only after:
  - crash rate is acceptable
  - cost per active user is understood
  - paywall conversion is measurable
  - abuse controls are proven

## 6. Suggested Milestones

### Milestone 1: App Hardening

Deliverables:
- URL scheme fixed
- deployment targets fixed
- privacy manifest added
- release logging cleaned up
- unnecessary background modes reviewed

### Milestone 2: Backend Foundation

Deliverables:
- auth / identity
- entitlement model
- Gemini proxy
- usage metering
- quota enforcement
- admin tools v1

### Milestone 3: Billing

Deliverables:
- StoreKit 2 subscriptions
- paywall
- restore / manage subscription
- server-side transaction handling
- subscription state sync

### Milestone 4: Public Beta UX + Ops

Deliverables:
- quota UI
- over-limit UX
- AI failure UX
- crash reporting
- analytics
- spend alerts

### Milestone 5: External TestFlight Launch

Deliverables:
- TestFlight metadata
- legal links
- purchase testing complete
- beta support process
- limited external cohort launch

## 7. Open Product Decisions

These decisions should be made before backend and billing implementation is finalized:

- What exact features are free vs paid?
- What exact quota unit is used?
  - requests
  - tokens
  - weighted cost units
- What is the monthly cap per tier?
- Will image analysis cost more than text chat?
- Will there be a free trial?
- Will users need an account on first launch, or only when upgrading?
- Should non-AI tracking features remain free and unlimited?
- What is the target gross margin after Gemini and Apple fees?
- What is the maximum acceptable AI cost per paid user per month?

## 8. Recommended Immediate Next Steps

1. Fix the iOS release blockers:
   - URL scheme
   - deployment targets
   - privacy manifest
   - release logging

2. Decide the monetization model:
   - free tier
   - paid tier(s)
   - quota metric
   - target margins

3. Design the backend before implementing billing UI.
   - identity
   - entitlement schema
   - usage ledger
   - quota policy
   - Gemini proxy contract

4. Implement StoreKit 2 and App Store Connect products.

5. Run an internal TestFlight beta before inviting any external testers.

## 9. Definition Of Done For Public Testing

Trai is ready for public testing when:

- The app builds, archives, and installs cleanly
- Deep links and widgets work reliably
- Privacy manifest and Apple metadata are complete
- Subscriptions are purchasable and restorable
- Entitlements are validated and enforced
- AI requests are backend-proxied
- Per-user quotas are server-enforced
- Crash reporting and spend monitoring are live
- External testers can complete the main product loop without manual developer intervention
