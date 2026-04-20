CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  email TEXT,
  display_name TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(provider, provider_user_id),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  installation_id TEXT,
  app_account_token TEXT NOT NULL,
  access_token_hash TEXT NOT NULL UNIQUE,
  refresh_token_hash TEXT,
  expires_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  plan TEXT NOT NULL,
  status TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'system',
  source_transaction_id TEXT,
  renews_at TEXT,
  expires_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS quota_periods (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  unit_limit INTEGER,
  bonus_units INTEGER NOT NULL DEFAULT 0,
  units_used INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(user_id, period_start, period_end),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS usage_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  feature TEXT NOT NULL,
  unit_cost INTEGER NOT NULL,
  request_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ai_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  feature TEXT NOT NULL,
  provider TEXT,
  model TEXT NOT NULL,
  action TEXT NOT NULL,
  outcome TEXT NOT NULL,
  latency_ms INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  total_tokens INTEGER,
  cached_input_tokens INTEGER,
  reasoning_tokens INTEGER,
  provider_cost_estimate REAL,
  provider_usage_json TEXT,
  request_format TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  retry_reason TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

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
);

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
);

CREATE TABLE IF NOT EXISTS storekit_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  environment TEXT,
  product_id TEXT NOT NULL,
  transaction_id TEXT NOT NULL UNIQUE,
  original_transaction_id TEXT NOT NULL,
  purchase_date TEXT,
  expires_date TEXT,
  revocation_date TEXT,
  signed_date TEXT,
  app_account_token TEXT,
  raw_jws TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS app_store_notifications (
  id TEXT PRIMARY KEY,
  notification_uuid TEXT NOT NULL UNIQUE,
  notification_type TEXT,
  subtype TEXT,
  environment TEXT,
  related_transaction_id TEXT,
  related_original_transaction_id TEXT,
  raw_payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  processed_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS usage_ledger_user_created_at_idx
  ON usage_ledger (user_id, created_at);

CREATE INDEX IF NOT EXISTS usage_ledger_created_at_idx
  ON usage_ledger (created_at);

CREATE INDEX IF NOT EXISTS ai_requests_user_created_at_idx
  ON ai_requests (user_id, created_at);

CREATE INDEX IF NOT EXISTS ai_requests_created_at_idx
  ON ai_requests (created_at);

CREATE INDEX IF NOT EXISTS subscription_overrides_user_active_idx
  ON subscription_overrides (user_id, revoked_at, expires_at, updated_at);
