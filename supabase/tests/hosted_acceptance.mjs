// Opt-in checks against a disposable hosted project with real Auth/PostgREST.
// No admin key, account creation, migration execution, or fixture deletion.
import { randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

export class AcceptanceError extends Error {}

export class ApiError extends AcceptanceError {
  constructor(status, code) {
    const safeCode = /^[a-zA-Z0-9_]{1,32}$/.test(code ?? '') ? code : 'unknown';
    super(`Backend request failed: HTTP ${status}, code ${safeCode}.`);
    this.status = status;
    this.code = safeCode;
  }
}

const requireValue = (condition, message) => {
  if (!condition) throw new AcceptanceError(message);
};

export function validateConfig(raw, writeFixtures = false) {
  requireValue(writeFixtures && raw?.allowTestWrites === true,
    'Requires --write-fixtures and allowTestWrites: true for a disposable development project.');
  let url;
  try { url = new URL(raw.projectUrl); } catch {
    throw new AcceptanceError('Supply a hosted Supabase project URL.');
  }
  requireValue(/^[a-z0-9-]+$/.test(raw.expectedProjectRef ?? '') &&
    url.protocol === 'https:' && !url.username && !url.password && !url.port &&
    url.hostname === `${raw.expectedProjectRef}.supabase.co` &&
    url.pathname === '/' && !url.search && !url.hash,
  'Project URL must exactly match expectedProjectRef on HTTPS supabase.co.');
  const key = raw.publicKey;
  let publicKey = typeof key === 'string' && /^sb_publishable_[a-zA-Z0-9_-]+$/.test(key);
  if (typeof key === 'string' && key.split('.').length === 3) {
    try {
      publicKey = JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role === 'anon';
    } catch { publicKey = false; }
  }
  requireValue(publicKey, 'Use a publishable key or legacy anon key; privileged keys are rejected.');
  const accounts = {};
  for (const name of ['ownerA', 'ownerB', 'staff']) {
    const account = raw.accounts?.[name];
    requireValue(typeof account?.email === 'string' && account.email.includes('@') &&
      typeof account.password === 'string' && account.password.length >= 8 &&
      account.password !== 'REPLACE_LOCALLY', 'Supply three existing test-account credentials locally.');
    accounts[name] = { email: account.email.trim().toLowerCase(), password: account.password };
  }
  requireValue(new Set(Object.values(accounts).map(a => a.email)).size === 3,
    'The three test accounts must have different email addresses.');
  return { projectUrl: url.origin, publicKey: key, accounts };
}

export class ProjectApi {
  constructor(config, fetchImpl = fetch) {
    this.config = config;
    this.fetchImpl = fetchImpl;
    this.token = null;
  }

  async request(path, { method = 'GET', body, schema } = {}) {
    requireValue(path.startsWith('/auth/v1/') || path.startsWith('/rest/v1/'),
      'Only project Auth and REST endpoints are supported.');
    const url = new URL(path, this.config.projectUrl);
    requireValue(url.origin === this.config.projectUrl, 'Cross-project requests are rejected.');
    const headers = { apikey: this.config.publicKey, 'Content-Type': 'application/json' };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    if (schema) headers['Accept-Profile'] = schema;
    let response;
    let data;
    try {
      response = await this.fetchImpl(url, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'error', signal: AbortSignal.timeout(15000),
      });
      const text = await response.text();
      data = text ? JSON.parse(text) : null;
    } catch {
      // Response bodies, credentials and transport errors may contain secrets.
      throw new AcceptanceError('Request timed out, was redirected, or returned no usable JSON response.');
    }
    if (!response.ok) throw new ApiError(response.status, data?.code);
    return data;
  }

  rpc(name, body) { return this.request(`/rest/v1/rpc/${name}`, { method: 'POST', body }); }
  rows(table, query) { return this.request(`/rest/v1/${table}?${new URLSearchParams(query)}`); }

  async signIn(account) {
    const session = await this.request('/auth/v1/token?grant_type=password', {
      method: 'POST', body: account,
    });
    requireValue(typeof session?.access_token === 'string' && session.access_token.length > 0,
      'Sign-in did not return an access token.');
    this.token = session.access_token;
    const user = await this.request('/auth/v1/user');
    requireValue(typeof user?.id === 'string' && user.role === 'authenticated' &&
      Boolean(user.email_confirmed_at) && user.email?.toLowerCase() === account.email,
    'Each test identity must be an existing verified authenticated account.');
    return user;
  }

  async signOut() {
    if (!this.token) return;
    try { await this.request('/auth/v1/logout?scope=local', { method: 'POST' }); }
    finally { this.token = null; }
  }
}

