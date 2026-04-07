import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const schemaPath = path.join(backendRoot, 'schema.sql');

export function createDatabase(databasePath) {
  fs.mkdirSync(path.dirname(databasePath), { recursive: true });
  const db = new DatabaseSync(databasePath);
  db.exec(fs.readFileSync(schemaPath, 'utf8'));
  applyMigrations(db);
  return db;
}

function applyMigrations(db) {
  ensureColumn(db, 'sessions', 'installation_id', 'TEXT');
  ensureColumn(db, 'quota_periods', 'bonus_units', 'INTEGER NOT NULL DEFAULT 0');
  ensureColumn(db, 'storekit_transactions', 'environment', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'product_id', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'transaction_id', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'original_transaction_id', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'purchase_date', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'expires_date', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'revocation_date', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'signed_date', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'raw_jws', 'TEXT');
  ensureColumn(db, 'storekit_transactions', 'updated_at', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'notification_uuid', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'notification_type', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'subtype', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'environment', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'related_transaction_id', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'related_original_transaction_id', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'raw_payload', 'TEXT');
  ensureColumn(db, 'app_store_notifications', 'processed_at', 'TEXT');
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
}

function ensureColumn(db, tableName, columnName, columnDefinition) {
  const columns = db.prepare(`PRAGMA table_info(${tableName})`).all();
  const hasColumn = columns.some((column) => column.name === columnName);
  if (!hasColumn) {
    db.exec(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDefinition}`);
  }
}
