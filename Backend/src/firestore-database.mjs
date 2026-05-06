const TABLES = new Set([
  'users',
  'auth_identities',
  'sessions',
  'subscriptions',
  'quota_periods',
  'usage_ledger',
  'ai_requests',
  'admin_adjustments',
  'subscription_overrides',
  'storekit_transactions',
  'app_store_notifications'
]);

export async function createFirestoreDatabase(config) {
  const { Firestore } = await import('@google-cloud/firestore');
  const options = {};
  if (config.firestoreProjectID) {
    options.projectId = config.firestoreProjectID;
  }
  if (config.firestoreDatabaseID) {
    options.databaseId = config.firestoreDatabaseID;
  }

  return createFirestoreAdapter(new Firestore(options));
}

export function createFirestoreAdapter(firestore) {
  const adapter = {
    driver: 'firestore',
    prepare(sql) {
      const statement = createFirestoreStatement(firestore, sql);
      return {
        get: (...params) => statement.get(...params),
        all: (...params) => statement.all(...params),
        run: (...params) => statement.run(...params)
      };
    },
    async exec() {},
    async close() {
      await firestore.terminate();
    }
  };

  return adapter;
}

function createFirestoreStatement(firestore, sql) {
  const normalizedSQL = normalizeSQL(sql);
  return {
    async get(...params) {
      return (await readRows(firestore, normalizedSQL, params))[0];
    },
    async all(...params) {
      return await readRows(firestore, normalizedSQL, params);
    },
    async run(...params) {
      return await writeRows(firestore, normalizedSQL, params);
    }
  };
}

async function readRows(firestore, sql, params) {
  if (sql.includes('from users') && sql.includes('where id = ?')) {
    return one(await getByID(firestore, 'users', params[0]));
  }

  if (sql.includes('from auth_identities join users') && sql.includes('provider_user_id = ?')) {
    const [provider, providerUserID] = params;
    const identity = (await whereRows(firestore, 'auth_identities', [['provider', '==', provider]]))
      .find((row) => row.provider_user_id === providerUserID);
    if (!identity) return [];
    const user = await getByID(firestore, 'users', identity.user_id);
    return user ? [{ ...user, email: identity.email, display_name: identity.display_name }] : [];
  }

  if (sql.includes('from auth_identities') && sql.includes('lower(email) = ?')) {
    const [provider, email] = params;
    return (await allRows(firestore, 'auth_identities'))
      .filter((row) => row.provider === provider && String(row.email ?? '').toLowerCase() === email)
      .sort(desc('updated_at'))
      .map((row) => pick(row, ['user_id']));
  }

  if (sql.includes('from auth_identities') && sql.includes('where user_id = ?')) {
    return (await whereRows(firestore, 'auth_identities', [['user_id', '==', params[0]]]))
      .sort(asc('created_at'))
      .map((row) => projectAuthIdentity(row, sql));
  }

  if (sql.includes('from sessions join users') && sql.includes('access_token_hash = ?')) {
    return await sessionJoinRows(firestore, 'access_token_hash', params[0]);
  }

  if (sql.includes('from sessions join users') && sql.includes('refresh_token_hash = ?')) {
    return await sessionJoinRows(firestore, 'refresh_token_hash', params[0]);
  }

  if (sql.includes('from sessions') && sql.includes('where user_id = ?')) {
    return (await whereRows(firestore, 'sessions', [['user_id', '==', params[0]]]))
      .sort(desc('updated_at'))
      .slice(0, limitFromSQL(sql))
      .map((row) => projectSession(row));
  }

  if (sql.includes('from sessions') && sql.includes('app_account_token = ?')) {
    return (await whereRows(firestore, 'sessions', [['app_account_token', '==', params[0]]]))
      .sort(desc('updated_at'))
      .slice(0, limitFromSQL(sql))
      .map((row) => pick(row, ['user_id']));
  }

  if (sql.includes('from subscriptions') && sql.includes('where user_id = ?')) {
    return one(await firstWhere(firestore, 'subscriptions', [['user_id', '==', params[0]]]));
  }

  if (sql.includes('from subscriptions') && sql.includes('source_transaction_id = ?')) {
    return (await whereRows(firestore, 'subscriptions', [['source_transaction_id', '==', params[0]]]))
      .slice(0, limitFromSQL(sql))
      .map((row) => pick(row, ['user_id']));
  }

  if (sql.includes('from quota_periods') && sql.includes('period_start = ?') && sql.includes('period_end = ?')) {
    const [userID, periodStart, periodEnd] = params;
    return one((await whereRows(firestore, 'quota_periods', [['user_id', '==', userID]]))
      .find((row) => row.period_start === periodStart && row.period_end === periodEnd));
  }

  if (sql.includes('from quota_periods') && sql.includes('where id = ?')) {
    return one(await getByID(firestore, 'quota_periods', params[0]));
  }

  if (sql.includes('from quota_periods') && sql.includes('where user_id = ?')) {
    return (await whereRows(firestore, 'quota_periods', [['user_id', '==', params[0]]]))
      .sort(desc('period_start'))
      .slice(0, limitFromSQL(sql));
  }

  if (sql.includes('from subscription_overrides') && sql.includes('where user_id = ?')) {
    const [userID, now] = params;
    return (await whereRows(firestore, 'subscription_overrides', [['user_id', '==', userID]]))
      .filter((row) => row.revoked_at == null && (row.expires_at == null || row.expires_at > now))
      .sort(desc('updated_at'))
      .slice(0, limitFromSQL(sql));
  }

  if (sql.includes('from usage_ledger')) {
    return await readUsageLedger(firestore, sql, params);
  }

  if (sql.includes('from ai_requests')) {
    return await readAIRequests(firestore, sql, params);
  }

  if (sql.includes('from storekit_transactions')) {
    return await readStoreKitTransactions(firestore, sql, params);
  }

  if (sql.includes('from app_store_notifications')) {
    return await readAppStoreNotifications(firestore, sql, params);
  }

  if (sql.includes('from admin_adjustments') && sql.includes('where user_id = ?')) {
    return (await whereRows(firestore, 'admin_adjustments', [['user_id', '==', params[0]]]))
      .sort(desc('created_at'))
      .slice(0, limitFromSQL(sql))
      .map((row) => pick(row, [
        'adjustment_type',
        'unit_delta',
        'previous_units_used',
        'new_units_used',
        'reason',
        'created_by',
        'created_at'
      ]));
  }

  throw new Error(`Unsupported Firestore read SQL: ${sql}`);
}

