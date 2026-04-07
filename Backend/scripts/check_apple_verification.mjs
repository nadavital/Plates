import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { X509Certificate } from 'node:crypto';

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
    TRAI_ENVIRONMENT: 'staging',
    TRAI_DB_PATH: databasePath,
    APPLE_JWKS_PATH: jwksPath,
    APPLE_EXPECTED_AUDIENCES: 'Nadav.Trai',
    APP_STORE_EXPECTED_BUNDLE_IDS: 'Nadav.Trai',
    APP_STORE_ROOT_CERT_PATHS: storeKitFixtures.rootCertificatePath,
    APP_STORE_TRUSTED_ROOT_SUBJECTS: 'Unit Test Root CA',
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

  const rawNonce = crypto.randomBytes(16).toString('hex');
  const sharedBody = {
    installationID: 'local-installation',
    appAccountToken: 'trai_anon_localtest',
    authorizationCode: 'local-auth-code',
    appleUserID: 'apple-user-123',
    email: 'tester@example.com',
    displayName: 'Local Tester'
  };

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

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
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
