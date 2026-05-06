#!/usr/bin/env node

const args = process.argv.slice(2);
const options = parseArgs(args);

if (!options.lookup) {
  console.error([
    'Usage:',
    '  node Backend/scripts/override_staging_subscription.mjs <email> [plan] [status] [source]',
    '  node Backend/scripts/override_staging_subscription.mjs --email <email> [--plan pro] [--status active] [--source adminGrant]',
    '  node Backend/scripts/override_staging_subscription.mjs --user-id <id> [--plan pro]',
    '  node Backend/scripts/override_staging_subscription.mjs --app-account-token <token> [--plan pro]',
    '  node Backend/scripts/override_staging_subscription.mjs --original-transaction-id <id> [--plan pro]'
  ].join('\n'));
  process.exit(1);
}

const baseURL = process.env.TRAI_ADMIN_BASE_URL?.trim();
const adminToken = process.env.TRAI_ADMIN_API_KEY?.trim();

if (!baseURL || !adminToken) {
  console.error('Set TRAI_ADMIN_BASE_URL and TRAI_ADMIN_API_KEY before running this script.');
  process.exit(1);
}

const response = await fetch(new URL('/v1/admin/subscription-override', baseURL), {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Trai-Admin-Token': adminToken
  },
  body: JSON.stringify({
    ...options.lookup,
    plan: options.plan,
    status: options.status,
    source: options.source,
    createdBy: 'local-script',
    reason: options.reason
  })
});

const payload = await response.json().catch(() => null);

if (!response.ok) {
  console.error(`Override failed (${response.status})`);
  if (payload) {
    console.error(JSON.stringify(payload, null, 2));
  }
  process.exit(1);
}

console.log(JSON.stringify(payload, null, 2));

function parseArgs(args) {
  if (args.length > 0 && !args[0].startsWith('--')) {
    return {
      lookup: { email: args[0] },
      plan: args[1] ?? 'pro',
      status: args[2] ?? 'active',
      source: args[3],
      reason: 'tester subscription override'
    };
  }

  const values = {};
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) {
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

  const lookup = firstLookup(values);
  return {
    lookup,
    plan: values.plan ?? 'pro',
    status: values.status ?? 'active',
    source: values.source,
    reason: values.reason ?? 'tester subscription override'
  };
}

function firstLookup(values) {
  if (values.email) {
    return { email: values.email };
  }
  if (values['user-id']) {
    return { userID: values['user-id'] };
  }
  if (values['app-account-token']) {
    return { appAccountToken: values['app-account-token'] };
  }
  if (values['original-transaction-id']) {
    return { originalTransactionId: values['original-transaction-id'] };
  }
  return null;
}