async function writeRows(firestore, sql, params) {
  if (sql.startsWith('insert into users')) {
    return await setRow(firestore, 'users', params[0], rowFrom(params, ['id', 'created_at', 'updated_at', 'status']), { create: true });
  }
  if (sql.startsWith('insert into auth_identities')) {
    const row = rowFrom(params, ['id', 'user_id', 'provider', 'provider_user_id', 'email', 'display_name', 'created_at', 'updated_at']);
    row.id = `${row.provider}:${row.provider_user_id}`;
    return await setRow(firestore, 'auth_identities', row.id, row, { create: true });
  }
  if (sql.startsWith('insert into sessions')) {
    return await setRow(firestore, 'sessions', params[0], rowFrom(params, ['id', 'user_id', 'installation_id', 'app_account_token', 'access_token_hash', 'refresh_token_hash', 'expires_at', 'created_at', 'updated_at']), { create: true });
  }
  if (sql.startsWith('insert into subscriptions')) {
    return await setRow(firestore, 'subscriptions', params[0], rowFrom(params, ['id', 'user_id', 'plan', 'status', 'source', 'source_transaction_id', 'renews_at', 'expires_at', 'created_at', 'updated_at']), { create: true });
  }
  if (sql.startsWith('insert into quota_periods')) {
    return await setRow(firestore, 'quota_periods', params[0], rowFrom(params, ['id', 'user_id', 'period_start', 'period_end', 'unit_limit', 'bonus_units', 'units_used', 'created_at', 'updated_at']), { create: true });
  }
  if (sql.startsWith('insert into usage_ledger')) {
    return await setRow(firestore, 'usage_ledger', params[0], rowFrom(params, ['id', 'user_id', 'feature', 'unit_cost', 'request_id', 'created_at']), { create: true });
  }
  if (sql.startsWith('insert into ai_requests')) {
    return await setRow(firestore, 'ai_requests', params[0], rowFrom(params, [
      'id',
      'user_id',
      'feature',
      'provider',
      'model',
      'action',
      'outcome',
      'latency_ms',
      'input_tokens',
      'output_tokens',
      'total_tokens',
      'cached_input_tokens',
      'reasoning_tokens',
      'provider_cost_estimate',
      'provider_usage_json',
      'request_format',
      'retry_count',
      'retry_reason',
      'created_at'
    ]), { create: true });
  }
  if (sql.startsWith('insert into admin_adjustments')) {
    return await setRow(firestore, 'admin_adjustments', params[0], rowFrom(params, ['id', 'user_id', 'quota_period_id', 'adjustment_type', 'unit_delta', 'previous_units_used', 'new_units_used', 'reason', 'created_by', 'created_at']), { create: true });
  }
  if (sql.startsWith('insert into subscription_overrides')) {
    return await setRow(firestore, 'subscription_overrides', params[0], rowFrom(params, ['id', 'user_id', 'plan', 'status', 'source', 'renews_at', 'expires_at', 'reason', 'created_by', 'created_at', 'updated_at', 'revoked_at']), { create: true });
  }
  if (sql.startsWith('insert into storekit_transactions')) {
    const row = rowFrom(params, ['id', 'user_id', 'environment', 'product_id', 'transaction_id', 'original_transaction_id', 'purchase_date', 'expires_date', 'revocation_date', 'signed_date', 'app_account_token', 'raw_jws', 'created_at', 'updated_at']);
    const existing = await firstWhere(firestore, 'storekit_transactions', [['transaction_id', '==', row.transaction_id]]);
    const id = existing?.id ?? row.id;
    const next = existing
      ? { ...existing, ...omit(row, ['id', 'user_id', 'created_at']), updated_at: row.updated_at }
      : row;
    return await setRow(firestore, 'storekit_transactions', id, { ...next, id });
  }
  if (sql.startsWith('insert into app_store_notifications')) {
    const row = rowFrom(params, ['id', 'notification_uuid', 'notification_type', 'subtype', 'environment', 'related_transaction_id', 'related_original_transaction_id', 'raw_payload', 'created_at', 'processed_at']);
    const existing = await firstWhere(firestore, 'app_store_notifications', [['notification_uuid', '==', row.notification_uuid]]);
    const id = existing?.id ?? row.id;
    const next = existing
      ? { ...existing, ...omit(row, ['id', 'created_at']) }
      : row;
    return await setRow(firestore, 'app_store_notifications', id, { ...next, id });
  }

  if (sql.startsWith('update auth_identities')) {
    const [email, displayName, updatedAt, provider, providerUserID] = params;
    const row = (await whereRows(firestore, 'auth_identities', [['provider', '==', provider]]))
      .find((candidate) => candidate.provider_user_id === providerUserID);
    if (!row) return result(0);
    return await updateByID(firestore, 'auth_identities', row.id, { email, display_name: displayName, updated_at: updatedAt });
  }
  if (sql.startsWith('update sessions')) {
    const [accessTokenHash, refreshTokenHash, expiresAt, updatedAt, id] = params;
    return await updateByID(firestore, 'sessions', id, { access_token_hash: accessTokenHash, refresh_token_hash: refreshTokenHash, expires_at: expiresAt, updated_at: updatedAt });
  }
  if (sql.startsWith('update subscriptions')) {
    const [plan, status, source, sourceTransactionID, renewsAt, expiresAt, updatedAt, userID] = params;
    return await updateFirstWhere(firestore, 'subscriptions', [['user_id', '==', userID]], { plan, status, source, source_transaction_id: sourceTransactionID, renews_at: renewsAt, expires_at: expiresAt, updated_at: updatedAt });
  }
  if (sql.startsWith('update quota_periods') && sql.includes('set unit_limit')) {
    return await updateByID(firestore, 'quota_periods', params[2], { unit_limit: params[0], updated_at: params[1] });
  }
  if (sql.startsWith('update quota_periods') && sql.includes('units_used = units_used +')) {
    return await reserveQuota(firestore, params[2], params[0], params[1]);
  }
  if (sql.startsWith('update quota_periods') && sql.includes('max(units_used -')) {
    return await releaseQuota(firestore, params[2], params[0], params[1]);
  }
  if (sql.startsWith('update quota_periods') && sql.includes('set units_used = ?')) {
    return await updateByID(firestore, 'quota_periods', params[2], { units_used: params[0], updated_at: params[1] });
  }
  if (sql.startsWith('update quota_periods') && sql.includes('set bonus_units = ?')) {
    return await updateByID(firestore, 'quota_periods', params[2], { bonus_units: params[0], updated_at: params[1] });
  }
  if (sql.startsWith('update subscription_overrides')) {
    const [revokedAt, updatedAt, userID] = params;
    const rows = (await whereRows(firestore, 'subscription_overrides', [['user_id', '==', userID]])).filter((row) => row.revoked_at == null);
    const batch = firestore.batch();
    for (const row of rows) {
      batch.update(docRef(firestore, 'subscription_overrides', row.id), { revoked_at: revokedAt, updated_at: updatedAt });
    }
    await batch.commit();
    return result(rows.length);
  }

  throw new Error(`Unsupported Firestore write SQL: ${sql}`);
}

