# Trai Production Accounts, Billing, and AI Backend Plan

## Objective

Ship Trai for public testing with:

- authenticated user accounts
- App Store subscription entitlements
- server-enforced AI quotas and billing protection
- Gemini access routed through Trai-owned backend services
- production-safe observability, support tooling, and rollout controls

## Principles

- The app must never be the production source of truth for quota or paid access.
- Gemini API keys must never ship as the production execution path for paid users.
- A user must have one canonical backend identity across reinstall, device change, and subscription restore.
- Every AI request must be attributable to a user, entitlement state, and quota period.
- Degraded states must be explicit: signed out, subscription expired, quota exhausted, backend unavailable.

## Current State

- iOS app exists and currently owns AI orchestration locally.
- Local quota and subscription scaffolding exists in the app.
- StoreKit 2 product loading, purchase, and restore scaffolding exists in the app.
- There is no backend in this repository yet.
- There is no server-side identity, entitlement validation, Gemini proxy, or quota ledger yet.
- Gemini direct calls still exist in the app and remain a production risk until backend proxy mode is fully live.

## Required Workstreams

## 1. Account System

### Goals

- Give every user a stable account identity.
- Support anonymous install bootstrap before sign-in.
- Support Sign in with Apple as the primary authenticated path.
- Support account recovery across reinstall and device changes.

### Implementation

- Persist local installation identity and app account token in the app.
- Add Sign in with Apple in iOS settings/account surfaces.
- Exchange Apple identity token with Trai backend.
- Backend issues a Trai session token and canonical `user_id`.
- Backend links anonymous install token to canonical user on first successful auth.
- Support sign-out and session refresh flows.

### Done When

- A reinstalling user can sign back in and recover entitlements.
- Backend can identify a user without trusting client-provided plan/quota state.

## 2. Billing and Entitlement Source of Truth

### Goals

- Use App Store purchases as the commercial source.
- Use backend entitlement records as the operational source for AI access.

### Implementation

- Define App Store products and subscription group in App Store Connect.
- Load products in the app using StoreKit 2.
- Send verified purchase context to backend.
- Backend stores:
  - current entitlement
  - renewal / expiration metadata
  - source transaction identifiers
  - audit event history
- Add App Store Server Notifications ingestion.
- Reconcile StoreKit state, backend entitlement state, and app presentation state.

### Done When

- Backend can answer: "Is this user entitled right now?"
- Revoked, expired, billing retry, and restored subscriptions all flow into backend state.

## 3. Gemini Proxy and Cost Protection

### Goals

- Remove direct production dependency on client-to-Gemini requests.
- Make Trai backend the only production caller of Gemini.

### Implementation

- Add backend AI proxy endpoints for standard and streaming requests.
- Require authenticated request context and app account token.
- Attach feature type to each AI request.
- Backend enforces quota before calling Gemini.
- Backend records cost and usage after each request.
- Use the backend as the only shipped AI execution path.

### Done When

- Production uses the backend as the only AI path.
- AI usage cannot bypass quota enforcement with a modified client.

## 4. Quota and Usage Ledger

### Goals

- Prevent unit economics from drifting negative.
- Give support and ops visibility into user usage and spend.

### Initial Model

- Free: `60` monthly AI units
- Pro: `1200` monthly AI units at `3.99/month`
- Elite: `2400` monthly AI units at `5.99/month`
- Meter by weighted AI cost units by feature
- Aim to keep average paid-user AI cost near `1.00/month`, with a support/escalation ceiling around `2.25/month`

### Server Responsibilities

- open quota period per user
- track used units
- track feature-level counts
- reject over-limit requests
- support admin resets and manual credits
- support emergency caps

### Done When

- Server can answer: "How much quota does this user have left this period?"
- Spend anomalies are observable before large cost overruns happen.

## 5. Backend Services

### Initial Service Surface

- `POST /v1/auth/apple/exchange`
- `GET /v1/account/bootstrap`
- `POST /v1/ai/generate`
- `POST /v1/ai/stream`
- `GET /v1/billing/status`
- `POST /v1/billing/sync-storekit`

### Backend Responsibilities

- verify Apple identity tokens
- mint and refresh Trai session tokens
- verify App Store transaction state
- maintain entitlement and quota state
- proxy Gemini requests
- emit logs, metrics, and audit records

## 6. Data Model

### Core Tables

- `users`
- `auth_identities`
- `sessions`
- `subscriptions`
- `subscription_events`
- `quota_periods`
- `usage_ledger`
- `ai_requests`
- `admin_adjustments`

### Required Fields

- `users`: canonical id, created_at, status
- `auth_identities`: provider, provider_user_id, user_id
- `sessions`: user_id, access_token_hash, refresh_token_hash, expires_at
- `subscriptions`: user_id, plan, status, source_transaction_id, renews_at, expires_at
- `quota_periods`: user_id, period_start, period_end, unit_limit, units_used
- `usage_ledger`: user_id, feature, unit_cost, request_id, created_at
- `ai_requests`: user_id, feature, model, outcome, latency_ms, provider_cost_estimate

## 7. Security Requirements

- Do not trust client plan or quota state.
- Do not persist raw secrets in app bundle or repo.
- Do not expose backend session tokens in logs.
- Use hashed token storage on the backend.
- Use signed session tokens with short-lived access and refresh rotation.
- Verify Apple identity tokens server-side.
- Verify App Store purchase state server-side.
- Rate-limit auth and AI proxy endpoints.

## 8. iOS Work Required

### Immediate

- Persist backend session state in-app
- Add Sign in with Apple account flow
- Add backend bootstrap/sync service
- Route backend proxy mode through authenticated request headers
- Surface signed-in status, backend sync status, and failure states

### Follow-up

- Replace local-only quota UI with server-backed quota state
- Add paywall and limit-hit experiences tied to backend state
- Add graceful offline and degraded-mode handling

## 9. Rollout Phases

### Phase 1

- app-side account and backend contract
- Sign in with Apple
- backend API contract
- backend proxy transport path in app

### Phase 2

- real backend auth/session service
- billing sync endpoint
- quota ledger
- Gemini proxy endpoint

### Phase 3

- StoreKit reconciliation
- App Store Server Notifications
- admin tools
- spend monitoring and alerts

### Phase 4

- internal TestFlight with paid entitlement and quota scenarios
- external TestFlight with limited audience and spend monitoring

## 10. Production Readiness Checklist

- Sign in with Apple works across reinstall
- purchase and restore work against real App Store Connect products
- backend is authoritative for entitlement and quota
- production uses the backend as the only AI path
- quota exhaustion returns correct UX
- expired subscription returns correct UX
- support can inspect and adjust user quota
- request/latency/error metrics exist
- privacy policy and terms reflect accounts and subscriptions
- incident rollback path exists for backend proxy and AI spend spikes

## Implementation Order

1. Finalize app-side account and backend models
2. Add Sign in with Apple and backend session persistence
3. Add backend-aware AI transport path in the app
4. Stand up backend endpoints and schema
5. Sync StoreKit entitlement state to backend
6. Enforce quotas server-side
7. Cut over production AI traffic to backend proxy only

## Blockers Outside This Repo

- App Store Connect product creation
- backend hosting and database provisioning
- Apple Sign in service configuration
- TLS domains and secret management
- App Store Server Notifications setup
