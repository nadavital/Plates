# Trai Backend

Zero-dependency backend scaffold for:

- Sign in with Apple exchange
- backend session bootstrap
- entitlement and quota state
- Gemini proxying
- usage ledger persistence

## Run

```bash
cd /Users/navital/Desktop/Trai/Backend
ALLOW_DEV_APPLE_BYPASS=true \
TRAI_ENVIRONMENT=staging \
GEMINI_API_KEY=your_key_here \
npm run dev
```

## Environment Variables

- `PORT`
  - default: `8789`
- `TRAI_ENVIRONMENT`
  - `staging` or `production`
- `HOST`
  - default: `127.0.0.1`
- `TRAI_DB_PATH`
  - optional custom SQLite path
- `GEMINI_API_KEY`
  - required for AI proxy endpoints
- `GEMINI_MODEL`
  - default: `gemini-3-flash-preview`
- `ALLOW_DEV_APPLE_BYPASS`
  - `true` enables local Apple auth bypass for development
- `APPLE_EXPECTED_AUDIENCES`
  - comma-separated expected Apple audiences
  - default: `Nadav.Trai`
- `APPLE_EXPECTED_ISSUER`
  - default: `https://appleid.apple.com`
- `APPLE_JWKS_URL`
  - default: `https://appleid.apple.com/auth/keys`
- `APPLE_JWKS_PATH`
  - optional local JWKS file override for development/testing
- `APPLE_JWKS_CACHE_TTL_SECONDS`
  - default: `21600`
- `APP_STORE_EXPECTED_BUNDLE_IDS`
  - comma-separated bundle identifiers allowed in App Store signed transactions and notifications
  - default: `Nadav.Trai`
- `APP_STORE_ROOT_CERT_PATHS`
  - comma-separated PEM or DER certificate paths for trusted App Store root certificates
- `APP_STORE_TRUSTED_ROOT_SUBJECTS`
  - comma-separated fallback subject fragments for trusted App Store roots
  - default: `Apple Root CA - G3,Apple Inc. Root`
- `TRAI_ADMIN_API_KEY`
  - required for backend admin inspection, reconciliation, quota credit, and quota reset endpoints

## Notes

- This scaffold is intentionally dependency-light so it can run in this repo without package installs.
- Apple identity tokens are now verified against Apple JWKS before a backend session is issued.
- `ALLOW_DEV_APPLE_BYPASS` must never be enabled in production.
- When `ALLOW_DEV_APPLE_BYPASS=true`, non-JWT placeholder tokens can still be used for local-only development.
- `POST /v1/billing/sync-storekit` now prefers signed App Store transaction JWS payloads and updates backend subscription state after verification.
- `POST /v1/app-store/notifications` accepts App Store Server Notifications V2 signed payloads and can update subscriptions even when the app is not open.
- Notification handling now maps lifecycle events into backend subscription states including `gracePeriod`, `billingRetry`, `expired`, `refunded`, and `revoked`.
- The current launch pricing assumption is a break-even-oriented `Trai Pro` monthly plan at `$3.99`, with backend quotas tuned to avoid subsidizing Gemini usage.
- `GET /v1/admin/user-inspect`, `POST /v1/admin/reconcile-subscription`, `POST /v1/admin/quota-adjustment`, and `POST /v1/admin/quota-reset` provide support tooling for drift debugging, manual repair, and beta support credits.
- The iOS app can use the `Local Development` backend environment to point at `http://127.0.0.1:8789` during simulator-based testing.
- Run `npm run verify:apple` to exercise the JWT verification path against a local JWKS fixture.