async function sessionJoinRows(firestore, hashField, hashValue) {
  const session = await firstWhere(firestore, 'sessions', [[hashField, '==', hashValue]]);
  if (!session) return [];
  const user = await getByID(firestore, 'users', session.user_id);
  if (!user) return [];
  return [{ ...session, status: user.status }];
}

async function readUsageLedger(firestore, sql, params) {
  const rows = await allRows(firestore, 'usage_ledger');
  const filtered = filterByUserAndDate(rows, sql, params);

  if (sql.includes('count(*) as request_count') && sql.includes('count(distinct user_id)')) {
    return [{
      request_count: filtered.length,
      units_used: sum(filtered, 'unit_cost'),
      active_user_count: new Set(filtered.map((row) => row.user_id)).size
    }];
  }

  if (sql.includes('count(*) as request_count') && sql.includes('group by feature')) {
    return groupRows(filtered, ['feature'], {
      request_count: (items) => items.length,
      units_used: (items) => sum(items, 'unit_cost')
    }).sort((a, b) => (b.units_used - a.units_used) || (b.request_count - a.request_count));
  }

  if (sql.includes('coalesce(subscriptions.plan')) {
    const subscriptions = await allRows(firestore, 'subscriptions');
    const byUser = new Map(subscriptions.map((row) => [row.user_id, row]));
    return groupRows(filtered, [(row) => byUser.get(row.user_id)?.plan ?? 'free'], {
      plan: (items, key) => key[0],
      request_count: (items) => items.length,
      units_used: (items) => sum(items, 'unit_cost'),
      active_user_count: (items) => new Set(items.map((row) => row.user_id)).size
    }).sort((a, b) => (b.units_used - a.units_used) || (b.request_count - a.request_count));
  }

  if (sql.includes('group by') && sql.includes('usage_ledger.user_id')) {
    const subscriptions = await allRows(firestore, 'subscriptions');
    const byUser = new Map(subscriptions.map((row) => [row.user_id, row]));
    return groupRows(filtered, ['user_id'], {
      user_id: (items) => items[0].user_id,
      plan: (items) => byUser.get(items[0].user_id)?.plan ?? 'free',
      subscription_status: (items) => byUser.get(items[0].user_id)?.status ?? 'unknown',
      request_count: (items) => items.length,
      units_used: (items) => sum(items, 'unit_cost'),
      last_used_at: (items) => max(items, 'created_at')
    }).sort((a, b) => (b.units_used - a.units_used) || (b.request_count - a.request_count) || compareDesc(a.last_used_at, b.last_used_at)).slice(0, limitFromSQL(sql));
  }

  if (sql.includes('count(*) as request_count') || sql.includes('sum(unit_cost)')) {
    return [{ request_count: filtered.length, units_used: sum(filtered, 'unit_cost'), units: sum(filtered, 'unit_cost') }];
  }

  if (sql.includes('count(*) as count') && sql.includes('group by feature')) {
    return groupRows(filtered, ['feature'], {
      count: (items) => items.length
    });
  }

  return filtered.sort(desc('created_at')).slice(0, limitFromSQL(sql)).map((row) => pick(row, ['feature', 'unit_cost', 'created_at']));
}

