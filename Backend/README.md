# Trai Backend

Backend service for:

- Sign in with Apple exchange
- backend session bootstrap
- entitlement and quota state
- AI provider proxying
- usage ledger persistence

## Run

```bash
cd /Users/navital/Desktop/Trai/Backend
ALLOW_DEV_APPLE_BYPASS=true \
TRAI_ENVIRONMENT=staging \
TRAI_AI_PROVIDER=openai \
OPENAI_API_KEY=your_key_here \
npm run dev
```

For on-device local testing, also set `HOST=0.0.0.0` and point the app's custom local backend URL at your Mac's LAN IP.

Use `.env.example` as the starting point for local and Cloud Run environment configuration.

## Environment Variables

- `PORT`
  - default: `8789`
- `TRAI_ENVIRONMENT`
  - `staging` or `production`
- `HOST`
  - default: `127.0.0.1`
- `TRAI_DB_PATH`
  - optional custom SQLite path
- `TRAI_AI_PROVIDER`
  - `gemini` or `openai`
  - default: `openai`
- `TRAI_DATABASE_DRIVER`
  - `sqlite` or `firestore`
  - defaults to `sqlite` for local development
  - use `firestore` for Cloud Run staging and production
- `FIRESTORE_PROJECT_ID`
  - optional explicit Google Cloud project for Firestore
- `FIRESTORE_DATABASE_ID`
  - optional Firestore database ID
  - defaults to `(default)`
- `GEMINI_API_KEY`
  - required for AI proxy endpoints
- `GEMINI_MODEL`
  - default: `gemini-3-flash-preview`
- `OPENAI_API_KEY`
  - required only when `TRAI_AI_PROVIDER=openai`
- `OPENAI_MODEL`
  - default: `gpt-5.4-mini`
- `OPENAI_INPUT_USD_PER_1M_TOKENS`, `OPENAI_OUTPUT_USD_PER_1M_TOKENS`, `OPENAI_CACHED_INPUT_USD_PER_1M_TOKENS`
  - optional override for OpenAI token-cost estimation
  - defaults for `gpt-5.4-mini`: `0.75`, `4.5`, `0.075`
- `GEMINI_INPUT_USD_PER_1M_TOKENS`, `GEMINI_OUTPUT_USD_PER_1M_TOKENS`, `GEMINI_CACHED_INPUT_USD_PER_1M_TOKENS`
  - optional override for Gemini token-cost estimation
  - defaults for `gemini-3-flash-preview`: `0.5`, `3`, `0.05`
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

## Cloud Run Staging

Build and deploy the backend as a public staging service:

```bash
cd /Users/navital/Desktop/Trai/Backend

gcloud builds submit --tag us-central1-docker.pkg.dev/YOUR_PROJECT/trai-backend/trai-backend:staging .

gcloud run deploy trai-backend-staging \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT/trai-backend/trai-backend:staging \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars HOST=0.0.0.0,TRAI_ENVIRONMENT=staging,GEMINI_MODEL=gemini-3-flash-preview \
  --set-secrets GEMINI_API_KEY=GEMINI_API_KEY:latest,TRAI_ADMIN_API_KEY=TRAI_ADMIN_API_KEY:latest
```

For the durable low-cost staging shape, use Firestore:

```bash
TRAI_DATABASE_DRIVER=firestore
```

Recommended next step after the first successful staging deploy:

- map `staging-api.trai.app` to the Cloud Run service
- update the iOS app's staging URL to that real hostname
- verify `/health`, Sign in with Apple exchange, bootstrap, AI proxy, and StoreKit sync

## Cloud Run Production

For TestFlight and the App Store, the recommended shape is:

- one shared production backend
- one shared production Firestore database
- TestFlight and App Store builds both pointed at production

That keeps account state, subscriptions, and quota consistent when a TestFlight tester later installs the App Store build.
TestFlight StoreKit transactions and server notifications use Apple's Sandbox environment even when the app talks to this production backend, so the backend accepts signed Sandbox and Production App Store payloads after validating the bundle ID, product ID, certificate chain, signature, and transaction ownership.

Enable Firestore native mode in the Google Cloud project, then deploy the production service without Cloud SQL:

```bash
cd /Users/navital/Desktop/Trai/Backend

PROJECT_ID=YOUR_PROJECT \
SERVICE_NAME=trai-backend-production \
IMAGE_NAME=trai-backend \
IMAGE_TAG=production \
TRAI_ENVIRONMENT=production \
TRAI_DATABASE_DRIVER=firestore \
MIN_INSTANCES=0 \
MAX_INSTANCES=3 \
./scripts/deploy_cloud_run.sh
```