export async function expectRejection(action, code, statuses) {
  try { await action(); } catch (error) {
    if (error instanceof ApiError && error.code === code && statuses.includes(error.status)) return;
    throw new AcceptanceError('Expected backend denial was not confirmed; check deployment and connectivity.');
  }
  throw new AcceptanceError('A request that should have been denied succeeded.');
}

export async function runAcceptance(raw, {
  writeFixtures = false, fetchImpl = fetch, record = async () => {}, log = () => {},
} = {}) {
  const config = validateConfig(raw, writeFixtures);
  const report = {
    runId: randomUUID(), projectUrl: config.projectUrl, startedAt: new Date().toISOString(),
    status: 'running', checks: [], fixtures: { businesses: [], sales: [] },
  };
  const clients = Object.fromEntries(['ownerA', 'ownerB', 'staff'].map(name =>
    [name, new ProjectApi(config, fetchImpl)]));
  const anonymous = new ProjectApi(config, fetchImpl);
  const check = (value, label) => {
    requireValue(value, `Check failed: ${label}.`);
    report.checks.push(label);
    log(`PASS ${label}`);
  };
  const denied = async (api, name, args, label, code = '42501', statuses = [401, 403]) => {
    await expectRejection(() => api.rpc(name, args), code, statuses);
    check(true, label);
  };
  const onlyIds = (rows, ids) => Array.isArray(rows) && rows.length === ids.length &&
    rows.every(row => ids.includes(row.id));
  const rowsFor = (api, table, business, select = 'id') =>
    api.rows(table, { select, business_id: `eq.${business}` });
  let failure;
  try {
    await record(report);
    const users = {};
    for (const name of Object.keys(clients)) users[name] = await clients[name].signIn(config.accounts[name]);
    check(new Set(Object.values(users).map(u => u.id)).size === 3, 'Three distinct verified Auth identities');
    const { ownerA, ownerB, staff } = clients;
    await denied(anonymous, 'pos_create_business', {
      request_id: randomUUID(), business_name: 'Denied anonymous test', branch_name: 'Main',
    }, 'Anonymous business creation denied');
    await expectRejection(() => ownerA.request('/rest/v1/access_audit?select=id&limit=0',
      { schema: 'fastpas_private' }), 'PGRST106', [406]);
    check(true, 'Private schema is absent from exposed API schemas');

    const createBusiness = async (api, label) => {
      const id = randomUUID();
      // Record attempted IDs first: a timeout can lose the response after commit.
      report.fixtures.businesses.push({ id, label });
      await record(report);
      const args = { request_id: id, business_name: `Acceptance ${report.runId} ${label}`, branch_name: 'Main' };
      check(await api.rpc('pos_create_business', args) === id, `Create ${label} business`);
      check(await api.rpc('pos_create_business', args) === id, `Retry ${label} business without duplication`);
      const branches = await rowsFor(api, 'pos_branches', id);
      check(Array.isArray(branches) && branches.length === 1, `One branch after ${label} business retry`);
      return { id, branch: branches[0].id };
    };
    const a = await createBusiness(ownerA, 'owner-a-first');
    const a2 = await createBusiness(ownerA, 'owner-a-second');
    const b = await createBusiness(ownerB, 'owner-b');
    const ownBusinesses = await ownerA.rows('pos_businesses', { select: 'id', id: `in.(${a.id},${a2.id},${b.id})` });
    check(onlyIds(ownBusinesses, [a.id, a2.id]), 'Owner sees both own businesses and excludes unrelated business');
    check(onlyIds(await ownerB.rows('pos_businesses', { select: 'id', id: `eq.${a.id}` }), []),
      'Unrelated owner cannot read first business');
    check(onlyIds(await rowsFor(ownerB, 'pos_branches', a.id), []), 'Unrelated owner cannot read branches');
    await denied(ownerB, 'pos_staff_access', { business: a.id }, 'Unrelated owner cannot list staff');
    await denied(ownerB, 'pos_create_business', {
      request_id: a.id, business_name: 'Denied takeover', branch_name: 'Main',
    }, 'Existing business cannot be claimed by another owner');

    const product = { name: 'Acceptance water', sku: `acceptance-${report.runId}`, cents: 2800 };
    const addArgs = {
      business: a.id, branch: a.branch, product_name: product.name,
      product_sku: product.sku, unit_cents: product.cents, opening_quantity: 10,
    };
    const productId = await ownerA.rpc('pos_add_item', addArgs);
    check(typeof productId === 'string', 'Owner creates product and opening stock');
    check(onlyIds(await rowsFor(ownerB, 'pos_items', a.id), []), 'Catalog is isolated from unrelated owner');
    await denied(ownerB, 'pos_add_item', addArgs, 'Unrelated owner cannot add catalog items');
    await denied(ownerA, 'pos_add_item', { ...addArgs, branch: b.branch, product_sku: `${product.sku}-invalid` },
      'Cross-business stock relationship rejected', '23503', [409]);

    const invite = async (api, workspace, role) => api.rpc('pos_invite_staff', {
      business: workspace.id, branch: workspace.branch, invite_email: config.accounts.staff.email, invite_role: role,
    });
    const code = await invite(ownerA, a, 'cashier');
    await denied(ownerB, 'pos_accept_invitation', { invite_code: code }, 'Invitation rejects the wrong verified email');
    check(await staff.rpc('pos_accept_invitation', { invite_code: code }) === a.id, 'Verified staff accepts invitation');
    await denied(staff, 'pos_accept_invitation', { invite_code: code }, 'Used invitation cannot be replayed');
    const bCode = await invite(ownerB, b, 'employee');
    check(await staff.rpc('pos_accept_invitation', { invite_code: bCode }) === b.id, 'Same account joins another business with a different role');
    const access = await ownerA.rpc('pos_staff_access', { business: a.id });
    const member = access?.members?.find(m => m.user_id === users.staff.id);
    check(member?.role === 'cashier' && member.branch_ids?.includes(a.branch), 'Owner staff listing includes role and branch assignment');
    await denied(staff, 'pos_staff_access', { business: a.id }, 'Cashier cannot list owner staff controls');
    await denied(staff, 'pos_change_staff_access', { business: a.id, member: users.staff.id, new_role: 'manager' },
      'Cashier cannot promote themselves');
    await expectRejection(() => staff.request(`/rest/v1/pos_memberships?business_id=eq.${a.id}&user_id=eq.${users.staff.id}`,
      { method: 'PATCH', body: { role: 'owner' } }), '42501', [403]);
    check(true, 'Direct membership edits denied through REST');
    await denied(ownerA, 'pos_change_staff_access', { business: a.id, member: users.ownerA.id, new_role: 'cashier' },
      'Owner membership protected', '22023', [400]);

    const sale = {
      id: randomUUID(), business_id: a.id, branch_id: a.branch, device_id: randomUUID(),
      occurred_at: new Date().toISOString(), cash_cents: product.cents,
      items: [{ product_id: productId, name: product.name, sku: product.sku, quantity: 1, unit_cents: product.cents }],
    };
    report.fixtures.sales.push(sale.id);
    await record(report);
    const saleReplies = await Promise.all([staff.rpc('pos_sync_cash_sale', { sale }), staff.rpc('pos_sync_cash_sale', { sale })]);
    check(saleReplies.every(id => id === sale.id), 'Concurrent identical sale uploads return the same receipt');
    const quantity = async () => {
      const rows = await rowsFor(ownerA, 'pos_item_stock', a.id, 'product_id,quantity');
      return rows.find(row => row.product_id === productId)?.quantity;
    };
    check(await quantity() === 9, 'Concurrent retries deduct stock once');
    check(onlyIds(await rowsFor(ownerA, 'pos_cash_sales', a.id), [sale.id]), 'Exactly one saved receipt after concurrent retries');
    check(onlyIds(await rowsFor(ownerB, 'pos_cash_sales', a.id), []), 'Unrelated owner cannot read receipts');
    await denied(staff, 'pos_sync_cash_sale', { sale: { ...sale, cash_cents: 5600 } },
      'Existing receipt rejects a different payload', '22023', [400]);
    await denied(staff, 'pos_sync_cash_sale', { sale: {
      ...sale, id: randomUUID(), items: [{ ...sale.items[0], unit_cents: 2900 }],
    } }, 'Stale catalog price rejected', '22023', [400]);
    check(await quantity() === 9, 'Rejected sale leaves stock unchanged');
    await denied(staff, 'pos_sync_cash_sale', { sale: { ...sale, id: randomUUID(), business_id: b.id, branch_id: b.branch } },
      'Employee role cannot sell in second business');

    const unusedCode = await invite(ownerA, a, 'cashier');
    await ownerA.rpc('pos_set_staff_branches', { business: a.id, member: users.staff.id, branches: [] });
    check(onlyIds(await rowsFor(staff, 'pos_branches', a.id), []), 'Cleared branch access hides branch');
    check(onlyIds(await rowsFor(staff, 'pos_item_stock', a.id, 'product_id'), []), 'Cleared branch access hides branch stock');
    const pendingSale = { ...sale, id: randomUUID() };
    report.fixtures.sales.push(pendingSale.id);
    await record(report);
    await denied(staff, 'pos_sync_cash_sale', { sale: pendingSale }, 'Unsynced sale denied while branch access is revoked');
    check(await quantity() === 9, 'Revoked upload does not change stock');
    check(onlyIds(await rowsFor(staff, 'pos_branches', b.id), [b.branch]), 'Branch revocation preserves access in another business');
    await ownerA.rpc('pos_set_staff_branches', { business: a.id, member: users.staff.id, branches: [a.branch] });
    await denied(staff, 'pos_accept_invitation', { invite_code: unusedCode }, 'Branch change cancels unused invitation');
    check(await staff.rpc('pos_sync_cash_sale', { sale: pendingSale }) === pendingSale.id,
      'Original unsynced payload uploads after access restoration');
    check(await staff.rpc('pos_sync_cash_sale', { sale: pendingSale }) === pendingSale.id && await quantity() === 8,
      'Restored sale retry does not deduct twice');

    await ownerA.rpc('pos_change_staff_access', { business: a.id, member: users.staff.id, new_role: null });
    check(onlyIds(await rowsFor(staff, 'pos_items', a.id), []), 'Removed membership loses catalog access');
    await denied(staff, 'pos_sync_cash_sale', { sale: pendingSale }, 'Removed member cannot upload receipts');
    check(onlyIds(await rowsFor(ownerA, 'pos_cash_sales', a.id), [sale.id, pendingSale.id]),
      'Historical receipts survive staff removal');
    const remaining = await staff.rows('pos_memberships', { select: 'role', business_id: `eq.${b.id}`, user_id: `eq.${users.staff.id}` });
    check(remaining.length === 1 && remaining[0].role === 'employee', 'Other business membership and role survive removal');
  } catch (error) {
    failure = error instanceof AcceptanceError ? error : new AcceptanceError('Acceptance stopped; no passing hosted result is assumed.');
  } finally {
    const cleanup = await Promise.allSettled(Object.values(clients).map(client => client.signOut()));
    report.sessionsClosed = cleanup.every(result => result.status === 'fulfilled');
    if (!report.sessionsClosed && !failure) failure = new AcceptanceError('Test session cleanup failed; review the test accounts.');
    report.status = failure ? 'failed' : 'passed';
    report.finishedAt = new Date().toISOString();
    if (failure) report.failure = failure.message;
    await record(report);
  }
  if (failure) throw failure;
  return report;
}

async function main() {
  const args = process.argv.slice(2);
  requireValue(args.length === 2 && args[1] === '--write-fixtures',
    'Usage: node supabase/tests/hosted_acceptance.mjs config/acceptance.local.json --write-fixtures');
  let raw;
  try { raw = JSON.parse(await readFile(resolve(args[0]), 'utf8')); } catch {
    throw new AcceptanceError('Cannot read acceptance configuration JSON.');
  }
  validateConfig(raw, true);
  let reportPath;
  const report = await runAcceptance(raw, {
    writeFixtures: true, log: console.log,
    record: async result => {
      reportPath ??= resolve('config', `acceptance-${result.runId}.local.json`);
      await mkdir(dirname(reportPath), { recursive: true });
      await writeFile(reportPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 });
    },
  });
  console.log(`Hosted acceptance passed: ${report.checks.length} checks. Fixtures retained; report: ${reportPath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    console.error(error instanceof AcceptanceError ? error.message : 'Local runner failed; no hosted result is assumed.');
    console.error('Inspect the ignored config/acceptance-*.local.json report for attempted fixture IDs.');
    process.exitCode = 1;
  });
}