async function readAIRequests(firestore, sql, params) {
  const rows = filterByUserAndDate(await allRows(firestore, 'ai_requests'), sql, params);
  if (sql.includes('count(*) as count') && sql.includes('group by outcome')) {
    return groupRows(rows, ['outcome'], { count: (items) => items.length });
  }
  if (sql.includes('count(*) as count')) {
    return [{ count: rows.length }];
  }
  return rows.sort(desc('created_at')).slice(0, limitFromSQL(sql)).map((row) => projectAIRequest(row, sql));
}

async function readStoreKitTransactions(firestore, sql, params) {
  let rows = await allRows(firestore, 'storekit_transactions');
  if (sql.includes('where user_id = ?')) {
    rows = rows.filter((row) => row.user_id === params[0]);
  } else if (sql.includes('where original_transaction_id = ?')) {
    rows = rows.filter((row) => row.original_transaction_id === String(params[0]));
  } else if (sql.includes('where transaction_id = ?')) {
    rows = rows.filter((row) => row.transaction_id === String(params[0]));
  }
  if (sql.includes('revocation_date is null')) {
    rows = rows.filter((row) => row.revocation_date == null);
    rows.sort((a, b) => compareDesc(a.expires_date ?? '9999-12-31T23:59:59.999Z', b.expires_date ?? '9999-12-31T23:59:59.999Z') || compareDesc(a.signed_date ?? a.updated_at, b.signed_date ?? b.updated_at));
  } else {
    rows.sort(desc(sql.includes('coalesce(signed_date') ? (row) => row.signed_date ?? row.updated_at : 'updated_at'));
  }
  return rows.slice(0, limitFromSQL(sql)).map((row) => projectStoreKitTransaction(row, sql));
}