Recommended follow-up after the first successful production deploy:

- map `api.trai.app` to the production Cloud Run service
- update the iOS app production URL if needed
- verify `/health`, Sign in with Apple exchange, bootstrap, AI proxy, and StoreKit sync
- use production for TestFlight so beta users keep their account state at App Store launch

## Switching A Provider

To test OpenAI on an existing Cloud Run service, store the OpenAI key in Secret Manager:

```bash
printf '%s' 'YOUR_OPENAI_API_KEY' | gcloud secrets create OPENAI_API_KEY --data-file=-
```

If the secret already exists:

```bash
printf '%s' 'YOUR_OPENAI_API_KEY' | gcloud secrets versions add OPENAI_API_KEY --data-file=-
```

Then redeploy with:

```bash
cd /Users/navital/Desktop/Trai/Backend

PROJECT_ID=YOUR_PROJECT \
SERVICE_NAME=trai-backend-staging \
IMAGE_NAME=trai-backend \
IMAGE_TAG=openai-staging \
TRAI_ENVIRONMENT=staging \
TRAI_AI_PROVIDER=openai \
OPENAI_MODEL=gpt-5.4-mini \
TRAI_DATABASE_DRIVER=firestore \
./scripts/deploy_cloud_run.sh
```

Do the same for production by changing:

- `SERVICE_NAME=trai-backend-production`
- `IMAGE_TAG=openai-production`
- `TRAI_ENVIRONMENT=production`

The active provider can be confirmed from `/health`, which now reports:

- `aiProvider`
- `aiProviderModel`
- `aiProviderCapabilities`

## Scaling Path

The backend now supports SQLite and Firestore:

- SQLite keeps local development simple and fast.
- Firestore is the intended cost-efficient Cloud Run / staging / production persistence layer.

Recommended order:

1. Keep SQLite for simulator and single-machine local work.
2. Use Firestore for Cloud Run staging and production so sessions, subscriptions, admin overrides, quota, and usage telemetry survive instance restarts without a fixed Cloud SQL instance bill.
3. Keep normal free-user app usage local-first. Only hit the backend for sign-in, purchase/restore, App Store notifications, admin overrides, and AI requests.
4. Keep the iOS client on backend-only AI paths so future providers can be added behind the server without changing the app.

## Notes

- The deployed backend uses Firestore for persistence; local development can use SQLite.
- Apple identity tokens are now verified against Apple JWKS before a backend session is issued.
- `ALLOW_DEV_APPLE_BYPASS` must never be enabled in production.
- When `ALLOW_DEV_APPLE_BYPASS=true`, non-JWT placeholder tokens can still be used for local-only development.
- `POST /v1/billing/sync-storekit` now prefers signed App Store transaction JWS payloads and updates backend subscription state after verification.
- `POST /v1/app-store/notifications` accepts App Store Server Notifications V2 signed payloads and can update subscriptions even when the app is not open.
- Notification handling now maps lifecycle events into backend subscription states including `gracePeriod`, `billingRetry`, `expired`, `refunded`, and `revoked`.
- The current launch pricing assumption is a break-even-oriented `Trai Pro` monthly plan at `$3.99`, with backend quotas tuned to avoid subsidizing Gemini usage.
- `GET /v1/admin/user-inspect`, `GET /v1/admin/usage-summary`, `POST /v1/admin/reconcile-subscription`, `POST /v1/admin/quota-adjustment`, and `POST /v1/admin/quota-reset` provide support tooling for drift debugging, manual repair, and beta support credits.
- `GET /v1/admin/user-inspect` now includes trailing AI telemetry summaries by feature and by provider/model when token metadata is available.
- `GET /v1/admin/usage-summary` returns trailing-window usage averages, plan breakdowns, top users, and telemetry cost rollups so quota changes can be based on real per-user behavior.
- Real token-cost estimation is driven by model-aware defaults for the shipped OpenAI and Gemini models, and can still be overridden with `OPENAI_INPUT_USD_PER_1M_TOKENS`, `OPENAI_OUTPUT_USD_PER_1M_TOKENS`, `OPENAI_CACHED_INPUT_USD_PER_1M_TOKENS`, `GEMINI_INPUT_USD_PER_1M_TOKENS`, `GEMINI_OUTPUT_USD_PER_1M_TOKENS`, and `GEMINI_CACHED_INPUT_USD_PER_1M_TOKENS`.
- The iOS app can use the `Local Development` backend environment to point at `http://127.0.0.1:8789` during simulator-based testing.
- The iOS app should use `Staging` by default in development builds once a real public staging service exists.
- Run `npm run verify:apple` to exercise the JWT verification path against a local JWKS fixture.
