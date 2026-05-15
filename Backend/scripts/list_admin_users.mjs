#!/usr/bin/env node

const args = process.argv.slice(2);
const options = parseArgs(args);

if (options.help) {
  printUsage();
  process.exit(0);
}

const baseURL = process.env.TRAI_ADMIN_BASE_URL?.trim();
const adminToken = process.env.TRAI_ADMIN_API_KEY?.trim();

if (!baseURL || !adminToken) {
  console.error('Set TRAI_ADMIN_BASE_URL and TRAI_ADMIN_API_KEY before running this script.');
  process.exit(1);
}

const url = new URL('/v1/admin/users', baseURL);
for (const [key, value] of Object.entries(options.queryParams)) {
  if (value != null && String(value).trim().length > 0) {
    url.searchParams.set(key, value);
  }
}

const response = await fetch(url, {
  headers: {
    'X-Trai-Admin-Token': adminToken
  }
});

const payload = await response.json().catch(() => null);

if (!response.ok) {
  console.error(`User list failed (${response.status})`);
  if (payload) {
    console.error(JSON.stringify(payload, null, 2));
  }
  process.exit(1);
}

if (options.json) {
  console.log(JSON.stringify(payload, null, 2));
} else {
  printTable(payload);
}

function parseArgs(args) {
  const values = {};
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) {
      values.query = arg;
      continue;
    }

    const key = arg.slice(2);
    const value = args[index + 1];
    if (value == null || value.startsWith('--')) {
      values[key] = true;
      continue;
    }

    values[key] = value;
    index += 1;
  }

  return {
    help: Boolean(values.help || values.h),
    json: Boolean(values.json),
    queryParams: {
      query: values.query,
      email: values.email,
      plan: values.plan,
      status: values.status,
      limit: values.limit ?? '25',
      offset: values.offset
    }
  };
}

function printUsage() {
  console.error([
    'Usage:',
    '  node Backend/scripts/list_admin_users.mjs [query]',
    '  node Backend/scripts/list_admin_users.mjs --email <email-fragment>',
    '  node Backend/scripts/list_admin_users.mjs --plan pro --limit 100',
    '  node Backend/scripts/list_admin_users.mjs --query tester --json'
  ].join('\n'));
}

function printTable(payload) {
  const users = payload?.users ?? [];
  const rows = users.map((user) => ({
    userID: user.userID,
    email: user.email ?? '',
    name: user.displayName ?? '',
    plan: user.subscription?.plan ?? '',
    source: user.subscription?.source ?? '',
    lastSessionAt: user.lastSessionAt ?? '',
    units30d: String(user.usageLast30Days?.unitsUsed ?? 0)
  }));

  console.table(rows);
  console.error(
    `Showing ${users.length} of ${payload?.pagination?.totalMatching ?? users.length}`
    + (payload?.pagination?.hasMore ? `; next offset ${payload.pagination.offset + payload.pagination.limit}` : '')
  );
}
