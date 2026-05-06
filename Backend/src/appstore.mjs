import crypto from 'node:crypto';

export function createAppStoreHelpers({
  db,
  config,
  trustedAppStoreRoots,
  HttpError,
  createID,
  isoNow,
  PRODUCT_DEFINITIONS,
  normalizeNumericIdentifier,
  normalizeMillisecondsTimestamp,
  normalizeDateString,
  base64URLDecode,
  ensureSubscription,
  planRank
}) {
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  function findKnownProduct(productID) {
    return PRODUCT_DEFINITIONS.find((candidate) => candidate.id === productID);
  }

  function normalizeStoreKitAppAccountToken(value) {
    if (typeof value !== 'string') {
      return null;
    }

    const normalizedValue = value.trim().toLowerCase();
    return uuidPattern.test(normalizedValue) ? normalizedValue : null;
  }

  function effectiveTimestamp(now) {
    return Date.parse(now) || Date.now();
  }

  function isEntitlementActiveAt(entitlement, now) {
    return entitlement.revocationDate == null
      && (entitlement.expirationDate == null || Date.parse(entitlement.expirationDate) > effectiveTimestamp(now));
  }

  function selectPreferredEntitlement(entitlements) {
    return entitlements.reduce((best, current) => {
      if (!best) {
        return current;
      }

      const bestRank = planRank(best.product.plan);
      const currentRank = planRank(current.product.plan);
      if (currentRank !== bestRank) {
        return currentRank > bestRank ? current : best;
      }

      const bestExpiry = best.expirationDate ? Date.parse(best.expirationDate) : Number.POSITIVE_INFINITY;
      const currentExpiry = current.expirationDate ? Date.parse(current.expirationDate) : Number.POSITIVE_INFINITY;
      return currentExpiry > bestExpiry ? current : best;
    }, null);
  }

  async function applyStoreKitSubscriptionState(userID, entitlements, now) {
    const currentSubscription = await ensureSubscription(userID, now);

    const activeEntitlements = entitlements
      .filter((entitlement) => isEntitlementActiveAt(entitlement, now))
      .map((entitlement) => ({
        ...entitlement,
        product: findKnownProduct(entitlement.productID)
      }))
      .filter((entitlement) => entitlement.product);

    if (activeEntitlements.length === 0) {
      if (shouldPreserveNotificationManagedState(currentSubscription)) {
        await updateSubscriptionRecord(userID, {
          plan: currentSubscription.plan,
          status: currentSubscription.status,
          source: subscriptionSource(currentSubscription),
          sourceTransactionID: currentSubscription.source_transaction_id ?? null,
          renewsAt: currentSubscription.renews_at ?? null,
          expiresAt: currentSubscription.expires_at ?? null
        }, now);
      } else {
        const ledgerBackedEntitlement = await findBestStoredActiveEntitlement(userID, now);
        if (shouldPreserveLedgerBackedStoreKitState(currentSubscription, ledgerBackedEntitlement)) {
          await updateSubscriptionRecord(userID, {
            plan: ledgerBackedEntitlement.product.plan,
            status: statusForActiveEntitlement(currentSubscription, ledgerBackedEntitlement),
            source: 'appStore',
            sourceTransactionID: String(
              ledgerBackedEntitlement.originalTransactionID ?? ledgerBackedEntitlement.transactionID
            ),
            renewsAt: ledgerBackedEntitlement.expirationDate ?? null,
            expiresAt: ledgerBackedEntitlement.expirationDate ?? null
          }, now);
        } else if (shouldPreserveNonStoreKitSubscription(currentSubscription)) {
          await updateSubscriptionRecord(userID, {
            plan: currentSubscription.plan,
            status: currentSubscription.status,
            source: subscriptionSource(currentSubscription),
            sourceTransactionID: currentSubscription.source_transaction_id ?? null,
            renewsAt: currentSubscription.renews_at ?? null,
            expiresAt: currentSubscription.expires_at ?? null
          }, now);
        } else {
          await updateSubscriptionRecord(userID, {
            plan: 'free',
            status: 'active',
            source: 'system',
            sourceTransactionID: null,
            renewsAt: null,
            expiresAt: null
          }, now);
        }
      }
      return;
    }

    const selectedEntitlement = selectPreferredEntitlement(activeEntitlements);

    await updateSubscriptionRecord(userID, {
      plan: selectedEntitlement.product.plan,
      status: statusForActiveEntitlement(currentSubscription, selectedEntitlement),
      source: 'appStore',
      sourceTransactionID: String(selectedEntitlement.originalTransactionID ?? selectedEntitlement.transactionID),
      renewsAt: selectedEntitlement.expirationDate ?? null,
      expiresAt: selectedEntitlement.expirationDate ?? null
    }, now);
  }

  function shouldPreserveNotificationManagedState(subscription) {
    return subscriptionSource(subscription) === 'appStore'
      && new Set(['gracePeriod', 'billingRetry', 'expired', 'refunded', 'revoked'])
      .has(subscription?.status);
  }

  function shouldPreserveNonStoreKitSubscription(subscription) {
    return Boolean(
      subscription
      && subscription.plan !== 'free'
      && subscriptionSource(subscription) !== 'appStore'
    );
  }

  function shouldPreserveLedgerBackedStoreKitState(subscription, entitlement) {
    if (!entitlement) {
      return false;
    }

    return subscriptionSource(subscription) === 'appStore'
      && !new Set(['refunded', 'revoked']).has(subscription?.status);
  }

  function subscriptionSource(subscription) {
    if (typeof subscription?.source === 'string' && subscription.source.length > 0) {
      return subscription.source;
    }

    if (subscription?.source_transaction_id != null) {
      return 'appStore';
    }

    if (subscription?.plan === 'developer') {
      return 'developer';
    }

    if (subscription?.plan && subscription.plan !== 'free') {
      return 'adminGrant';
    }

    return 'system';
  }

  function statusForActiveEntitlement(subscription, entitlement) {
    const currentSourceTransactionID = subscription?.source_transaction_id != null
      ? String(subscription.source_transaction_id)
      : null;
    const entitlementSourceTransactionID = String(
      entitlement.originalTransactionID ?? entitlement.transactionID
    );

    if (
      currentSourceTransactionID === entitlementSourceTransactionID &&
      new Set(['gracePeriod', 'billingRetry']).has(subscription?.status)
    ) {
      return subscription.status;
    }

    return subscription?.status === 'trial' ? 'trial' : 'active';
  }

  async function applyNotificationLifecycleUpdate(userID, { notification, transaction, renewalInfo }, now) {
    const currentSubscription = await ensureSubscription(userID, now);
    const status = deriveSubscriptionStatus(notification, renewalInfo, transaction, currentSubscription.status);
    const plan = deriveSubscriptionPlan(transaction, renewalInfo, currentSubscription.plan);
    const sourceTransactionID = String(
      transaction?.originalTransactionID
        ?? renewalInfo?.originalTransactionId
        ?? currentSubscription.source_transaction_id
        ?? ''
    ) || null;
    const renewsAt = deriveRenewalDate(notification, renewalInfo, transaction, currentSubscription.renews_at);
    const expiresAt = deriveExpirationDate(notification, renewalInfo, transaction, currentSubscription.expires_at);

    await updateSubscriptionRecord(userID, {
      plan,
      status,
      source: 'appStore',
      sourceTransactionID,
      renewsAt,
      expiresAt
    }, now);
  }

  async function reconcileUserSubscriptionFromLedger(userID, now) {
    await ensureSubscription(userID, now);

    const transactions = await db.prepare(`
      SELECT *
      FROM storekit_transactions
      WHERE user_id = ?
      ORDER BY COALESCE(signed_date, updated_at) DESC
    `).all(userID);

    const entitlements = transactions.map(storeKitTransactionRowToEntitlement);
    await applyStoreKitSubscriptionState(userID, entitlements, now);

    const latestNotificationRow = await db.prepare(`
      SELECT *
      FROM app_store_notifications
      WHERE related_original_transaction_id IN (
        SELECT original_transaction_id
        FROM storekit_transactions
        WHERE user_id = ?
      )
      ORDER BY processed_at DESC
      LIMIT 1
    `).get(userID);

    let appliedNotificationType = null;
    if (latestNotificationRow?.raw_payload) {
      const notification = verifyAndDecodeAppStoreNotification(latestNotificationRow.raw_payload);
      const signedTransactionInfo = notification.data?.signedTransactionInfo ?? null;
      const signedRenewalInfo = notification.data?.signedRenewalInfo ?? null;
      const transaction = signedTransactionInfo ? verifyAndDecodeStoreKitTransaction(signedTransactionInfo) : null;
      const renewalInfo = signedRenewalInfo ? verifyAndDecodeAppStoreRenewalInfo(signedRenewalInfo) : null;
      await applyNotificationLifecycleUpdate(userID, { notification, transaction, renewalInfo }, now);
      appliedNotificationType = notification.notificationType ?? null;
    }

    const subscription = await ensureSubscription(userID, now);
    return {
      userID,
      reconciledAt: now,
      transactionCount: transactions.length,
      appliedNotificationType,
      subscription
    };
  }

  async function updateSubscriptionRecord(userID, { plan, status, source, sourceTransactionID, renewsAt, expiresAt }, now) {
    await db.prepare(`
      UPDATE subscriptions
      SET plan = ?, status = ?, source = ?, source_transaction_id = ?, renews_at = ?, expires_at = ?, updated_at = ?
      WHERE user_id = ?
    `).run(plan, status, source, sourceTransactionID, renewsAt, expiresAt, now, userID);
  }

  function normalizeStoreKitEntitlement(value) {
    if (!value || typeof value !== 'object') {
      return null;
    }

    if (typeof value.productID !== 'string' || value.productID.length === 0) {
      return null;
    }

    const transactionID = normalizeNumericIdentifier(value.transactionID);
    const originalTransactionID = normalizeNumericIdentifier(value.originalTransactionID);
    if (transactionID == null || originalTransactionID == null) {
      return null;
    }

    return {
      productID: value.productID,
      transactionID,
      originalTransactionID,
      purchaseDate: normalizeDateString(value.purchaseDate),
      expirationDate: normalizeDateString(value.expirationDate),
      revocationDate: normalizeDateString(value.revocationDate),
      isUpgraded: Boolean(value.isUpgraded),
      appAccountToken: normalizeStoreKitAppAccountToken(value.appAccountToken),
      environment: typeof value.environment === 'string' ? value.environment : null,
      signedDate: normalizeDateString(value.signedDate),
      rawJWS: typeof value.rawJWS === 'string' ? value.rawJWS : null
    };
  }

  async function persistAppStoreNotification(notification, rawPayload, transaction, renewalInfo, now) {
    await db.prepare(`
      INSERT INTO app_store_notifications (
        id, notification_uuid, notification_type, subtype, environment, related_transaction_id,
        related_original_transaction_id, raw_payload, created_at, processed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(notification_uuid) DO UPDATE SET
        notification_type = excluded.notification_type,
        subtype = excluded.subtype,
        environment = excluded.environment,
        related_transaction_id = excluded.related_transaction_id,
        related_original_transaction_id = excluded.related_original_transaction_id,
        raw_payload = excluded.raw_payload,
        processed_at = excluded.processed_at
    `).run(
      createID('asn'),
      notification.notificationUUID,
      notification.notificationType ?? null,
      notification.subtype ?? null,
      notification.data?.environment ?? notification.environment ?? null,
      transaction ? String(transaction.transactionID) : null,
      transaction
        ? String(transaction.originalTransactionID)
        : renewalInfo?.originalTransactionId
          ? String(renewalInfo.originalTransactionId)
          : null,
      rawPayload,
      now,
      now
    );
  }

  async function findUserIDForStoreKitTransaction(transaction) {
    const byOriginalTransaction = await db.prepare(`
      SELECT user_id
      FROM storekit_transactions
      WHERE original_transaction_id = ?
      ORDER BY updated_at DESC
      LIMIT 1
    `).get(String(transaction.originalTransactionID));

    if (byOriginalTransaction?.user_id) {
      return byOriginalTransaction.user_id;
    }

    const bySubscription = await db.prepare(`
      SELECT user_id
      FROM subscriptions
      WHERE source_transaction_id = ?
      LIMIT 1
    `).get(String(transaction.originalTransactionID));

    if (bySubscription?.user_id) {
      return bySubscription.user_id;
    }

    const byTransaction = await db.prepare(`
      SELECT user_id
      FROM storekit_transactions
      WHERE transaction_id = ?
      ORDER BY updated_at DESC
      LIMIT 1
    `).get(String(transaction.transactionID));

    return byTransaction?.user_id ?? null;
  }

  async function findUserIDForOriginalTransaction(originalTransactionId) {
    if (!originalTransactionId) {
      return null;
    }

    const byTransaction = await db.prepare(`
      SELECT user_id
      FROM storekit_transactions
      WHERE original_transaction_id = ?
      ORDER BY updated_at DESC
      LIMIT 1
    `).get(String(originalTransactionId));

    if (byTransaction?.user_id) {
      return byTransaction.user_id;
    }

    const bySubscription = await db.prepare(`
      SELECT user_id
      FROM subscriptions
      WHERE source_transaction_id = ?
      LIMIT 1
    `).get(String(originalTransactionId));

    return bySubscription?.user_id ?? null;
  }

  async function findBestStoredActiveEntitlement(userID, now) {
    const rows = await db.prepare(`
      SELECT *
      FROM storekit_transactions
      WHERE user_id = ?
        AND revocation_date IS NULL
      ORDER BY COALESCE(expires_date, '9999-12-31T23:59:59.999Z') DESC,
        COALESCE(signed_date, updated_at) DESC
    `).all(userID);

    const activeEntitlements = rows
      .map(storeKitTransactionRowToEntitlement)
      .filter((entitlement) => isEntitlementActiveAt(entitlement, now))
      .map((entitlement) => ({
        ...entitlement,
        product: findKnownProduct(entitlement.productID)
      }))
      .filter((entitlement) => entitlement.product);

    return selectPreferredEntitlement(activeEntitlements);
  }

  function storeKitTransactionRowToEntitlement(row) {
    return {
      productID: row.product_id,
      transactionID: normalizeNumericIdentifier(row.transaction_id),
      originalTransactionID: normalizeNumericIdentifier(row.original_transaction_id),
      purchaseDate: row.purchase_date,
      expirationDate: row.expires_date,
      revocationDate: row.revocation_date,
      isUpgraded: false,
      appAccountToken: normalizeStoreKitAppAccountToken(row.app_account_token),
      environment: row.environment ?? null,
      signedDate: row.signed_date ?? null,
      rawJWS: row.raw_jws ?? null
    };
  }

  function verifyAndDecodeStoreKitTransaction(compactJWS) {
    const token = parseCompactJWS(compactJWS);
    const header = token.header;
    const payload = token.payload;

    if (header.alg !== 'ES256') {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction uses an unsupported signing algorithm.'
      });
    }

    if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction certificate chain is missing.'
      });
    }

    const certificates = header.x5c.map((encodedCertificate) => parseX5CCertificate(encodedCertificate));
    verifyCertificateChain(certificates, payload.signedDate);

    const isValidSignature = crypto.verify(
      'sha256',
      Buffer.from(`${token.parts[0]}.${token.parts[1]}`, 'utf8'),
      {
        key: certificates[0].publicKey,
        dsaEncoding: 'ieee-p1363'
      },
      base64URLDecode(token.parts[2])
    );

    if (!isValidSignature) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction signature verification failed.'
      });
    }

    validateStoreKitPayload(payload);

    return {
      productID: payload.productId,
      transactionID: normalizeNumericIdentifier(payload.transactionId),
      originalTransactionID: normalizeNumericIdentifier(payload.originalTransactionId) ?? normalizeNumericIdentifier(payload.transactionId),
      purchaseDate: normalizeDateString(payload.purchaseDate),
      expirationDate: normalizeDateString(payload.expiresDate),
      revocationDate: normalizeDateString(payload.revocationDate),
      isUpgraded: Boolean(payload.isUpgraded),
      appAccountToken: normalizeStoreKitAppAccountToken(payload.appAccountToken),
      environment: typeof payload.environment === 'string' ? payload.environment : null,
      signedDate: normalizeDateString(payload.signedDate),
      rawJWS: compactJWS
    };
  }

  function parseCompactJWS(token) {
    const parts = String(token ?? '').split('.');
    if (parts.length !== 3) {
      throw new HttpError(400, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction must be a three-part JWS.'
      });
    }

    let header;
    let payload;

    try {
      header = JSON.parse(base64URLDecode(parts[0]).toString('utf8'));
      payload = JSON.parse(base64URLDecode(parts[1]).toString('utf8'));
    } catch {
      throw new HttpError(400, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction contains malformed JSON.'
      });
    }

    return {
      parts,
      header,
      payload
    };
  }

  function parseX5CCertificate(base64DER) {
    try {
      const der = Buffer.from(base64DER, 'base64');
      return new crypto.X509Certificate(der);
    } catch {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction contains an invalid signing certificate.'
      });
    }
  }

  function verifyCertificateChain(certificates, signedDateValue) {
    const verificationDate = normalizeVerificationDate(signedDateValue);

    for (let index = 0; index < certificates.length - 1; index += 1) {
      const certificate = certificates[index];
      const issuer = certificates[index + 1];

      if (!certificate.verify(issuer.publicKey)) {
        throw new HttpError(401, {
          error: 'invalid_storekit_transaction',
          message: 'StoreKit transaction certificate chain is invalid.'
        });
      }

      ensureCertificateValidAt(certificate, verificationDate);
    }

    const root = certificates[certificates.length - 1];
    if (!root.verify(root.publicKey)) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit root certificate is not self-signed.'
      });
    }

    ensureCertificateValidAt(root, verificationDate);

    if (!isTrustedAppStoreRoot(root)) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit root certificate is not trusted.'
      });
    }
  }

  function normalizeVerificationDate(value) {
    const parsed = normalizeMillisecondsTimestamp(value) ?? Date.now();
    return new Date(parsed);
  }

  function ensureCertificateValidAt(certificate, date) {
    const notBefore = Date.parse(certificate.validFrom);
    const notAfter = Date.parse(certificate.validTo);
    const timestamp = date.getTime();

    if (Number.isNaN(notBefore) || Number.isNaN(notAfter) || timestamp < notBefore || timestamp > notAfter) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit certificate was not valid at the transaction signing time.'
      });
    }
  }

  function isTrustedAppStoreRoot(certificate) {
    if (trustedAppStoreRoots.some((trustedRoot) => trustedRoot.fingerprint256 === certificate.fingerprint256)) {
      return true;
    }

    return config.appStoreTrustedRootSubjects.some((subjectFragment) => certificate.subject.includes(subjectFragment));
  }

  function validateStoreKitPayload(payload) {
    if (typeof payload.bundleId !== 'string' || !config.appStoreExpectedBundleIDs.includes(payload.bundleId)) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction bundle identifier is invalid.'
      });
    }

    if (typeof payload.productId !== 'string' || !findKnownProduct(payload.productId)) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction product identifier is not recognized.'
      });
    }

    if (normalizeNumericIdentifier(payload.transactionId) == null) {
      throw new HttpError(401, {
        error: 'invalid_storekit_transaction',
        message: 'StoreKit transaction identifier is invalid.'
      });
    }

    // TestFlight sends App Store-signed transactions with environment=Sandbox.
    // Production backend still validates signature, bundle, product, and ownership.
  }

  async function persistStoreKitTransactions(userID, transactions, signedTransactions, now) {
    for (const [index, transaction] of transactions.entries()) {
      const rawJWS = transaction.rawJWS ?? signedTransactions[index] ?? null;
      if (!rawJWS) {
        continue;
      }

      await db.prepare(`
        INSERT INTO storekit_transactions (
          id, user_id, environment, product_id, transaction_id, original_transaction_id, purchase_date,
          expires_date, revocation_date, signed_date, app_account_token, raw_jws, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(transaction_id) DO UPDATE SET
          environment = excluded.environment,
          product_id = excluded.product_id,
          original_transaction_id = excluded.original_transaction_id,
          purchase_date = excluded.purchase_date,
          expires_date = excluded.expires_date,
          revocation_date = excluded.revocation_date,
          signed_date = excluded.signed_date,
          app_account_token = excluded.app_account_token,
          raw_jws = excluded.raw_jws,
          updated_at = excluded.updated_at
      `).run(
        createID('stx'),
        userID,
        transaction.environment ?? null,
        transaction.productID,
        String(transaction.transactionID),
        String(transaction.originalTransactionID),
        transaction.purchaseDate ?? null,
        transaction.expirationDate ?? null,
        transaction.revocationDate ?? null,
        transaction.signedDate ?? null,
        transaction.appAccountToken ?? null,
        rawJWS,
        now,
        now
      );
    }
  }

  function verifyAndDecodeAppStoreNotification(compactJWS) {
    const token = parseCompactJWS(compactJWS);
    const header = token.header;
    const payload = token.payload;

    if (header.alg !== 'ES256') {
      throw new HttpError(401, {
        error: 'invalid_app_store_notification',
        message: 'App Store notification uses an unsupported signing algorithm.'
      });
    }

    if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
      throw new HttpError(401, {
        error: 'invalid_app_store_notification',
        message: 'App Store notification certificate chain is missing.'
      });
    }

    const certificates = header.x5c.map((encodedCertificate) => parseX5CCertificate(encodedCertificate));
    verifyCertificateChain(certificates, payload.signedDate);

    const isValidSignature = crypto.verify(
      'sha256',
      Buffer.from(`${token.parts[0]}.${token.parts[1]}`, 'utf8'),
      {
        key: certificates[0].publicKey,
        dsaEncoding: 'ieee-p1363'
      },
      base64URLDecode(token.parts[2])
    );

    if (!isValidSignature) {
      throw new HttpError(401, {
        error: 'invalid_app_store_notification',
        message: 'App Store notification signature verification failed.'
      });
    }

    validateAppStoreNotificationPayload(payload);
    return payload;
  }

  function verifyAndDecodeAppStoreRenewalInfo(compactJWS) {
    const token = parseCompactJWS(compactJWS);
    const header = token.header;
    const payload = token.payload;

    if (header.alg !== 'ES256') {
      throw new HttpError(401, {
        error: 'invalid_app_store_renewal_info',
        message: 'App Store renewal info uses an unsupported signing algorithm.'
      });
    }

    if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
      throw new HttpError(401, {
        error: 'invalid_app_store_renewal_info',
        message: 'App Store renewal info certificate chain is missing.'
      });
    }

    const certificates = header.x5c.map((encodedCertificate) => parseX5CCertificate(encodedCertificate));
    verifyCertificateChain(certificates, payload.signedDate);

    const isValidSignature = crypto.verify(
      'sha256',
      Buffer.from(`${token.parts[0]}.${token.parts[1]}`, 'utf8'),
      {
        key: certificates[0].publicKey,
        dsaEncoding: 'ieee-p1363'
      },
      base64URLDecode(token.parts[2])
    );

    if (!isValidSignature) {
      throw new HttpError(401, {
        error: 'invalid_app_store_renewal_info',
        message: 'App Store renewal info signature verification failed.'
      });
    }

    validateAppStoreRenewalInfoPayload(payload);
    return payload;
  }

  function validateAppStoreNotificationPayload(payload) {
    if (typeof payload.notificationUUID !== 'string' || payload.notificationUUID.length === 0) {
      throw new HttpError(401, {
        error: 'invalid_app_store_notification',
        message: 'App Store notification UUID is missing.'
      });
    }

    const bundleID = payload.data?.bundleId;
    if (bundleID && !config.appStoreExpectedBundleIDs.includes(bundleID)) {
      throw new HttpError(401, {
        error: 'invalid_app_store_notification',
        message: 'App Store notification bundle identifier is invalid.'
      });
    }

    // TestFlight subscription notifications can also be Sandbox while using
    // the shared production backend/database.
  }

  function validateAppStoreRenewalInfoPayload(payload) {
    if (payload.bundleId && !config.appStoreExpectedBundleIDs.includes(payload.bundleId)) {
      throw new HttpError(401, {
        error: 'invalid_app_store_renewal_info',
        message: 'App Store renewal info bundle identifier is invalid.'
      });
    }

    if (payload.autoRenewProductId && !findKnownProduct(payload.autoRenewProductId)) {
      throw new HttpError(401, {
        error: 'invalid_app_store_renewal_info',
        message: 'App Store renewal info product identifier is not recognized.'
      });
    }

    // Keep Sandbox renewal metadata valid for TestFlight accounts.
  }

  function deriveSubscriptionStatus(notification, renewalInfo, transaction, currentStatus) {
    const notificationType = notification.notificationType ?? '';
    const subtype = notification.subtype ?? '';

    if (notificationType === 'REFUND' || notificationType === 'REFUND_DECLINED') {
      return notificationType === 'REFUND' ? 'refunded' : currentStatus;
    }

    if (notificationType === 'REVOKE') {
      return 'revoked';
    }

    if (notificationType === 'EXPIRED') {
      return 'expired';
    }

    if (notificationType === 'GRACE_PERIOD_EXPIRED') {
      return 'billingRetry';
    }

    if (notificationType === 'DID_FAIL_TO_RENEW') {
      return subtype === 'GRACE_PERIOD' ? 'gracePeriod' : 'billingRetry';
    }

    if (renewalInfo?.gracePeriodExpiresDate && Date.parse(normalizeDateString(renewalInfo.gracePeriodExpiresDate) ?? '') > Date.now()) {
      return 'gracePeriod';
    }

    if (renewalInfo?.isInBillingRetryPeriod === true || renewalInfo?.isInBillingRetryPeriod === 1 || renewalInfo?.isInBillingRetryPeriod === '1') {
      return 'billingRetry';
    }

    if (transaction?.revocationDate) {
      return 'revoked';
    }

    return currentStatus === 'trial' ? 'trial' : 'active';
  }

  function deriveSubscriptionPlan(transaction, renewalInfo, currentPlan) {
    const productID = transaction?.productID ?? renewalInfo?.autoRenewProductId ?? renewalInfo?.productId ?? null;
    const product = findKnownProduct(productID);
    return product?.plan ?? currentPlan;
  }

  function deriveRenewalDate(notification, renewalInfo, transaction, currentRenewalDate) {
    return transaction?.expirationDate
      ?? normalizeDateString(renewalInfo?.gracePeriodExpiresDate)
      ?? currentRenewalDate
      ?? null;
  }

  function deriveExpirationDate(notification, renewalInfo, transaction, currentExpirationDate) {
    const notificationType = notification.notificationType ?? '';
    if (notificationType === 'EXPIRED' || notificationType === 'REFUND' || notificationType === 'REVOKE') {
      return transaction?.revocationDate
        ?? transaction?.expirationDate
        ?? normalizeDateString(renewalInfo?.gracePeriodExpiresDate)
        ?? isoNow();
    }

    return transaction?.expirationDate
      ?? normalizeDateString(renewalInfo?.gracePeriodExpiresDate)
      ?? currentExpirationDate
      ?? null;
  }

  return {
    applyStoreKitSubscriptionState,
    applyNotificationLifecycleUpdate,
    reconcileUserSubscriptionFromLedger,
    updateSubscriptionRecord,
    normalizeStoreKitEntitlement,
    persistAppStoreNotification,
    findUserIDForStoreKitTransaction,
    findUserIDForOriginalTransaction,
    storeKitTransactionRowToEntitlement,
    verifyAndDecodeStoreKitTransaction,
    persistStoreKitTransactions,
    verifyAndDecodeAppStoreNotification,
    verifyAndDecodeAppStoreRenewalInfo
  };
}
