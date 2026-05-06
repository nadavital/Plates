# Trai Release Checklist

This is the working source of truth for getting Trai onto TestFlight and the App Store.

Current status:

- [x] TestFlight build is live.
- [x] Device/runtime verification has been completed for the current TestFlight path.

## Release Decisions

- [x] AI is backend-only. The app no longer calls Gemini directly.
- [x] Local development uses staging or an explicit custom backend URL.
- [x] TestFlight and App Store builds should use the same production backend environment so accounts, subscriptions, and quota state carry forward cleanly.
- [x] Staging remains for local development and backend verification only.

## Already Done

- [x] Cloud Run backend is deployed.
- [x] Backend persistence is on Postgres instead of SQLite.
- [x] Apple sign-in works against the backend.
- [x] Backend supports explicit subscription sources like `appStore` and `adminGrant`.
- [x] Direct Gemini transport was removed from the app.
- [x] Developer Settings is hidden from non-debug builds.
- [x] Device build succeeds after the backend-only AI transition.

## Completed Before TestFlight

### Backend / Environment

- [x] Decide the production backend URL.
- [x] Deploy or promote the production backend service.
- [x] Set `TRAIBackendProductionBaseURL` to the real production API URL.
- [x] Make sure non-debug builds use the production backend by default.
- [x] Keep staging available for local debugging only.

### StoreKit / Billing

- [x] Confirm `trai.pro.monthly` loads from App Store Connect on device.
- [x] Verify purchase flow succeeds on device.
- [x] Verify restore flow succeeds on device.
- [x] Verify backend sync marks paid subscriptions as `source=appStore`.
- [x] Verify a purchased account stays Pro after relaunch and next-day refresh.

### Account / Auth

- [x] Verify Sign in with Apple on a clean install.
- [x] Verify sign-out and sign-back-in on the same device.
- [x] Verify account state persists across relaunch.

### Core Product Flows

- [x] Verify Trai chat works on the backend path.
- [x] Verify food analysis works on the backend path.
- [x] Verify workout planning / review works on the backend path.
- [x] Verify free-user locked states and upsells still behave correctly.
- [x] Verify Pro-user unlocked states still behave correctly.

### Widget / Deep Link

- [x] Verify the widget `Log Food` action works from a cold launch.
- [x] Verify the widget `Log Food` action works when the app is already running.

## Strongly Recommended Before External TestFlight / App Store

- [ ] Add a real production domain such as `api.trai.app`.
- [ ] Add stronger app-origin trust such as App Attest or DeviceCheck.
- [ ] Add backend observability for auth, billing sync, and AI failures.
- [ ] Confirm App Store Connect agreements, banking, and tax are complete.
- [ ] Finalize App Store metadata, screenshots, and review notes.
- [ ] Confirm privacy disclosures are accurate for Sign in with Apple, HealthKit, and backend AI usage.

## Release Day Verification

- [x] Build an archive from a non-debug/release configuration.
- [x] Upload to TestFlight.
- [x] Install the TestFlight build on a clean device.
- [x] Repeat the core sign-in, billing, AI, and widget smoke tests in TestFlight.
- [x] Confirm the TestFlight build points at production, not staging.

## Notes

- If we want TestFlight users to keep their account state when the App Store version goes live, TestFlight and App Store must talk to the same production backend and database.
- TestFlight StoreKit payloads are signed but report Apple's Sandbox environment; the production backend must accept those payloads after normal signature, bundle, product, and ownership validation.
- Staging is still useful for local iteration, but it should not be the long-term backend for distributed beta users.
