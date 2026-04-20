import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import pg from 'pg';
import { fileURLToPath } from 'node:url';

const { Pool, types } = pg;

types.setTypeParser(20, (value) => Number.parseInt(value, 10));

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const sqliteSchemaPath = path.join(backendRoot, 'schema.sql');
const postgresSchemaPath = path.join(backendRoot, 'schema.postgres.sql');

export async function createDatabase(config) {
  if (config.databaseDriver === 'postgres') {
    return await createPostgresDatabase(config);
  }
  return createSQLiteDatabase(config.databasePath);
}

function createSQLiteDatabase(databasePath) {
  fs.mkdirSync(path.dirname(databasePath), { recursive: true });
  const rawDatabase = new DatabaseSync(databasePath);
  rawDatabase.exec(fs.readFileSync(sqliteSchemaPath, 'utf8'));
  applySQLiteMigrations(rawDatabase);
  return createSQLiteAdapter(rawDatabase);
}

async function createPostgresDatabase(config) {
  const pool = new Pool({
    connectionString: config.databaseURL,
    ssl: config.databaseSSLMode === 'require'
      ? { rejectUnauthorized: false }
      : undefined
  });

  await pool.query(fs.readFileSync(postgresSchemaPath, 'utf8'));
  await applyPostgresMigrations(pool);
  return createPostgresAdapter(pool);
}

function createSQLiteAdapter(rawDatabase) {
  return {
    driver: 'sqlite',
    prepare(sql) {
      const statement = rawDatabase.prepare(sql);
      return {
        async get(...params) {
          return statement.get(...params);
        },
        async all(...params) {
          return statement.all(...params);
        },
        async run(...params) {
          return normalizeRunResult(statement.run(...params));
        }
      };
    },
    async exec(sql) {
      rawDatabase.exec(sql);
    },
    async close() {
      rawDatabase.close();
    }
  };
}

function createPostgresAdapter(pool) {
  return {
    driver: 'postgres',
    prepare(sql) {
      const normalizedSql = convertPlaceholdersToPostgres(sql);
      return {
        async get(...params) {
          const result = await pool.query(normalizedSql, params);
          return result.rows[0] ?? undefined;
        },
        async all(...params) {
          const result = await pool.query(normalizedSql, params);
          return result.rows;
        },
        async run(...params) {
          const result = await pool.query(normalizedSql, params);
          return normalizeRunResult({
            changes: result.rowCount ?? 0
          });
        }
      };
    },
    async exec(sql) {
      await pool.query(sql);
    },
    async close() {
      await pool.end();
    }
  };
}

function normalizeRunResult(result) {
  return {
    changes: Number(result?.changes ?? 0),
    lastInsertRowid: result?.lastInsertRowid ?? null
  };
}

function convertPlaceholdersToPostgres(sql) {
  let placeholderIndex = 0;
  return sql.replace(/\?/g, () => {
    placeholderIndex += 1;
    return `$${placeholderIndex}`;
  });
}