async function readAppStoreNotifications(firestore, sql, params) {
  let rows = await allRows(firestore, 'app_store_notifications');
  if (sql.includes('related_original_transaction_id in')) {
    const transactions = (await whereRows(firestore, 'storekit_transactions', [['user_id', '==', params[0]]]));
    const originals = new Set(transactions.map((row) => row.original_transaction_id));
    rows = rows.filter((row) => originals.has(row.related_original_transaction_id));
  }
  rows.sort(desc('processed_at'));
  return rows.slice(0, limitFromSQL(sql)).map((row) => projectAppStoreNotification(row, sql));
}

function filterByUserAndDate(rows, sql, params) {
  let filtered = rows;
  if (sql.includes('where user_id = ? and created_at >= ?')) {
    filtered = filtered.filter((row) => row.user_id === params[0] && row.created_at >= params[1]);
    if (sql.includes('created_at < ?')) {
      filtered = filtered.filter((row) => row.created_at < params[2]);
    }
  } else if (sql.includes('where created_at >= ?')) {
    filtered = filtered.filter((row) => row.created_at >= params[0]);
  } else if (sql.includes('where user_id = ?')) {
    filtered = filtered.filter((row) => row.user_id === params[0]);
  }
  return filtered;
}

async function reserveQuota(firestore, id, unitCost, updatedAt) {
  const ref = docRef(firestore, 'quota_periods', id);
  const changed = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return false;
    const row = snapshot.data();
    const limit = row.unit_limit == null ? null : row.unit_limit + (row.bonus_units ?? 0);
    if (limit != null && (row.units_used + unitCost) > limit) return false;
    transaction.update(ref, { units_used: row.units_used + unitCost, updated_at: updatedAt });
    return true;
  });
  return result(changed ? 1 : 0);
}

async function releaseQuota(firestore, id, unitCost, updatedAt) {
  const ref = docRef(firestore, 'quota_periods', id);
  const changed = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return false;
    const row = snapshot.data();
    transaction.update(ref, { units_used: Math.max((row.units_used ?? 0) - unitCost, 0), updated_at: updatedAt });
    return true;
  });
  return result(changed ? 1 : 0);
}

async function getByID(firestore, table, id) {
  const snapshot = await docRef(firestore, table, id).get();
  return snapshot.exists ? snapshot.data() : undefined;
}

async function firstWhere(firestore, table, clauses) {
  return (await whereRows(firestore, table, clauses))[0];
}

async function whereRows(firestore, table, clauses) {
  let query = firestore.collection(table);
  for (const [field, op, value] of clauses) {
    query = query.where(field, op, value);
  }
  const snapshot = await query.get();
  return snapshot.docs.map((doc) => doc.data());
}

async function allRows(firestore, table) {
  const snapshot = await firestore.collection(table).get();
  return snapshot.docs.map((doc) => doc.data());
}

async function setRow(firestore, table, id, row, options = {}) {
  const ref = docRef(firestore, table, id);
  if (options.create) {
    const snapshot = await ref.get();
    if (snapshot.exists) return result(0);
  }
  await ref.set(cleanRow(row));
  return result(1);
}

async function updateByID(firestore, table, id, changes) {
  const ref = docRef(firestore, table, id);
  const snapshot = await ref.get();
  if (!snapshot.exists) return result(0);
  await ref.update(cleanRow(changes));
  return result(1);
}

