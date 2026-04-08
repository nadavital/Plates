#!/usr/bin/env node

const [, , emailArg, planArg = 'pro', statusArg = 'active', sourceArg] = process.argv;

if (!emailArg) {
  console.error('Usage: node Backend/scripts/override_staging_subscription.mjs <email> [plan] [status] [source]');
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
    email: emailArg,
    plan: planArg,
    status: statusArg,
    source: sourceArg,
    createdBy: 'local-script',
    reason: 'staging tester override'
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