function applySQLiteMigrations(db) {
  ensureSQLiteColumn(db, 'sessions', 'installation_id', 'TEXT');
  ensureSQLiteColumn(db, 'subscriptions', 'source', "TEXT NOT NULL DEFAULT 'system'");
  ensureSQLiteColumn(db, 'quota_periods', 'bonus_units', 'INTEGER NOT NULL DEFAULT 0');
  ensureSQLiteColumn(db, 'ai_requests', 'provider', 'TEXT');
  ensureSQLiteColumn(db, 'ai_requests', 'input_tokens', 'INTEGER');
  ensureSQLiteColumn(db, 'ai_requests', 'output_tokens', 'INTEGER');
  ensureSQLiteColumn(db, 'ai_requests', 'total_tokens', 'INTEGER');
  ensureSQLiteColumn(db, 'ai_requests', 'cached_input_tokens', 'INTEGER');
  ensureSQLiteColumn(db, 'ai_requests', 'reasoning_tokens', 'INTEGER');
  ensureSQLiteColumn(db, 'ai_requests', 'provider_usage_json', 'TEXT');
  ensureSQLiteColumn(db, 'ai_requests', 'request_format', 'TEXT');
  ensureSQLiteColumn(db, 'ai_requests', 'retry_count', 'INTEGER NOT NULL DEFAULT 0');
  ensureSQLiteColumn(db, 'ai_requests', 'retry_reason', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'environment', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'product_id', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'transaction_id', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'original_transaction_id', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'purchase_date', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'expires_date', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'revocation_date', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'signed_date', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'app_account_token', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'raw_jws', 'TEXT');
  ensureSQLiteColumn(db, 'storekit_transactions', 'updated_at', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'notification_uuid', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'notification_type', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'subtype', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'environment', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'related_transaction_id', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'related_original_transaction_id', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'raw_payload', 'TEXT');
  ensureSQLiteColumn(db, 'app_store_notifications', 'processed_at', 'TEXT');
  db.exec(`
    CREATE TABLE IF NOT EXISTS admin_adjustments (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      quota_period_id TEXT,
      adjustment_type TEXT NOT NULL,
      unit_delta INTEGER NOT NULL DEFAULT 0,
      previous_units_used INTEGER,
      new_units_used INTEGER,
      reason TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY(quota_period_id) REFERENCES quota_periods(id) ON DELETE SET NULL
    )
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS subscription_overrides (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      plan TEXT NOT NULL,
      status TEXT NOT NULL,
      source TEXT NOT NULL,
      renews_at TEXT,
      expires_at TEXT,
      reason TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      revoked_at TEXT,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `);
  db.exec('CREATE INDEX IF NOT EXISTS usage_ledger_user_created_at_idx ON usage_ledger (user_id, created_at)');
  db.exec('CREATE INDEX IF NOT EXISTS usage_ledger_created_at_idx ON usage_ledger (created_at)');
  db.exec('CREATE INDEX IF NOT EXISTS ai_requests_user_created_at_idx ON ai_requests (user_id, created_at)');
  db.exec('CREATE INDEX IF NOT EXISTS ai_requests_created_at_idx ON ai_requests (created_at)');
  db.exec('CREATE INDEX IF NOT EXISTS ai_requests_provider_model_created_at_idx ON ai_requests (provider, model, created_at)');
  db.exec('CREATE INDEX IF NOT EXISTS subscription_overrides_user_active_idx ON subscription_overrides (user_id, revoked_at, expires_at, updated_at)');
  backfillSubscriptionSourcesSQLite(db);
  backfillSubscriptionOverridesSQLite(db);
}