async function updateFirstWhere(firestore, table, clauses, changes) {
  const row = await firstWhere(firestore, table, clauses);
  if (!row) return result(0);
  return await updateByID(firestore, table, row.id, changes);
}

function docRef(firestore, table, id) {
  if (!TABLES.has(table)) {
    throw new Error(`Unknown Firestore table: ${table}`);
  }
  return firestore.collection(table).doc(String(id));
}

function rowFrom(params, fields) {
  return Object.fromEntries(fields.map((field, index) => [field, params[index] ?? null]));
}

function cleanRow(row) {
  return Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined));
}

function projectAuthIdentity(row, sql) {
  if (sql.includes('select email, display_name')) {
    return pick(row, ['email', 'display_name']);
  }
  return pick(row, ['provider', 'provider_user_id', 'email', 'display_name', 'created_at', 'updated_at']);
}

function projectSession(row) {
  return pick(row, ['id', 'installation_id', 'app_account_token', 'expires_at', 'created_at', 'updated_at']);
}

function projectAIRequest(row, sql) {
  const fields = [
    'user_id',
    'feature',
    'provider',
    'model',
    'action',
    'outcome',
    'latency_ms',
    'input_tokens',
    'output_tokens',
    'total_tokens',
    'cached_input_tokens',
    'reasoning_tokens',
    'provider_cost_estimate',
    'provider_usage_json',
    'request_format',
    'retry_count',
    'retry_reason',
    'created_at'
  ];
  return pick(row, fields.filter((field) => sql.includes(field) || field === 'feature' || field === 'provider' || field === 'model' || field === 'outcome'));
}

function projectStoreKitTransaction(row, sql) {
  if (sql.includes('select user_id')) {
    return pick(row, ['user_id']);
  }
  if (sql.includes('select environment')) {
    return pick(row, ['environment', 'product_id', 'transaction_id', 'original_transaction_id', 'purchase_date', 'expires_date', 'revocation_date', 'signed_date', 'updated_at']);
  }
  return row;
}

function projectAppStoreNotification(row, sql) {
  if (sql.includes('select notification_uuid')) {
    return pick(row, ['notification_uuid', 'notification_type', 'subtype', 'environment', 'related_transaction_id', 'related_original_transaction_id', 'processed_at']);
  }
  return row;
}

function groupRows(rows, keys, aggregations) {
  const buckets = new Map();
  for (const row of rows) {
    const keyValues = keys.map((key) => typeof key === 'function' ? key(row) : row[key]);
    const key = JSON.stringify(keyValues);
    if (!buckets.has(key)) buckets.set(key, { keyValues, rows: [] });
    buckets.get(key).rows.push(row);
  }
  return Array.from(buckets.values()).map(({ keyValues, rows: bucketRows }) => {
    const entry = {};
    for (const [field, aggregate] of Object.entries(aggregations)) {
      entry[field] = aggregate(bucketRows, keyValues);
    }
    for (let index = 0; index < keys.length; index += 1) {
      if (typeof keys[index] === 'string' && !(keys[index] in entry)) {
        entry[keys[index]] = keyValues[index];
      }
    }
    return entry;
  });
}

function pick(row, fields) {
  return Object.fromEntries(fields.filter((field) => field in row).map((field) => [field, row[field]]));
}

function omit(row, fields) {
  const excluded = new Set(fields);
  return Object.fromEntries(Object.entries(row).filter(([field]) => !excluded.has(field)));
}

function sum(rows, field) {
  return rows.reduce((total, row) => total + (Number(row[field]) || 0), 0);
}

function max(rows, field) {
  return rows.reduce((latest, row) => !latest || row[field] > latest ? row[field] : latest, null);
}

function asc(field) {
  return (left, right) => String(valueForSort(left, field) ?? '').localeCompare(String(valueForSort(right, field) ?? ''));
}

function desc(field) {
  return (left, right) => compareDesc(valueForSort(left, field), valueForSort(right, field));
}

function compareDesc(left, right) {
  return String(right ?? '').localeCompare(String(left ?? ''));
}

function valueForSort(row, field) {
  return typeof field === 'function' ? field(row) : row[field];
}

function limitFromSQL(sql) {
  const match = sql.match(/limit (\d+)/);
  return match ? Number.parseInt(match[1], 10) : Number.POSITIVE_INFINITY;
}

function one(row) {
  return row ? [row] : [];
}

function result(changes) {
  return { changes, lastInsertRowid: null };
}

function normalizeSQL(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toLowerCase();
}
