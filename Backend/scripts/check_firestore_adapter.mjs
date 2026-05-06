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
}

await main();