function ensureSQLiteColumn(db, tableName, columnName, columnDefinition) {
  const columns = db.prepare(`PRAGMA table_info(${tableName})`).all();
  const hasColumn = columns.some((column) => column.name === columnName);
  if (!hasColumn) {
    db.exec(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDefinition}`);
  }
}

async function applyPostgresMigrations(db) {
  await db.query('ALTER TABLE sessions ADD COLUMN IF NOT EXISTS installation_id TEXT');
  await db.query("ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'system'");
  await db.query('ALTER TABLE quota_periods ADD COLUMN IF NOT EXISTS bonus_units INTEGER NOT NULL DEFAULT 0');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS provider TEXT');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS input_tokens INTEGER');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS output_tokens INTEGER');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS total_tokens INTEGER');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS cached_input_tokens INTEGER');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS reasoning_tokens INTEGER');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS provider_usage_json TEXT');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS request_format TEXT');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0');
  await db.query('ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS retry_reason TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS environment TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS product_id TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS transaction_id TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS original_transaction_id TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS purchase_date TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS expires_date TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS revocation_date TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS signed_date TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS app_account_token TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS raw_jws TEXT');
  await db.query('ALTER TABLE storekit_transactions ADD COLUMN IF NOT EXISTS updated_at TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS notification_uuid TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS notification_type TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS subtype TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS environment TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS related_transaction_id TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS related_original_transaction_id TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS raw_payload TEXT');
  await db.query('ALTER TABLE app_store_notifications ADD COLUMN IF NOT EXISTS processed_at TEXT');
  await db.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS storekit_transactions_transaction_id_idx
      ON storekit_transactions (transaction_id)
  `);
  await db.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS app_store_notifications_notification_uuid_idx
      ON app_store_notifications (notification_uuid)
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS usage_ledger_user_created_at_idx
      ON usage_ledger (user_id, created_at)
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS usage_ledger_created_at_idx
      ON usage_ledger (created_at)
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS ai_requests_user_created_at_idx
      ON ai_requests (user_id, created_at)
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS ai_requests_created_at_idx
      ON ai_requests (created_at)
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS ai_requests_provider_model_created_at_idx
      ON ai_requests (provider, model, created_at)
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS subscription_overrides (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      plan TEXT NOT NULL,
      status TEXT NOT NULL,
      source TEXT NOT NULL,
      renews_at TEXT,
      expires_at TEXT,
      reason TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      revoked_at TEXT,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS subscription_overrides_user_active_idx
      ON subscription_overrides (user_id, revoked_at, expires_at, updated_at)
  `);
  await backfillSubscriptionSourcesPostgres(db);
  await backfillSubscriptionOverridesPostgres(db);
}

function backfillSubscriptionSourcesSQLite(db) {
  db.exec(`
    UPDATE subscriptions
    SET source = CASE
      WHEN source_transaction_id IS NOT NULL THEN 'appStore'
      WHEN plan = 'developer' THEN 'developer'
      WHEN plan != 'free' THEN 'adminGrant'
      ELSE 'system'
    END
    WHERE source IS NULL
      OR TRIM(source) = ''
      OR (
        source = 'system'
        AND (
          source_transaction_id IS NOT NULL
          OR plan != 'free'
        )
      )
  `);
}

async function backfillSubscriptionSourcesPostgres(db) {
  await db.query(`
    UPDATE subscriptions
    SET source = CASE
      WHEN source_transaction_id IS NOT NULL THEN 'appStore'
      WHEN plan = 'developer' THEN 'developer'
      WHEN plan <> 'free' THEN 'adminGrant'
      ELSE 'system'
    END
    WHERE source IS NULL
      OR BTRIM(source) = ''
      OR (
        source = 'system'
        AND (
          source_transaction_id IS NOT NULL
          OR plan <> 'free'
        )
      )
  `);
}

function backfillSubscriptionOverridesSQLite(db) {
  db.exec(`
    INSERT INTO subscription_overrides (
      id, user_id, plan, status, source, renews_at, expires_at, reason, created_by, created_at, updated_at, revoked_at
    )
    SELECT
      'sov_legacy_' || lower(hex(randomblob(12))),
      s.user_id,
      s.plan,
      s.status,
      s.source,
      s.renews_at,
      s.expires_at,
      'migrated legacy subscription override',
      'migration',
      s.updated_at,
      s.updated_at,
      NULL
    FROM subscriptions s
    WHERE s.plan != 'free'
      AND s.source IN ('adminGrant', 'promo', 'developer')
      AND NOT EXISTS (
        SELECT 1
        FROM subscription_overrides o
        WHERE o.user_id = s.user_id
          AND o.revoked_at IS NULL
      )
  `);
}

async function backfillSubscriptionOverridesPostgres(db) {
  await db.query(`
    INSERT INTO subscription_overrides (
      id, user_id, plan, status, source, renews_at, expires_at, reason, created_by, created_at, updated_at, revoked_at
    )
    SELECT
      'sov_legacy_' || md5(random()::text || clock_timestamp()::text || s.user_id),
      s.user_id,
      s.plan,
      s.status,
      s.source,
      s.renews_at,
      s.expires_at,
      'migrated legacy subscription override',
      'migration',
      s.updated_at,
      s.updated_at,
      NULL
    FROM subscriptions s
    WHERE s.plan <> 'free'
      AND s.source IN ('adminGrant', 'promo', 'developer')
      AND NOT EXISTS (
        SELECT 1
        FROM subscription_overrides o
        WHERE o.user_id = s.user_id
          AND o.revoked_at IS NULL
      )
  `);
}
