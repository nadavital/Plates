import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { X509Certificate } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'trai-apple-verify-'));
const jwksPath = path.join(tempRoot, 'jwks.json');
const databasePath = path.join(tempRoot, 'trai.sqlite');
const port = 8791;
const storeKitFixtures = createStoreKitCertificateChain(tempRoot);
const adminToken = 'local-admin-token';

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048
});
const publicJWK = publicKey.export({ format: 'jwk' });
const keyID = 'test-key-1';

fs.writeFileSync(jwksPath, JSON.stringify({
  keys: [
    {
      ...publicJWK,
      kid: keyID,
      alg: 'RS256',
      use: 'sig'
    }
  ]
}, null, 2));

const child = spawn(process.execPath, ['src/server.mjs'], {
  cwd: backendRoot,
  env: {
    ...process.env,
    PORT: String(port),
    HOST: '127.0.0.1',
    TRAI_ENVIRONMENT: 'production',
    TRAI_DB_PATH: databasePath,
    APPLE_JWKS_PATH: jwksPath,
    APPLE_EXPECTED_AUDIENCES: 'Nadav.Trai',
    APP_STORE_EXPECTED_BUNDLE_IDS: 'Nadav.Trai',
    APP_STORE_ROOT_CERT_PATHS: storeKitFixtures.rootCertificatePath,
    APP_STORE_TRUSTED_ROOT_SUBJECTS: 'Unit Test Root CA',
    OPENAI_API_KEY: 'unit-test-openai-key',
    TRAI_ADMIN_API_KEY: adminToken
  },
  stdio: ['ignore', 'pipe', 'pipe']
});

child.stdout.on('data', (chunk) => {
  process.stdout.write(chunk);
});

child.stderr.on('data', (chunk) => {
  process.stderr.write(chunk);
});

