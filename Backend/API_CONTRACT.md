# Trai Backend API Contract

## Auth

### `POST /v1/auth/apple/exchange`

Exchanges Sign in with Apple credentials for a Trai backend session and bootstrap payload.

Request:

```json
{
  "installationID": "device-installation-id",
  "appAccountToken": "trai_anon_abc123",
  "identityToken": "apple-jwt",
  "authorizationCode": "apple-auth-code",
  "rawNonce": "client-generated-nonce",
  "appleUserID": "001122.3344",
  "email": "user@example.com",
  "displayName": "Taylor User"
}
```

### `POST /v1/auth/refresh`

Rotates backend session tokens and returns a fresh bootstrap payload.

Request:

```json
{
  "refreshToken": "refresh-token",
  "appAccountToken": "trai_anon_abc123"
}
```

Response:

```json
{
  "session": {
    "userID": "usr_123",
    "identityProvider": "apple",
    "email": "user@example.com",
    "displayName": "Taylor User",
    "accessToken": "access-token",
    "refreshToken": "refresh-token",
    "expiresAt": "2026-04-02T17:00:00Z",
    "lastAuthenticatedAt": "2026-04-02T16:00:00Z"
  },
  "billing": {
    "accountSnapshot": {
      "installationID": "device-installation-id",
      "appAccountToken": "trai_anon_abc123",
      "identityMode": "signInWithApple",
      "backendEnvironment": "production",
      "lastSyncedAt": "2026-04-02T16:00:00Z"
    },
    "entitlementSnapshot": {
      "plan": "free",
      "status": "active",
      "sourceDescription": "backend-bootstrap",
      "renewalDate": null,
      "lastValidatedAt": "2026-04-02T16:00:00Z"
    },
    "quotaSnapshot": {
      "periodStart": "2026-04-01T00:00:00Z",
      "periodEnd": "2026-05-01T00:00:00Z",
      "usedUnits": 0,
      "bonusUnits": 0,
      "featureUsageCounts": {},
      "lastUpdatedAt": "2026-04-02T16:00:00Z"
    },
    "availableProducts": [],
    "syncState": "syncedWithBackend",
    "syncedAt": "2026-04-02T16:00:00Z"
  }
}
```

## Account Bootstrap

### `GET /v1/account/bootstrap`

Returns current session, entitlement, product, and quota state.

Headers:

- `Authorization: Bearer <access-token>`
- `X-Trai-App-Account-Token: trai_anon_abc123`

## AI Proxy

### `POST /v1/ai/generate`

Request:

```json
{
  "feature": "coachChat",
  "model": "gemini-3-flash-preview",
  "action": "generateContent",
  "requestBody": {
    "contents": []
  }
}
```

Response:

- Returns a Gemini-compatible JSON payload so the iOS client can reuse the existing parsing path.
- Backend may optionally add response headers for quota metadata later.

### `POST /v1/ai/stream`

Streaming endpoint using SSE.

- Returns Gemini-compatible SSE chunks so the current iOS streaming parser and function-calling parser can reuse the same code path.

## Billing

### `GET /v1/billing/status`

Returns current entitlement, quota, and product metadata.

### `POST /v1/billing/sync-storekit`

Used by the app or backend worker to reconcile purchase state against App Store records.

Request:

```json
{
  "signedTransactions": [
    "signed-transaction-jws"
  ],
  "entitlements": [
    {
      "productID": "trai.pro.monthly",
      "transactionID": 1001,
      "originalTransactionID": 1001,
      "purchaseDate": "2026-04-02T16:00:00Z",
      "expirationDate": "2026-05-02T16:00:00Z",
      "revocationDate": null,
      "isUpgraded": false
    }
  ]
}
```

Response:

- Returns a `BillingSyncPayload`.
- The backend prefers `signedTransactions` and verifies App Store-signed JWS payloads before mapping them into Trai subscription state.
- `entitlements` remains as a development fallback for older clients and local testing.

## App Store Server Notifications

### `POST /v1/app-store/notifications`

Accepts App Store Server Notifications V2 signed payloads.

Request:

```json
{
  "signedPayload": "signed-notification-jws"
}
```

Response:

```json
{
  "ok": true,
  "matchedUser": true
}
```

- The backend verifies the signed notification payload.
- If the payload contains `data.signedTransactionInfo`, the backend verifies that transaction too.
- If the payload contains `data.signedRenewalInfo`, the backend verifies renewal metadata and can map billing lifecycle states such as `gracePeriod`, `billingRetry`, `expired`, `refunded`, and `revoked`.
- Matching users are resolved by stored transaction history and subscription source transaction IDs.

## Admin

### `GET /v1/admin/user-inspect`

Admin-authenticated inspection endpoint for support and drift debugging.

Query params:

- `userID`
- `appAccountToken`
- `originalTransactionId`

Response:

- user record
- linked identities
- recent sessions
- current subscription
- latest quota period
- quota status summary including bonus units and remaining units
- usage analytics summary for the current period and trailing 30 days
- recent usage entries
- recent verified StoreKit transactions
- recent App Store notifications
- recent admin adjustments
- current monetization policy summary

### `POST /v1/admin/reconcile-subscription`

Admin-authenticated reconciliation endpoint that recomputes a user subscription from stored verified App Store records.

Request:

```json
{
  "userID": "usr_123"
}
```

Alternative lookup keys:

- `appAccountToken`
- `originalTransactionId`

Response:

```json
{
  "userID": "usr_123",
  "reconciledAt": "2026-04-03T18:00:00Z",
  "transactionCount": 3,
  "appliedNotificationType": "REFUND",
  "subscription": {
    "plan": "pro",
    "status": "refunded"
  }
}
```

### `POST /v1/admin/quota-adjustment`

Admin-authenticated endpoint for manual credits or debits on the current quota period.

Request:

```json
{
  "userID": "usr_123",
  "unitDelta": 120,
  "reason": "Support credit for beta testing"
}
```

Alternative lookup keys:

- `appAccountToken`
- `originalTransactionId`

Response:

- updated `quotaSnapshot`
- refreshed usage analytics for the user

### `POST /v1/admin/quota-reset`

Admin-authenticated endpoint for resetting current-period usage without destroying the audit trail.

Request:

```json
{
  "userID": "usr_123",
  "resetUsedUnitsTo": 0,
  "reason": "Support reset"
}
```

Alternative lookup keys:

- `appAccountToken`
- `originalTransactionId`
