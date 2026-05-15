import assert from 'node:assert/strict';
import { createFirestoreAdapter } from '../src/firestore-database.mjs';

async function main() {
const firestore = new FakeFirestore();
const db = createFirestoreAdapter(firestore);

await db.prepare(`
  INSERT INTO users (id, created_at, updated_at, status)
  VALUES (?, ?, ?, ?)
`).run('usr_1', '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z', 'active');

await db.prepare(`
  INSERT INTO auth_identities (
    id, user_id, provider, provider_user_id, email, display_name, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
`).run('aid_1', 'usr_1', 'apple', 'apple-user-1', 'one@example.com', 'One', '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z');

const identity = await db.prepare(`
  SELECT users.id, users.status, auth_identities.email, auth_identities.display_name
  FROM auth_identities
  JOIN users ON users.id = auth_identities.user_id
  WHERE auth_identities.provider = ? AND auth_identities.provider_user_id = ?
`).get('apple', 'apple-user-1');
assert.equal(identity.id, 'usr_1');
assert.equal(identity.email, 'one@example.com');

await db.prepare(`
  INSERT INTO sessions (
    id, user_id, installation_id, app_account_token, access_token_hash, refresh_token_hash, expires_at, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
`).run('ses_1', 'usr_1', 'install_1', 'acct_1', 'access_hash_1', 'refresh_hash_1', '2026-06-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z');

const session = await db.prepare(`
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
`).get('access_hash_1');
assert.equal(session.user_id, 'usr_1');
assert.equal(session.status, 'active');

await db.prepare(`
  INSERT INTO subscriptions (
    id, user_id, plan, status, source, source_transaction_id, renews_at, expires_at, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`).run('sub_1', 'usr_1', 'pro', 'active', 'appStore', 'orig_1', null, null, '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z');

await db.prepare(`
  INSERT INTO quota_periods (
    id, user_id, period_start, period_end, unit_limit, bonus_units, units_used, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
`).run('qtp_1', 'usr_1', '2026-05-01T00:00:00.000Z', '2026-06-01T00:00:00.000Z', 10, 0, 0, '2026-05-01T00:00:00.000Z', '2026-05-01T00:00:00.000Z');

let result = await db.prepare(`
  UPDATE quota_periods
  SET units_used = units_used + ?, updated_at = ?
  WHERE id = ?
    AND (
      unit_limit IS NULL
      OR (units_used + ?) <= (unit_limit + COALESCE(bonus_units, 0))
    )
`).run(7, '2026-05-01T01:00:00.000Z', 'qtp_1', 7);
assert.equal(result.changes, 1);

result = await db.prepare(`
  UPDATE quota_periods
  SET units_used = units_used + ?, updated_at = ?
  WHERE id = ?
    AND (
      unit_limit IS NULL
      OR (units_used + ?) <= (unit_limit + COALESCE(bonus_units, 0))
    )
`).run(4, '2026-05-01T01:01:00.000Z', 'qtp_1', 4);
assert.equal(result.changes, 0);

await db.prepare(`
  UPDATE quota_periods
  SET units_used = MAX(units_used - ?, 0), updated_at = ?
  WHERE id = ?
`).run(2, '2026-05-01T01:02:00.000Z', 'qtp_1');

const quota = await db.prepare(`
  SELECT *
  FROM quota_periods
  WHERE id = ?
`).get('qtp_1');
assert.equal(quota.units_used, 5);

await db.prepare(`
  INSERT INTO usage_ledger (id, user_id, feature, unit_cost, request_id, created_at)
  VALUES (?, ?, ?, ?, ?, ?)
`).run('ulg_1', 'usr_1', 'coachChat', 3, 'req_1', '2026-05-02T00:00:00.000Z');

const topUsers = await db.prepare(`
  SELECT
    usage_ledger.user_id,
    COALESCE(subscriptions.plan, 'free') AS plan,
    COALESCE(subscriptions.source, 'system') AS subscription_source,
    COALESCE(subscriptions.status, 'unknown') AS subscription_status,
    COUNT(*) AS request_count,
    COALESCE(SUM(usage_ledger.unit_cost), 0) AS units_used,
    MAX(usage_ledger.created_at) AS last_used_at
  FROM usage_ledger
  LEFT JOIN subscriptions ON subscriptions.user_id = usage_ledger.user_id
  WHERE usage_ledger.created_at >= ? AND usage_ledger.created_at < ?
  GROUP BY
    usage_ledger.user_id,
    COALESCE(subscriptions.plan, 'free'),
    COALESCE(subscriptions.source, 'system'),
    COALESCE(subscriptions.status, 'unknown')
  ORDER BY units_used DESC, request_count DESC, last_used_at DESC
  LIMIT 5000
`).all('2026-05-01T00:00:00.000Z', '2026-06-01T00:00:00.000Z');
assert.deepEqual(topUsers, [{
  user_id: 'usr_1',
  plan: 'pro',
  subscription_source: 'appStore',
  subscription_status: 'active',
  request_count: 1,
  units_used: 3,
  last_used_at: '2026-05-02T00:00:00.000Z'
}]);

const adminUsers = await db.prepare(`
  /* admin_user_list */
  SELECT
    users.id AS user_id,
    users.created_at,
    users.updated_at,
    users.status AS user_status,
    auth_identities.provider AS identity_provider,
    auth_identities.email,
    auth_identities.display_name,
    auth_identities.updated_at AS identity_updated_at,
    subscriptions.plan AS subscription_plan,
    subscriptions.status AS subscription_status,
    subscriptions.source AS subscription_source,
    subscriptions.renews_at,
    subscriptions.expires_at,
    session_summary.last_session_at,
    usage_summary.request_count_30d,
    usage_summary.units_used_30d,
    usage_summary.last_used_at
  FROM users
  LEFT JOIN auth_identities ON auth_identities.id = (
    SELECT id
    FROM auth_identities
    WHERE user_id = users.id
    ORDER BY created_at ASC
    LIMIT 1
  )
  LEFT JOIN subscriptions ON subscriptions.user_id = users.id
  LEFT JOIN (
    SELECT user_id, MAX(updated_at) AS last_session_at
    FROM sessions
    GROUP BY user_id
  ) AS session_summary ON session_summary.user_id = users.id
  LEFT JOIN (
    SELECT
      user_id,
      COUNT(*) AS request_count_30d,
      COALESCE(SUM(unit_cost), 0) AS units_used_30d,
      MAX(created_at) AS last_used_at
    FROM usage_ledger
    WHERE created_at >= ?
    GROUP BY user_id
  ) AS usage_summary ON usage_summary.user_id = users.id
  ORDER BY COALESCE(session_summary.last_session_at, users.updated_at, users.created_at) DESC, users.created_at DESC
  LIMIT 5000
`).all('2026-05-01T00:00:00.000Z');
assert.equal(adminUsers[0].user_id, 'usr_1');
assert.equal(adminUsers[0].email, 'one@example.com');
assert.equal(adminUsers[0].subscription_plan, 'pro');
assert.equal(adminUsers[0].last_session_at, '2026-05-01T00:00:00.000Z');
assert.equal(adminUsers[0].request_count_30d, 1);
assert.equal(adminUsers[0].units_used_30d, 3);

await db.prepare(`
  INSERT INTO pending_subscription_grants (
    id, normalized_email, plan, status, source, renews_at, expires_at, reason,
    created_by, created_at, updated_at, applied_user_id, applied_at, revoked_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`).run('psg_1', 'future@example.com', 'pro', 'active', 'adminGrant', null, null, 'test grant', 'test', '2026-05-02T00:00:00.000Z', '2026-05-02T00:00:00.000Z', null, null, null);

let pendingGrant = await db.prepare(`
  SELECT *
  FROM pending_subscription_grants
  WHERE normalized_email = ?
    AND revoked_at IS NULL
    AND applied_at IS NULL
  ORDER BY updated_at DESC
  LIMIT 1
`).get('future@example.com');
assert.equal(pendingGrant.plan, 'pro');

await db.prepare(`
  UPDATE pending_subscription_grants
  SET applied_user_id = ?, applied_at = ?, updated_at = ?
  WHERE id = ?
`).run('usr_1', '2026-05-03T00:00:00.000Z', '2026-05-03T00:00:00.000Z', 'psg_1');

pendingGrant = await db.prepare(`
  SELECT *
  FROM pending_subscription_grants
  WHERE normalized_email = ?
    AND revoked_at IS NULL
    AND applied_at IS NULL
  ORDER BY updated_at DESC
  LIMIT 1
`).get('future@example.com');
assert.equal(pendingGrant, undefined);

await db.prepare(`
  SELECT feature, COUNT(*) AS count
  FROM usage_ledger
  WHERE user_id = ? AND created_at >= ? AND created_at < ?
  GROUP BY feature
`).all('usr_1', '2026-05-01T00:00:00.000Z', '2026-06-01T00:00:00.000Z').then((rows) => {
  assert.deepEqual(rows, [{ feature: 'coachChat', count: 1 }]);
});

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
`).run('stx_1', 'usr_1', 'Production', 'trai.pro.monthly', 'tx_1', 'orig_1', null, null, null, '2026-05-02T00:00:00.000Z', null, 'jws_1', '2026-05-02T00:00:00.000Z', '2026-05-02T00:00:00.000Z');

const owner = await db.prepare(`
  SELECT user_id
  FROM storekit_transactions
  WHERE original_transaction_id = ?
  ORDER BY updated_at DESC
  LIMIT 1
`).get('orig_1');
assert.equal(owner.user_id, 'usr_1');

await db.prepare(`
  UPDATE auth_identities
  SET email = NULL, display_name = NULL, updated_at = ?
  WHERE user_id = ?
`).run('2026-05-04T00:00:00.000Z', 'usr_1');

const scrubbedIdentity = await db.prepare(`
  SELECT users.id, users.status, auth_identities.email, auth_identities.display_name
  FROM auth_identities
  JOIN users ON users.id = auth_identities.user_id
  WHERE auth_identities.provider = ? AND auth_identities.provider_user_id = ?
`).get('apple', 'apple-user-1');
assert.equal(scrubbedIdentity.email, null);
assert.equal(scrubbedIdentity.display_name, null);

await db.prepare(`
  DELETE FROM sessions
  WHERE user_id = ?
`).run('usr_1');

const deletedSession = await db.prepare(`
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
`).get('access_hash_1');
assert.equal(deletedSession, undefined);

await db.prepare(`
  UPDATE users
  SET status = ?, updated_at = ?
  WHERE id = ?
`).run('deleted', '2026-05-04T00:00:00.000Z', 'usr_1');

const deletedIdentity = await db.prepare(`
  SELECT users.id, users.status, auth_identities.email, auth_identities.display_name
  FROM auth_identities
  JOIN users ON users.id = auth_identities.user_id
  WHERE auth_identities.provider = ? AND auth_identities.provider_user_id = ?
`).get('apple', 'apple-user-1');
assert.equal(deletedIdentity.status, 'deleted');

await db.prepare(`
  INSERT INTO users (id, created_at, updated_at, status)
  VALUES (?, ?, ?, ?)
`).run('usr_2', '2026-05-04T00:00:00.000Z', '2026-05-04T00:00:00.000Z', 'active');

await db.prepare(`
  UPDATE auth_identities
  SET user_id = ?, email = ?, display_name = ?, updated_at = ?
  WHERE provider = ? AND provider_user_id = ?
`).run('usr_2', 'two@example.com', 'Two', '2026-05-04T00:01:00.000Z', 'apple', 'apple-user-1');

const reattachedIdentity = await db.prepare(`
  SELECT users.id, users.status, auth_identities.email, auth_identities.display_name
  FROM auth_identities
  JOIN users ON users.id = auth_identities.user_id
  WHERE auth_identities.provider = ? AND auth_identities.provider_user_id = ?
`).get('apple', 'apple-user-1');
assert.equal(reattachedIdentity.id, 'usr_2');
assert.equal(reattachedIdentity.email, 'two@example.com');

console.log('Firestore adapter smoke check passed.');
}

class FakeFirestore {
  constructor() {
    this.tables = new Map();
  }

  collection(name) {
    return new FakeQuery(this, name);
  }

  batch() {
    const operations = [];
    return {
      set: (ref, value) => operations.push(() => ref.set(value)),
      update: (ref, value) => operations.push(() => ref.update(value)),
      delete: (ref) => operations.push(() => ref.delete()),
      commit: async () => {
        for (const operation of operations) await operation();
      }
    };
  }

  async runTransaction(callback) {
    return await callback({
      get: (ref) => ref.get(),
      update: (ref, value) => ref.update(value)
    });
  }

  async terminate() {}

  table(name) {
    if (!this.tables.has(name)) this.tables.set(name, new Map());
    return this.tables.get(name);
  }
}

class FakeQuery {
  constructor(firestore, tableName, filters = []) {
    this.firestore = firestore;
    this.tableName = tableName;
    this.filters = filters;
  }

  doc(id) {
    return new FakeDocRef(this.firestore, this.tableName, id);
  }

  where(field, op, value) {
    return new FakeQuery(this.firestore, this.tableName, [...this.filters, [field, op, value]]);
  }

  async get() {
    const rows = Array.from(this.firestore.table(this.tableName).values())
      .filter((row) => this.filters.every(([field, op, value]) => op === '==' && row[field] === value));
    return {
      docs: rows.map((row) => ({ data: () => ({ ...row }) }))
    };
  }
}

class FakeDocRef {
  constructor(firestore, tableName, id) {
    this.firestore = firestore;
    this.tableName = tableName;
    this.id = String(id);
  }

  async get() {
    const row = this.firestore.table(this.tableName).get(this.id);
    return {
      exists: Boolean(row),
      data: () => row ? { ...row } : undefined
    };
  }

  async set(value) {
    this.firestore.table(this.tableName).set(this.id, { ...value });
  }

  async update(value) {
    const row = this.firestore.table(this.tableName).get(this.id);
    if (!row) throw new Error(`Missing fake document ${this.tableName}/${this.id}`);
    this.firestore.table(this.tableName).set(this.id, { ...row, ...value });
  }

  async delete() {
    this.firestore.table(this.tableName).delete(this.id);
  }
}

await main();