try {
  await waitForHealth();
  const healthResponse = await fetch(`http://127.0.0.1:${port}/health`);
  assert.equal(healthResponse.status, 200, 'expected health check to succeed');

  const healthPayload = await healthResponse.json();
  assert.equal(healthPayload.environment, 'production', 'expected verification server to model TestFlight production backend');
  assert.equal(healthPayload.aiProvider, 'openai', 'expected OpenAI to remain the default provider');
  assert.equal(healthPayload.hasProviderKey, true, 'expected default provider key to be configured');

  const rawNonce = crypto.randomBytes(16).toString('hex');
  const sharedBody = {
    installationID: 'local-installation',
    appAccountToken: 'trai_anon_localtest',
    authorizationCode: 'local-auth-code',
    appleUserID: 'apple-user-123',
    email: 'tester@example.com',
    displayName: 'Local Tester'
  };
  const storeKitAppAccountToken = deriveStoreKitAppAccountToken(sharedBody.appAccountToken);

  const goodToken = signIdentityToken({
    iss: 'https://appleid.apple.com',
    aud: 'Nadav.Trai',
    sub: sharedBody.appleUserID,
    email: sharedBody.email,
    nonce: sha256Hex(rawNonce),
    exp: Math.floor(Date.now() / 1000) + 300,
    iat: Math.floor(Date.now() / 1000) - 10
  });

  const successResponse = await postJSON('/v1/auth/apple/exchange', {
    ...sharedBody,
    identityToken: goodToken,
    rawNonce
  });
  assert.equal(successResponse.status, 200, 'expected valid Apple token exchange to succeed');

  const successPayload = await successResponse.json();
  assert.ok(successPayload.session?.userID, 'expected backend session in successful exchange response');
  assert.equal(successPayload.session?.identityProvider, 'apple');
  assert.equal(successPayload.billing?.entitlementSnapshot?.plan, 'free');

  const syncedResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/sync-storekit`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    },
    body: JSON.stringify({
      signedTransactions: [
        createSignedStoreKitTransaction(storeKitFixtures, {
          bundleId: 'Nadav.Trai',
          environment: 'Sandbox',
          productId: 'trai.pro.monthly',
          appAccountToken: storeKitAppAccountToken,
          transactionId: '1001',
          originalTransactionId: '1001',
          purchaseDate: Date.now(),
          expiresDate: Date.now() + (7 * 24 * 60 * 60 * 1000),
          signedDate: Date.now(),
          type: 'Auto-Renewable Subscription',
          inAppOwnershipType: 'PURCHASED'
        })
      ]
    })
  });
  assert.equal(syncedResponse.status, 200, 'expected StoreKit sync to succeed');

  const syncedPayload = await syncedResponse.json();
  assert.equal(syncedPayload.entitlementSnapshot?.plan, 'pro');
  assert.equal(syncedPayload.syncState, 'syncedWithBackend');

  const transientEmptySyncResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/sync-storekit`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    },
    body: JSON.stringify({
      signedTransactions: []
    })
  });
  assert.equal(transientEmptySyncResponse.status, 200, 'expected empty StoreKit sync to succeed');

  const transientEmptySyncPayload = await transientEmptySyncResponse.json();
  assert.equal(
    transientEmptySyncPayload.entitlementSnapshot?.plan,
    'pro',
    'expected transient empty sync to preserve a still-active verified subscription'
  );

  const mismatchedSyncResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/sync-storekit`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    },
    body: JSON.stringify({
      signedTransactions: [
        createSignedStoreKitTransaction(storeKitFixtures, {
          bundleId: 'Nadav.Trai',
          environment: 'Sandbox',
          productId: 'trai.pro.monthly',
          appAccountToken: deriveStoreKitAppAccountToken('different-account'),
          transactionId: '2001',
          originalTransactionId: '2001',
          purchaseDate: Date.now(),
          expiresDate: Date.now() + (7 * 24 * 60 * 60 * 1000),
          signedDate: Date.now(),
          type: 'Auto-Renewable Subscription',
          inAppOwnershipType: 'PURCHASED'
        })
      ]
    })
  });
  assert.equal(mismatchedSyncResponse.status, 409, 'expected mismatched StoreKit account token to be rejected');

  const notificationPayload = createSignedAppStoreNotification(storeKitFixtures, {
    notificationType: 'DID_RENEW',
    subtype: null,
    notificationUUID: crypto.randomUUID(),
    version: '2.0',
    signedDate: Date.now(),
    data: {
      appAppleId: 1234567890,
      bundleId: 'Nadav.Trai',
      bundleVersion: '1',
      environment: 'Sandbox',
      signedTransactionInfo: createSignedStoreKitTransaction(storeKitFixtures, {
        bundleId: 'Nadav.Trai',
        environment: 'Sandbox',
        productId: 'trai.pro.monthly',
        appAccountToken: storeKitAppAccountToken,
        transactionId: '1002',
        originalTransactionId: '1001',
        purchaseDate: Date.now(),
        expiresDate: Date.now() + (30 * 24 * 60 * 60 * 1000),
        signedDate: Date.now(),
        type: 'Auto-Renewable Subscription',
        inAppOwnershipType: 'PURCHASED'
      })
    }
  });

  const notificationResponse = await postJSON('/v1/app-store/notifications', {
    signedPayload: notificationPayload
  });
  assert.equal(notificationResponse.status, 200, 'expected signed App Store notification to succeed');

  const notificationResult = await notificationResponse.json();
  assert.equal(notificationResult.ok, true);
  assert.equal(notificationResult.matchedUser, true);

  const billingStatusResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/status`, {
    headers: {
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    }
  });
  assert.equal(billingStatusResponse.status, 200, 'expected billing status request to succeed');
  const billingStatusPayload = await billingStatusResponse.json();
  assert.equal(billingStatusPayload.entitlementSnapshot?.plan, 'pro');

  const gracePayload = createSignedAppStoreNotification(storeKitFixtures, {
    notificationType: 'DID_FAIL_TO_RENEW',
    subtype: 'GRACE_PERIOD',
    notificationUUID: crypto.randomUUID(),
    version: '2.0',
    signedDate: Date.now(),
    data: {
      appAppleId: 1234567890,
      bundleId: 'Nadav.Trai',
      bundleVersion: '1',
      environment: 'Sandbox',
      signedRenewalInfo: createSignedAppStoreNotification(storeKitFixtures, {
        environment: 'Sandbox',
        bundleId: 'Nadav.Trai',
        originalTransactionId: '1001',
        autoRenewProductId: 'trai.pro.monthly',
        productId: 'trai.pro.monthly',
        autoRenewStatus: 1,
        gracePeriodExpiresDate: Date.now() + (3 * 24 * 60 * 60 * 1000),
        isInBillingRetryPeriod: true,
        signedDate: Date.now()
      })
    }
  });

  const graceResponse = await postJSON('/v1/app-store/notifications', {
    signedPayload: gracePayload
  });
  assert.equal(graceResponse.status, 200, 'expected grace-period notification to succeed');

  const graceStatusResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/status`, {
    headers: {
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    }
  });
  const graceStatusPayload = await graceStatusResponse.json();
  assert.equal(graceStatusPayload.entitlementSnapshot?.status, 'gracePeriod');

  const refundPayload = createSignedAppStoreNotification(storeKitFixtures, {
    notificationType: 'REFUND',
    subtype: null,
    notificationUUID: crypto.randomUUID(),
    version: '2.0',
    signedDate: Date.now(),
    data: {
      appAppleId: 1234567890,
      bundleId: 'Nadav.Trai',
      bundleVersion: '1',
      environment: 'Sandbox',
      signedTransactionInfo: createSignedStoreKitTransaction(storeKitFixtures, {
        bundleId: 'Nadav.Trai',
        environment: 'Sandbox',
        productId: 'trai.pro.monthly',
        appAccountToken: storeKitAppAccountToken,
        transactionId: '1003',
        originalTransactionId: '1001',
        purchaseDate: Date.now() - (2 * 24 * 60 * 60 * 1000),
        expiresDate: Date.now() + (28 * 24 * 60 * 60 * 1000),
        revocationDate: Date.now(),
        signedDate: Date.now(),
        type: 'Auto-Renewable Subscription',
        inAppOwnershipType: 'PURCHASED'
      })
    }
  });

  const refundResponse = await postJSON('/v1/app-store/notifications', {
    signedPayload: refundPayload
  });
  assert.equal(refundResponse.status, 200, 'expected refund notification to succeed');

  const refundedStatusResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/status`, {
    headers: {
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    }
  });
  const refundedStatusPayload = await refundedStatusResponse.json();
  assert.equal(refundedStatusPayload.entitlementSnapshot?.status, 'refunded');

  const inspectResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/user-inspect?userID=${encodeURIComponent(successPayload.session.userID)}`, {
    headers: {
      Authorization: `Bearer ${adminToken}`
    }
  });
  assert.equal(inspectResponse.status, 200, 'expected admin user inspection to succeed');
  const inspectPayload = await inspectResponse.json();
  assert.equal(inspectPayload.subscription?.status, 'refunded');
  assert.equal(inspectPayload.monetizationPolicy?.primaryPlan?.priceDisplay, '$3.99');
  assert.equal(inspectPayload.usageAnalytics?.currentPeriod?.bonusUnits, 0);
  assert.ok(Array.isArray(inspectPayload.recentTransactions));
  assert.ok(Array.isArray(inspectPayload.recentNotifications));

  const overrideResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/subscription-override`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      userID: successPayload.session.userID,
      plan: 'pro',
      status: 'active',
      source: 'adminGrant',
      reason: 'Test override'
    })
  });
  assert.equal(overrideResponse.status, 200, 'expected admin subscription override to succeed');
  const overridePayload = await overrideResponse.json();
  assert.equal(overridePayload.subscription?.plan, 'pro');
  assert.equal(overridePayload.subscription?.source, 'adminGrant');
  assert.equal(overridePayload.rawSubscription?.status, 'refunded');
  assert.equal(overridePayload.subscriptionOverride?.plan, 'pro');

  const overriddenBillingStatusResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/status`, {
    headers: {
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    }
  });
  assert.equal(overriddenBillingStatusResponse.status, 200, 'expected billing status request after override to succeed');
  const overriddenBillingStatusPayload = await overriddenBillingStatusResponse.json();
  assert.equal(overriddenBillingStatusPayload.entitlementSnapshot?.plan, 'pro');
  assert.equal(overriddenBillingStatusPayload.entitlementSnapshot?.status, 'active');
  assert.equal(overriddenBillingStatusPayload.entitlementSnapshot?.sourceDescription, 'adminGrant');

  seedAnalyticsUsage(databasePath, successPayload.session.userID);

  const usageSummaryResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/usage-summary?days=7&limit=5&includeIdentity=true`, {
    headers: {
      Authorization: `Bearer ${adminToken}`
    }
  });
  assert.equal(usageSummaryResponse.status, 200, 'expected admin usage summary to succeed');
  const usageSummaryPayload = await usageSummaryResponse.json();
  assert.equal(usageSummaryPayload.usageAnalytics?.topUserLimit, 5);
  assert.equal(usageSummaryPayload.usageAnalytics?.activeUserCount, 1);
  assert.equal(usageSummaryPayload.usageAnalytics?.unitsUsed, 9);
  assert.equal(usageSummaryPayload.usageAnalytics?.averageUnitsPerActiveUser, 9);
  assert.equal(usageSummaryPayload.usageAnalytics?.topUsers?.[0]?.userID, successPayload.session.userID);
  assert.equal(usageSummaryPayload.usageAnalytics?.topUsers?.[0]?.plan, 'pro');
  assert.equal(usageSummaryPayload.usageAnalytics?.topUsers?.[0]?.subscriptionSource, 'adminGrant');
  assert.equal(usageSummaryPayload.usageAnalytics?.topUsers?.[0]?.email, sharedBody.email);
  assert.equal(usageSummaryPayload.usageAnalytics?.byPlan?.[0]?.plan, 'pro');
  assert.equal(usageSummaryPayload.usageAnalytics?.byPlan?.[0]?.source, 'adminGrant');
  assert.equal(usageSummaryPayload.usageAnalytics?.telemetry?.telemetryCoverageRatio, 1);

  const rangedUsageSummaryResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/usage-summary?start=2000-01-01T00%3A00%3A00.000Z&end=2000-01-02T00%3A00%3A00.000Z`, {
    headers: {
      Authorization: `Bearer ${adminToken}`
    }
  });
  assert.equal(rangedUsageSummaryResponse.status, 200, 'expected ranged admin usage summary to succeed');
  const rangedUsageSummaryPayload = await rangedUsageSummaryResponse.json();
  assert.equal(rangedUsageSummaryPayload.usageAnalytics?.activeUserCount, 0);

  const allTimeUsageSummaryResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/usage-summary?period=all&limit=1`, {
    headers: {
      Authorization: `Bearer ${adminToken}`
    }
  });
  assert.equal(allTimeUsageSummaryResponse.status, 200, 'expected all-time admin usage summary to succeed');
  const allTimeUsageSummaryPayload = await allTimeUsageSummaryResponse.json();
  assert.equal(allTimeUsageSummaryPayload.usageAnalytics?.isAllTime, true);
  assert.equal(allTimeUsageSummaryPayload.usageAnalytics?.topUserLimit, 1);

  const creditResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/quota-adjustment`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      userID: successPayload.session.userID,
      unitDelta: 120,
      reason: 'Support credit for beta testing'
    })
  });
  assert.equal(creditResponse.status, 200, 'expected admin quota adjustment to succeed');
  const creditPayload = await creditResponse.json();
  assert.equal(creditPayload.quotaSnapshot?.bonusUnits, 120);

  const resetResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/quota-reset`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      userID: successPayload.session.userID,
      resetUsedUnitsTo: 0,
      reason: 'Support reset'
    })
  });
  assert.equal(resetResponse.status, 200, 'expected admin quota reset to succeed');
  const resetPayload = await resetResponse.json();
  assert.equal(resetPayload.quotaSnapshot?.usedUnits, 0);
  assert.equal(resetPayload.quotaSnapshot?.bonusUnits, 120);

  const reconcileResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/reconcile-subscription`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      userID: successPayload.session.userID
    })
  });
  assert.equal(reconcileResponse.status, 200, 'expected admin reconciliation to succeed');
  const reconcilePayload = await reconcileResponse.json();
  assert.equal(reconcilePayload.subscription?.status, 'refunded');

  const preservedOverrideStatusResponse = await fetch(`http://127.0.0.1:${port}/v1/billing/status`, {
    headers: {
      Authorization: `Bearer ${successPayload.session.accessToken}`,
      'X-Trai-App-Account-Token': sharedBody.appAccountToken
    }
  });
  assert.equal(preservedOverrideStatusResponse.status, 200, 'expected billing status after reconciliation to succeed');
  const preservedOverrideStatusPayload = await preservedOverrideStatusResponse.json();
  assert.equal(preservedOverrideStatusPayload.entitlementSnapshot?.plan, 'pro');
  assert.equal(preservedOverrideStatusPayload.entitlementSnapshot?.status, 'active');
  assert.equal(preservedOverrideStatusPayload.entitlementSnapshot?.sourceDescription, 'adminGrant');

  const clearOverrideResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/subscription-override`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      userID: successPayload.session.userID,
      clearOverride: true,
      reason: 'Clear test override'
    })
  });
  assert.equal(clearOverrideResponse.status, 200, 'expected admin subscription override clear to succeed');
  const clearOverridePayload = await clearOverrideResponse.json();
  assert.equal(clearOverridePayload.subscription?.status, 'refunded');
  assert.equal(clearOverridePayload.subscriptionOverride, null);

  const pendingGrantEmail = 'future-pro@example.com';
  const pendingGrantResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/pending-subscription-grant`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify({
      email: pendingGrantEmail,
      reason: 'Future tester pro grant'
    })
  });
  assert.equal(pendingGrantResponse.status, 200, 'expected pending subscription grant to succeed');
  const pendingGrantPayload = await pendingGrantResponse.json();
  assert.equal(pendingGrantPayload.pending, true);
  assert.equal(pendingGrantPayload.grant?.normalized_email, pendingGrantEmail);

  const futureUserToken = signIdentityToken({
    iss: 'https://appleid.apple.com',
    aud: 'Nadav.Trai',
    sub: 'apple-user-future-pro',
    email: pendingGrantEmail,
    nonce: sha256Hex(rawNonce),
    exp: Math.floor(Date.now() / 1000) + 300,
    iat: Math.floor(Date.now() / 1000) - 10
  });
  const futureUserResponse = await postJSON('/v1/auth/apple/exchange', {
    ...sharedBody,
    appleUserID: 'apple-user-future-pro',
    email: pendingGrantEmail,
    displayName: 'Future Pro',
    identityToken: futureUserToken,
    rawNonce
  });
  assert.equal(futureUserResponse.status, 200, 'expected future granted user sign-in to succeed');
  const futureUserPayload = await futureUserResponse.json();
  assert.equal(futureUserPayload.billing?.entitlementSnapshot?.plan, 'pro');
  assert.equal(futureUserPayload.billing?.entitlementSnapshot?.sourceDescription, 'adminGrant');

  const appliedGrantInspectResponse = await fetch(`http://127.0.0.1:${port}/v1/admin/user-inspect?email=${encodeURIComponent(pendingGrantEmail)}`, {
    headers: {
      Authorization: `Bearer ${adminToken}`
    }
  });
  assert.equal(appliedGrantInspectResponse.status, 200, 'expected applied grant user inspection to succeed');
  const appliedGrantInspectPayload = await appliedGrantInspectResponse.json();
  assert.equal(appliedGrantInspectPayload.effectiveSubscription?.plan, 'pro');

  const badNonceResponse = await postJSON('/v1/auth/apple/exchange', {
    ...sharedBody,
    identityToken: goodToken,
    rawNonce: 'wrong-nonce'
  });
  assert.equal(badNonceResponse.status, 401, 'expected nonce mismatch to be rejected');

  const badNoncePayload = await badNonceResponse.json();
  assert.equal(badNoncePayload.error, 'invalid_apple_identity_token');

  console.log('Apple verification check passed.');
} finally {
  child.kill('SIGTERM');
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (child.exitCode != null) {
      throw new Error(`Backend exited early with code ${child.exitCode}`);
    }

    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // Retry until the server is accepting connections.
    }

    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error('Timed out waiting for backend health check.');
}

