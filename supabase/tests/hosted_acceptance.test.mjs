import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  AcceptanceError, ApiError, ProjectApi, expectRejection, runAcceptance, validateConfig,
} from './hosted_acceptance.mjs';

const configuration = () => ({
  projectUrl: 'https://acceptance-test.supabase.co', expectedProjectRef: 'acceptance-test',
  publicKey: 'sb_publishable_test_key', allowTestWrites: true,
  accounts: {
    ownerA: { email: 'owner-a@example.test', password: 'private-password-a' },
    ownerB: { email: 'owner-b@example.test', password: 'private-password-b' },
    staff: { email: 'staff@example.test', password: 'private-password-staff' },
  },
});
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });

test('both write opt-ins are required before any network request', async () => {
  let requests = 0;
  const fetchImpl = async () => { requests++; throw new Error('Unexpected request'); };
  await assert.rejects(runAcceptance(configuration(), { fetchImpl }), /Requires --write-fixtures/);
  await assert.rejects(runAcceptance({ ...configuration(), allowTestWrites: false },
    { writeFixtures: true, fetchImpl }), /Requires --write-fixtures/);
  assert.equal(requests, 0);
});

test('privileged and unknown project keys cannot be used to bypass RLS checks', () => {
  const jwt = role => `e30.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.signature`;
  for (const publicKey of ['sb_secret_admin', jwt('service_role'), jwt('authenticated'), 'unknown', 'e30.invalid.signature']) {
    assert.throws(() => validateConfig({ ...configuration(), publicKey }, true), /privileged keys are rejected/);
  }
  assert.equal(validateConfig({ ...configuration(), publicKey: jwt('anon') }, true).publicKey, jwt('anon'));
  assert.equal(validateConfig(configuration(), true).publicKey, 'sb_publishable_test_key');
});

test('passwords cannot be sent to a different project or non-HTTPS destination', () => {
  for (const projectUrl of [
    'http://acceptance-test.supabase.co', 'https://different.supabase.co',
    'https://acceptance-test.supabase.co.attacker.test', 'https://acceptance-test.supabase.co/path',
    'https://user:password@acceptance-test.supabase.co', 'https://acceptance-test.supabase.co/?key=secret',
  ]) {
    assert.throws(() => validateConfig({ ...configuration(), projectUrl }, true), /exactly match/);
  }
});

test('test accounts must be distinct even with email case differences', () => {
  const config = configuration();
  config.accounts.staff.email = 'OWNER-A@example.test';
  assert.throws(() => validateConfig(config, true), /different email/);
});

test('publishable keys stay in apikey and requests reject redirects', async () => {
  const calls = [];
  const api = new ProjectApi(validateConfig(configuration(), true), async (url, options) => {
    calls.push({ url, options });
    return json([]);
  });
  await api.rows('pos_businesses', { select: 'id' });
  assert.equal(calls[0].options.headers.apikey, 'sb_publishable_test_key');
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.equal(calls[0].options.redirect, 'error');
  assert.ok(calls[0].options.signal instanceof AbortSignal);
  api.token = 'user-access-token';
  await api.rows('pos_businesses', { select: 'id' });
  assert.equal(calls[1].options.headers.Authorization, 'Bearer user-access-token');
  await assert.rejects(api.request('https://attacker.test/auth/v1/user'), /Only project/);
  assert.equal(calls.length, 2);
});

test('HTTP failures do not include response messages, details, hints, or tokens', async () => {
  const api = new ProjectApi(validateConfig(configuration(), true), async () => json({
    code: '42501', message: 'private-password-a', details: 'user-access-token', hint: 'refresh-token',
  }, 403));
  await assert.rejects(api.rpc('pos_staff_access', { business: 'fixture' }), error => {
    assert.equal(error.message, 'Backend request failed: HTTP 403, code 42501.');
    return true;
  });
});

test('transport errors and malformed responses are sanitized', async () => {
  for (const fetchImpl of [
    async () => { throw new Error('private-password-a user-access-token'); },
    async () => new Response('<html>private-password-a</html>', { status: 502 }),
  ]) {
    const api = new ProjectApi(validateConfig(configuration(), true), fetchImpl);
    await assert.rejects(api.rows('pos_businesses', {}), error => {
      assert.ok(error instanceof AcceptanceError);
      assert.doesNotMatch(error.message, /private-password|user-access-token/);
      return true;
    });
  }
});

test('only the expected database denial code and HTTP status count as a denial', async () => {
  await expectRejection(async () => { throw new ApiError(403, '42501'); }, '42501', [401, 403]);
  for (const error of [new ApiError(404, 'PGRST202'), new ApiError(500, '42501'),
    new ApiError(403, 'invalid_jwt'), new Error('Network down')]) {
    await assert.rejects(expectRejection(async () => { throw error; }, '42501', [401, 403]),
      /denial was not confirmed/);
  }
  await assert.rejects(expectRejection(async () => null, '42501', [401, 403]), /should have been denied succeeded/);
});

test('real user lookup is required and unverified accounts fail before fixture writes', async () => {
  const calls = [];
  const records = [];
  const fetchImpl = async (url, options) => {
    calls.push({ path: url.pathname, query: url.search, options });
    if (url.pathname.endsWith('/token')) return json({ access_token: 'private-access', refresh_token: 'private-refresh' });
    if (url.pathname.endsWith('/user')) return json({
      id: '10000000-0000-4000-8000-000000000001', role: 'authenticated', email: 'owner-a@example.test', email_confirmed_at: null,
    });
    if (url.pathname.endsWith('/logout')) return new Response(null, { status: 204 });
    throw new Error('Unexpected fixture write');
  };
  await assert.rejects(runAcceptance(configuration(), {
    writeFixtures: true, fetchImpl, record: async report => records.push(structuredClone(report)),
  }), /existing verified authenticated/);
  assert.equal(calls.length, 3);
  assert.equal(calls[1].options.headers.Authorization, 'Bearer private-access');
  assert.equal(calls[2].query, '?scope=local');
  assert.equal(records.at(-1).status, 'failed');
  assert.deepEqual(records.at(-1).fixtures.businesses, []);
  assert.equal(records.at(-1).sessionsClosed, true);
  assert.doesNotMatch(JSON.stringify(records), /private-access|private-refresh|private-password|owner-a@example/);
});

test('three email addresses resolving to the same identity cannot create fixtures', async () => {
  let account;
  let writes = 0;
  let logouts = 0;
  const fetchImpl = async (url, options) => {
    if (url.pathname.endsWith('/token')) {
      account = JSON.parse(options.body);
      return json({ access_token: `token-${account.email}` });
    }
    if (url.pathname.endsWith('/user')) return json({
      id: '10000000-0000-4000-8000-000000000001', role: 'authenticated', email: account.email,
      email_confirmed_at: '2026-10-26T00:00:00Z',
    });
    if (url.pathname.endsWith('/logout')) { logouts++; return new Response(null, { status: 204 }); }
    writes++;
    return json(null);
  };
  await assert.rejects(runAcceptance(configuration(), { writeFixtures: true, fetchImpl }), /Three distinct verified/);
  assert.equal(writes, 0);
  assert.equal(logouts, 3);
});

test('CLI refuses the unconfigured example without attempting hosted acceptance', () => {
  const script = fileURLToPath(new URL('./hosted_acceptance.mjs', import.meta.url));
  const example = fileURLToPath(new URL('../../config/acceptance.example.json', import.meta.url));
  const result = spawnSync(process.execPath, [script, example, '--write-fixtures'], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /allowTestWrites: true/);
  assert.doesNotMatch(result.stdout, /PASS/);
});
