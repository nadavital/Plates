import crypto from 'node:crypto';
import fs from 'node:fs';

export function createAuthHelpers({
  db,
  config,
  HttpError,
  createID,
  hashToken,
  looksLikeJWT,
  parseJWT,
  validateAppleClaims,
  base64URLDecode,
  ensureSubscription,
  findUserIDForOriginalTransaction
}) {
  const appleJWKSCache = {
    fetchedAt: 0,
    keys: []
  };

  async function verifyAppleIdentity(body) {
    if (config.allowDevAppleBypass && !looksLikeJWT(body.identityToken)) {
      return {
        appleUserID: body.appleUserID,
        email: body.email ?? null
      };
    }

    const token = parseJWT(body.identityToken);
    validateAppleClaims(token.payload, body);

    const signingKey = await getAppleSigningKey(token.header.kid);
    const signingInput = `${token.parts[0]}.${token.parts[1]}`;
    const signature = base64URLDecode(token.parts[2]);
    const publicKey = crypto.createPublicKey({
      key: signingKey,
      format: 'jwk'
    });

    const isValidSignature = crypto.verify(
      'RSA-SHA256',
      Buffer.from(signingInput, 'utf8'),
      publicKey,
      signature
    );

    if (!isValidSignature) {
      throw new HttpError(401, {
        error: 'invalid_apple_identity_token',
        message: 'Apple identity token signature verification failed.'
      });
    }

    return {
      appleUserID: token.payload.sub,
      email: token.payload.email ?? null
    };
  }

  function findOrCreateUserFromApple(body, now) {
    const identity = db.prepare(`
      SELECT users.id, users.status, auth_identities.email, auth_identities.display_name
      FROM auth_identities
      JOIN users ON users.id = auth_identities.user_id
      WHERE auth_identities.provider = ? AND auth_identities.provider_user_id = ?
    `).get('apple', body.appleUserID);

    if (identity) {
      const nextEmail = body.email ?? identity.email ?? null;
      const nextDisplayName = body.displayName ?? identity.display_name ?? null;

      db.prepare(`
        UPDATE auth_identities
        SET email = ?, display_name = ?, updated_at = ?
        WHERE provider = ? AND provider_user_id = ?
      `).run(nextEmail, nextDisplayName, now, 'apple', body.appleUserID);

      ensureSubscription(identity.id, now);
      return {
        id: identity.id,
        email: nextEmail,
        displayName: nextDisplayName
      };
    }

    const userID = createID('usr');
    db.prepare(`
      INSERT INTO users (id, created_at, updated_at, status)
      VALUES (?, ?, ?, ?)
    `).run(userID, now, now, 'active');

    db.prepare(`
      INSERT INTO auth_identities (
        id, user_id, provider, provider_user_id, email, display_name, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      createID('aid'),
      userID,
      'apple',
      body.appleUserID,
      body.email ?? null,
      body.displayName ?? null,
      now,
      now
    );

    ensureSubscription(userID, now);

    return {
      id: userID,
      email: body.email ?? null,
      displayName: body.displayName ?? null
    };
  }

  function createSession(userID, installationID, appAccountToken, now) {
    const accessToken = crypto.randomBytes(32).toString('hex');
    const refreshToken = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

    const sessionRecord = {
      id: createID('ses'),
      user_id: userID,
      installation_id: installationID,
      app_account_token: appAccountToken,
      access_token_hash: hashToken(accessToken),
      refresh_token_hash: hashToken(refreshToken),
      expires_at: expiresAt,
      created_at: now,
      updated_at: now,
      accessToken,
      refreshToken
    };

    db.prepare(`
      INSERT INTO sessions (
        id, user_id, installation_id, app_account_token, access_token_hash, refresh_token_hash, expires_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      sessionRecord.id,
      sessionRecord.user_id,
      sessionRecord.installation_id,
      sessionRecord.app_account_token,
      sessionRecord.access_token_hash,
      sessionRecord.refresh_token_hash,
      sessionRecord.expires_at,
      sessionRecord.created_at,
      sessionRecord.updated_at
    );

    return sessionRecord;
  }

  function rotateSessionTokens(sessionID, now) {
    const accessToken = crypto.randomBytes(32).toString('hex');
    const refreshToken = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

    db.prepare(`
      UPDATE sessions
      SET access_token_hash = ?, refresh_token_hash = ?, expires_at = ?, updated_at = ?
      WHERE id = ?
    `).run(hashToken(accessToken), hashToken(refreshToken), expiresAt, now, sessionID);

    return {
      accessToken,
      refreshToken,
      expiresAt
    };
  }

  function requireSession(req) {
    const authorization = req.headers.authorization ?? '';
    const appAccountToken = req.headers['x-trai-app-account-token'];

    if (!authorization.startsWith('Bearer ') || !appAccountToken) {
      throw new HttpError(401, {
        error: 'unauthorized',
        message: 'Missing session or app account token.'
      });
    }

    const accessToken = authorization.slice('Bearer '.length);
    const tokenHash = hashToken(accessToken);
    const row = db.prepare(`
      SELECT
        sessions.id,
        sessions.user_id,
        sessions.installation_id,
        sessions.app_account_token,
        sessions.expires_at,
        users.status
      FROM sessions
      JOIN users ON users.id = sessions.user_id
      WHERE sessions.access_token_hash = ?
    `).get(tokenHash);

    if (!row) {
      throw new HttpError(401, {
        error: 'unauthorized',
        message: 'Session not found.'
      });
    }

    if (row.app_account_token !== appAccountToken) {
      throw new HttpError(401, {
        error: 'unauthorized',
        message: 'App account token mismatch.'
      });
    }

    if (row.expires_at && Date.parse(row.expires_at) < Date.now()) {
      throw new HttpError(401, {
        error: 'session_expired',
        message: 'Session has expired.'
      });
    }

    const identity = db.prepare(`
      SELECT email, display_name
      FROM auth_identities
      WHERE user_id = ?
      ORDER BY created_at ASC
      LIMIT 1
    `).get(row.user_id);

    return {
      accessToken,
      session: row,
      user: {
        id: row.user_id,
        status: row.status,
        email: identity?.email ?? null,
        displayName: identity?.display_name ?? null
      }
    };
  }

  function ensureSubscription(userID, now) {
    let subscription = db.prepare(`
      SELECT *
      FROM subscriptions
      WHERE user_id = ?
    `).get(userID);

    if (!subscription) {
      const id = createID('sub');
      db.prepare(`
        INSERT INTO subscriptions (
          id, user_id, plan, status, source_transaction_id, renews_at, expires_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(id, userID, 'free', 'active', null, null, null, now, now);

      subscription = db.prepare(`
        SELECT *
        FROM subscriptions
        WHERE user_id = ?
      `).get(userID);
    }

    return subscription;
  }

  function requireAdmin(req) {
    if (!config.adminAPIKey) {
      throw new HttpError(503, {
        error: 'admin_not_configured',
        message: 'TRAI_ADMIN_API_KEY must be configured before using admin endpoints.'
      });
    }

    const bearerToken = String(req.headers.authorization ?? '').startsWith('Bearer ')
      ? String(req.headers.authorization).slice('Bearer '.length)
      : null;
    const token = bearerToken ?? String(req.headers['x-trai-admin-token'] ?? '');

    if (token !== config.adminAPIKey) {
      throw new HttpError(401, {
        error: 'unauthorized',
        message: 'Admin token is invalid.'
      });
    }
  }

  function resolveAdminLookup({ userID, appAccountToken, originalTransactionId }) {
    return {
      userID: userID?.trim() || null,
      appAccountToken: appAccountToken?.trim() || null,
      originalTransactionId: originalTransactionId?.trim() || null
    };
  }

  function resolveAdminUserID({ userID, appAccountToken, originalTransactionId }) {
    if (userID) {
      const direct = db.prepare(`SELECT id FROM users WHERE id = ? LIMIT 1`).get(userID);
      return direct?.id ?? null;
    }

    if (appAccountToken) {
      const sessionMatch = db.prepare(`
        SELECT user_id
        FROM sessions
        WHERE app_account_token = ?
        ORDER BY updated_at DESC
        LIMIT 1
      `).get(appAccountToken);
      if (sessionMatch?.user_id) {
        return sessionMatch.user_id;
      }
    }

    if (originalTransactionId) {
      return findUserIDForOriginalTransaction(originalTransactionId);
    }

    throw new HttpError(400, {
      error: 'missing_lookup',
      message: 'Provide userID, appAccountToken, or originalTransactionId.'
    });
  }

  async function getAppleSigningKey(keyID) {
    if (!keyID) {
      throw new HttpError(401, {
        error: 'invalid_apple_identity_token',
        message: 'Apple identity token header is missing a key identifier.'
      });
    }

    let keys = await loadAppleJWKS(false);
    let key = keys.find((candidate) => candidate.kid === keyID);
    if (key) {
      return key;
    }

    keys = await loadAppleJWKS(true);
    key = keys.find((candidate) => candidate.kid === keyID);
    if (!key) {
      throw new HttpError(401, {
        error: 'invalid_apple_identity_token',
        message: 'Apple signing key could not be found for this identity token.'
      });
    }

    return key;
  }

  async function loadAppleJWKS(forceRefresh) {
    const now = Date.now();
    const cacheTTLMilliseconds = Math.max(config.appleJWKSCacheTTLSeconds, 60) * 1000;
    if (!forceRefresh && appleJWKSCache.keys.length > 0 && (now - appleJWKSCache.fetchedAt) < cacheTTLMilliseconds) {
      return appleJWKSCache.keys;
    }

    const payload = config.appleJWKSPath
      ? readAppleJWKSFromDisk(config.appleJWKSPath)
      : await fetchAppleJWKSFromNetwork(config.appleJWKSURL);

    if (!payload || !Array.isArray(payload.keys) || payload.keys.length === 0) {
      throw new HttpError(503, {
        error: 'apple_jwks_unavailable',
        message: 'Apple signing keys are unavailable.'
      });
    }

    appleJWKSCache.keys = payload.keys;
    appleJWKSCache.fetchedAt = now;
    return appleJWKSCache.keys;
  }

  function readAppleJWKSFromDisk(filePath) {
    try {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch {
      throw new HttpError(503, {
        error: 'apple_jwks_unavailable',
        message: 'Failed to read the configured Apple JWKS file.'
      });
    }
  }

  async function fetchAppleJWKSFromNetwork(url) {
    let response;
    try {
      response = await fetch(url, {
        headers: {
          Accept: 'application/json'
        }
      });
    } catch {
      throw new HttpError(503, {
        error: 'apple_jwks_unavailable',
        message: 'Failed to download Apple signing keys.'
      });
    }

    if (!response.ok) {
      throw new HttpError(503, {
        error: 'apple_jwks_unavailable',
        message: `Apple signing key endpoint returned ${response.status}.`
      });
    }

    try {
      return await response.json();
    } catch {
      throw new HttpError(503, {
        error: 'apple_jwks_unavailable',
        message: 'Apple signing key response was not valid JSON.'
      });
    }
  }

  return {
    verifyAppleIdentity,
    findOrCreateUserFromApple,
    createSession,
    rotateSessionTokens,
    requireSession,
    ensureSubscription,
    requireAdmin,
    resolveAdminLookup,
    resolveAdminUserID
  };
}