function signIdentityToken(payload) {
  const header = {
    alg: 'RS256',
    kid: keyID,
    typ: 'JWT'
  };

  const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput, 'utf8'), privateKey);
  return `${signingInput}.${signature.toString('base64url')}`;
}

async function postJSON(pathname, body) {
  return fetch(`http://127.0.0.1:${port}${pathname}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
}

function seedAnalyticsUsage(databasePath, userID) {
  const db = new DatabaseSync(databasePath);
  const now = new Date().toISOString();

  try {
    db.prepare(`
      INSERT INTO usage_ledger (id, user_id, feature, unit_cost, request_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run('ulg_analytics_1', userID, 'agentCoachChat', 3, 'req_analytics_1', now);
    db.prepare(`
      INSERT INTO usage_ledger (id, user_id, feature, unit_cost, request_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run('ulg_analytics_2', userID, 'foodPhotoAnalysis', 6, 'req_analytics_2', now);
    db.prepare(`
      INSERT INTO ai_requests (
        id, user_id, feature, provider, model, action, outcome, latency_ms,
        input_tokens, output_tokens, total_tokens, cached_input_tokens, reasoning_tokens,
        provider_cost_estimate, provider_usage_json, request_format, retry_count, retry_reason, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      'air_analytics_1',
      userID,
      'agentCoachChat',
      'openai',
      'gpt-5.4-mini',
      'test',
      'success',
      120,
      1000,
      200,
      1200,
      100,
      20,
      0.001,
      null,
      'trai_v1',
      0,
      null,
      now
    );
  } finally {
    db.close();
  }
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function deriveStoreKitAppAccountToken(appAccountToken) {
  const normalizedSource = String(appAccountToken ?? '').trim();
  if (!normalizedSource) {
    return null;
  }

  const directUUID = normalizeUUIDString(normalizedSource);
  if (directUUID) {
    return directUUID;
  }

  const digest = crypto
    .createHash('sha256')
    .update(`trai.storekit.appAccountToken.v1:${normalizedSource}`)
    .digest();
  const bytes = Array.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  return [
    bytes.slice(0, 4).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
    bytes.slice(4, 6).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
    bytes.slice(6, 8).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
    bytes.slice(8, 10).map((byte) => byte.toString(16).padStart(2, '0')).join(''),
    bytes.slice(10, 16).map((byte) => byte.toString(16).padStart(2, '0')).join('')
  ].join('-');
}

function normalizeUUIDString(value) {
  const normalizedValue = String(value ?? '').trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(normalizedValue)
    ? normalizedValue
    : null;
}

function createStoreKitCertificateChain(rootDirectory) {
  const opensslConfigPath = path.join(rootDirectory, 'openssl.cnf');
  fs.writeFileSync(opensslConfigPath, [
    '[ root_ca ]',
    'basicConstraints=critical,CA:TRUE',
    'keyUsage=critical,keyCertSign,cRLSign',
    'subjectKeyIdentifier=hash',
    '',
    '[ intermediate_ca ]',
    'basicConstraints=critical,CA:TRUE,pathlen:0',
    'keyUsage=critical,keyCertSign,cRLSign',
    'authorityKeyIdentifier=keyid:always,issuer',
    'subjectKeyIdentifier=hash',
    '',
    '[ leaf_signing ]',
    'basicConstraints=critical,CA:FALSE',
    'keyUsage=critical,digitalSignature',
    'extendedKeyUsage=codeSigning',
    'authorityKeyIdentifier=keyid:always,issuer',
    'subjectKeyIdentifier=hash',
    ''
  ].join('\n'));

  const rootKeyPath = path.join(rootDirectory, 'storekit-root-key.pem');
  const rootCertificatePath = path.join(rootDirectory, 'storekit-root-cert.pem');
  const intermediateKeyPath = path.join(rootDirectory, 'storekit-intermediate-key.pem');
  const intermediateCSRPath = path.join(rootDirectory, 'storekit-intermediate.csr');
  const intermediateCertificatePath = path.join(rootDirectory, 'storekit-intermediate-cert.pem');
  const leafKeyPath = path.join(rootDirectory, 'storekit-leaf-key.pem');
  const leafCSRPath = path.join(rootDirectory, 'storekit-leaf.csr');
  const leafCertificatePath = path.join(rootDirectory, 'storekit-leaf-cert.pem');

  execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', rootKeyPath]);
  execFileSync('openssl', [
    'req', '-x509', '-new', '-key', rootKeyPath, '-sha256', '-days', '3650',
    '-subj', '/CN=Unit Test Root CA',
    '-out', rootCertificatePath,
    '-extensions', 'root_ca',
    '-config', opensslConfigPath
  ]);

  execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', intermediateKeyPath]);
  execFileSync('openssl', [
    'req', '-new', '-key', intermediateKeyPath, '-subj', '/CN=Unit Test Intermediate CA', '-out', intermediateCSRPath
  ]);
  execFileSync('openssl', [
    'x509', '-req', '-in', intermediateCSRPath, '-CA', rootCertificatePath, '-CAkey', rootKeyPath,
    '-CAcreateserial', '-out', intermediateCertificatePath, '-days', '3650', '-sha256',
    '-extensions', 'intermediate_ca', '-extfile', opensslConfigPath
  ]);

  execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', leafKeyPath]);
  execFileSync('openssl', [
    'req', '-new', '-key', leafKeyPath, '-subj', '/CN=Unit Test StoreKit Signing', '-out', leafCSRPath
  ]);
  execFileSync('openssl', [
    'x509', '-req', '-in', leafCSRPath, '-CA', intermediateCertificatePath, '-CAkey', intermediateKeyPath,
    '-CAcreateserial', '-out', leafCertificatePath, '-days', '3650', '-sha256',
    '-extensions', 'leaf_signing', '-extfile', opensslConfigPath
  ]);

  return {
    rootCertificatePath,
    leafKeyPath,
    x5c: [
      new X509Certificate(fs.readFileSync(leafCertificatePath)).raw.toString('base64'),
      new X509Certificate(fs.readFileSync(intermediateCertificatePath)).raw.toString('base64'),
      new X509Certificate(fs.readFileSync(rootCertificatePath)).raw.toString('base64')
    ]
  };
}

function createSignedStoreKitTransaction(fixtures, payload) {
  const header = {
    alg: 'ES256',
    x5c: fixtures.x5c
  };

  const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.sign('sha256', Buffer.from(signingInput, 'utf8'), {
    key: fs.readFileSync(fixtures.leafKeyPath, 'utf8'),
    dsaEncoding: 'ieee-p1363'
  });

  return `${signingInput}.${signature.toString('base64url')}`;
}

function createSignedAppStoreNotification(fixtures, payload) {
  return createSignedStoreKitTransaction(fixtures, payload);
}
