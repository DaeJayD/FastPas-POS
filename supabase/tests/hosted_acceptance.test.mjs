import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { mkdtemp, readFile, readdir, rm, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  AcceptanceError, ApiError, ProjectApi, expectRejection, runAcceptance, validateConfig,
  concurrentSaleUploads, saveReport,
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

test('concurrent receipt check waits for the other request before propagating failure', async () => {
  let finishSecond;
  let calls = 0;
  const error = new ApiError(403, '42501');
  const sale = { id: 'stable-receipt' };
  const api = {
    rpc(name, args) {
      assert.equal(name, 'pos_sync_cash_sale');
      assert.equal(args.sale, sale);
      calls++;
      if (calls === 1) return Promise.reject(error);
      return new Promise(resolve => { finishSecond = resolve; });
    },
  };
  let settled = false;
  const upload = concurrentSaleUploads(api, sale).finally(() => { settled = true; });
  const rejection = assert.rejects(upload, result => result === error);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 2);
  assert.equal(settled, false);
  finishSecond(sale.id);
  await rejection;
  assert.equal(settled, true);
});

test('concurrent receipt check retains both successful server replies', async () => {
  const ids = ['first-reply', 'second-reply'];
  const replies = await concurrentSaleUploads({ rpc: async () => ids.shift() }, { id: 'receipt' });
  assert.deepEqual(replies, ['first-reply', 'second-reply']);
});

test('reports replace the previous manifest and leave no pending file after success', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'fastpas-acceptance-report-'));
  const path = join(directory, 'acceptance-fixture.local.json');
  const pending = join(directory, 'acceptance-fixture.pending.local.json');
  try {
    await saveReport(path, { status: 'running', fixtures: ['first'] });
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), { status: 'running', fixtures: ['first'] });
    await saveReport(path, { status: 'failed', fixtures: ['first', 'attempted-second'] });
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), { status: 'failed', fixtures: ['first', 'attempted-second'] });
    assert.deepEqual(await readdir(directory), ['acceptance-fixture.local.json']);
    await assert.rejects(saveReport(join(directory, 'report.json'), {}), /ignored .local.json/);
  } finally {
    await rm(path, { force: true });
    await rm(pending, { force: true });
    await rmdir(directory);
  }
});

test('missing RPCs identify the failed check and never count as permission denial', async () => {
  const config = configuration();
  const userIds = new Map(Object.values(config.accounts).map((account, index) =>
    [account.email, `10000000-0000-4000-8000-00000000000${index + 1}`]));
  const tokens = new Map();
  let lastReport;
  const fetchImpl = async (url, options) => {
    if (url.pathname.endsWith('/token')) {
      const account = JSON.parse(options.body);
      const token = `private-${userIds.get(account.email)}`;
      tokens.set(`Bearer ${token}`, account.email);
      return json({ access_token: token });
    }
    if (url.pathname.endsWith('/user')) {
      const email = tokens.get(options.headers.Authorization);
      return json({ id: userIds.get(email), role: 'authenticated', email, email_confirmed_at: '2026-10-30T00:00:00Z' });
    }
    if (url.pathname.endsWith('/logout')) return new Response(null, { status: 204 });
    return json({ code: 'PGRST202', message: 'private backend details' }, 404);
  };
  await assert.rejects(runAcceptance(config, {
    writeFixtures: true, fetchImpl, record: async report => { lastReport = structuredClone(report); },
  }), /Anonymous business creation denied: Expected backend denial was not confirmed/);
  assert.equal(lastReport.status, 'failed');
  assert.equal(lastReport.checks.length, 1);
  assert.equal(lastReport.sessionsClosed, true);
  assert.deepEqual(lastReport.fixtures.businesses, []);
  assert.doesNotMatch(JSON.stringify(lastReport), /private backend details|private-password/);
});
