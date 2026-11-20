'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const pageFiles = ['index.html', 'parent.html', 'tablet.html', 'parent-staging.html', 'tablet-staging.html'];
const codeFile = read('v3-client.js');

for (const p of pageFiles) {
  const html = read(p);
  assert.match(html, /<title>/i, p + ' missing title');
  const inline = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
    .map(m => m[1]).filter(s => s.trim());
  for (const script of inline) new vm.Script(script, { filename: p });
  console.log('PASS JavaScript parsing:', p, inline.length, 'inline script(s)');
}
new vm.Script(codeFile, { filename: 'v3-client.js' });
assert.match(read('parent.html'), /src="\.\/v3-client\.js"/);
assert.match(read('tablet.html'), /src="\.\/v3-client\.js"/);
assert.match(read('index.html'), /href="\.\/parent\.html"/);

assert.match(read('parent-staging.html'), /familyhub-staging-parent-session/);
assert.match(read('tablet-staging.html'), /familyhub-staging-tablet-session/);
assert.match(read('parent-staging.html'), /kytphqpfpchmmmbsmpcz\.supabase\.co/);
assert.match(read('tablet-staging.html'), /kytphqpfpchmmmbsmpcz\.supabase\.co/);
assert.doesNotMatch(read('parent-staging.html'), /FamilyHubV3\.client\('familyhub-session'\)/);
assert.doesNotMatch(read('tablet-staging.html'), /FamilyHubV3\.client\('familyhub-tablet-session'\)/);

assert.match(read('index.html'), /data-tab="calendar"/);
assert.doesNotMatch(read('tablet.html'), /familyhub-session['"]/);
assert.doesNotMatch(codeFile, /sb_secret_/);
console.log('PASS branch page wiring / no browser secret keys');

const fakeStore = new Map();
const sessionStorage = {
  getItem: key => fakeStore.get(key) || null,
  setItem: (key, value) => fakeStore.set(key, value),
  removeItem: key => fakeStore.delete(key)
};
const uid = '00000000-0000-0000-0000-000000000001';
const familyId = '00000000-0000-0000-0000-000000000002';
let currentRole = 'admin', calls = [];

async function fetchStub(url, options) {
  const route = url.replace('https://dyzdyqllmfoltiqkfvxm.supabase.co', '');
  calls.push({ route, options });
  let result;
  if (route.includes('grant_type=password')) {
    result = { access_token: 'TEST_TOKEN', refresh_token: 'TEST_REFRESH', expires_in: 3600 };
  } else if (route.endsWith('/auth/v1/user')) {
    result = { id: uid };
  } else if (route.includes('/rest/v1/family_members')) {
    result = [{ role: currentRole, family_id: familyId }];
  } else if (route.includes('/rest/v1/chore_assignments')) {
    result = [{ id: 'chore-id', title: 'Make bed' }];
  } else {
    result = null;
  }
  return { ok: true, status: 200, text: async () => JSON.stringify(result) };
}

async function main() {
  const window = {};
  const context = vm.createContext({ window, sessionStorage, fetch: fetchStub, Date, Intl, Error });
  vm.runInContext(codeFile, context, { filename: 'v3-client.js' });
  const lib = window.FamilyHubV3;
  const parent = lib.client('familyhub-session');
  await parent.signIn(' parent@example.org ', 'not-a-real-password');
  const membership = await parent.membership('admin');
  assert.equal(membership.familyId, familyId);
  assert.equal(membership.userId, uid);
  const assignments = await parent.list('chore_assignments', familyId);
  assert.equal(assignments.length, 1);
  await parent.rpc('approve_chore', { target_completion_id: 'test-id' });
  const rpcCall = calls.find(x => x.route === '/rest/v1/rpc/approve_chore');
  assert.equal(rpcCall.options.method, 'POST');
  assert.deepEqual(JSON.parse(rpcCall.options.body), { target_completion_id: 'test-id' });
  assert.ok(rpcCall.options.headers.Authorization.startsWith('Bearer '));
  assert.ok(calls.some(x => x.route.includes('family_id=eq.' + familyId)));
  await assert.rejects(parent.membership('tablet'), /not authorized/);
  parent.signOut();
  assert.equal(fakeStore.has('familyhub-session'), false);

  currentRole = 'tablet';
  const tablet = lib.client('familyhub-tablet-session');
  await tablet.signIn(' tablet@example.org ', 'not-a-real-password');
  assert.equal((await tablet.membership('tablet')).familyId, familyId);
  await assert.rejects(tablet.membership('admin'), /not authorized/);
  tablet.signOut();
  console.log('PASS mocked parent/tablet login, role separation, family filter, RPC and logout');

  const foundation = read('drafts/v3-security-foundation.sql');
  const rpc = read('drafts/v3-rpc.sql');
  assert.match(foundation, /role IN \('admin', 'member', 'tablet'\)/);
  assert.match(foundation, /"Admins manage calendar"/);
  assert.match(foundation, /"Only own membership or family admin"/);
  assert.match(foundation, /point_transactions_reward_identity_fk/);
  assert.match(rpc, /CREATE OR REPLACE FUNCTION public\.submit_chore/);
  assert.match(rpc, /CREATE OR REPLACE FUNCTION public\.approve_reward_request/);
  assert.match(rpc, /IF available_points < r\.points_cost_snapshot THEN/);
  assert.match(rpc, /GRANT EXECUTE ON FUNCTION public\.approve_chore\(uuid\) TO authenticated/);
  assert.match(read('drafts/v3-regression-tests.sql'), /ROLLBACK;/);
  console.log('PASS static security invariants (does NOT replace live database testing)');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
