// Opt-in checks against a disposable hosted project with real Auth/PostgREST.
// No admin key, account creation, migration execution, or fixture deletion.
import { randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
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

export async function concurrentSaleUploads(api, sale) {
  // Both requests may already have reached the server. Wait for both before
  // reporting failure or closing sessions, even when one rejects immediately.
  const results = await Promise.allSettled([
    api.rpc('pos_sync_cash_sale', { sale }), api.rpc('pos_sync_cash_sale', { sale }),
  ]);
  const failure = results.find(result => result.status === 'rejected');
  if (failure) throw failure.reason;
  return results.map(result => result.value);
}

export function receiptBranding(settings, branchId) {
  const business = settings?.business;
  const branch = settings?.branches?.find(row => row.id === branchId);
  requireValue(business && branch && branch.business_id === business.id,
    'Receipt branding must belong to the selected business and branch.');
  return {
    business_id: business.id, branch_id: branch.id,
    business_name: business.name, branch_name: branch.name,
    business_address: business.address, branch_address: branch.address,
    phone: business.contact_phone, email: business.contact_email,
    footer: business.receipt_footer, currency: 'PHP',
  };
}

// Exercises the same public RPC contract as the settings screen. Call only
// for newly recorded acceptance fixtures, after staff has joined the business.
export async function checkBusinessSettings({
  owner, unrelated, staff, anonymous, business, otherBusiness, check, recordBranch,
}) {
  const reject = async (api, rpc, args, label, code = '42501', statuses = [401, 403]) => {
    try { await expectRejection(() => api.rpc(rpc, args), code, statuses); }
    catch (error) { throw new AcceptanceError(`${label}: ${error.message}`); }
    check(true, label);
  };
  const initial = await owner.rpc('pos_business_settings', { business: business.id });
  const main = initial?.branches?.find(row => row.id === business.branch);
  check(initial?.business?.id === business.id && initial.business.settings_version === 1 &&
    main?.business_id === business.id && main.settings_version === 1,
  'Owner reads scoped business settings and initial versions');
  const update = {
    business: business.id, expected_version: 1,
    business_name: `${initial.business.name} updated`, business_address: 'Acceptance address A',
    phone_number: '0000000000', email_address: 'receipt@example.test', footer: 'Acceptance footer A',
  };
  const branchRequest = {
    business: business.id, request_id: randomUUID(),
    branch_name: 'Acceptance second branch', branch_address: 'Acceptance branch address',
  };
  const branchEdit = {
    business: business.id, branch: business.branch, expected_version: 1,
    branch_name: 'Acceptance renamed main', branch_address: 'Acceptance main address',
  };
  // Include every new RPC: a missing migration must fail, not look like denial.
  for (const [role, api] of [['Anonymous', anonymous], ['Unrelated owner', unrelated], ['Cashier', staff]]) {
    for (const [rpc, args] of [
      ['pos_business_settings', { business: business.id }],
      ['pos_update_business', update], ['pos_create_branch', branchRequest], ['pos_update_branch', branchEdit],
    ]) await reject(api, rpc, args, `${role} cannot call ${rpc}`);
  }
  await reject(owner, 'pos_update_business', { ...update, business_name: ' ' },
    'Blank business name rejected', '22023', [400]);
  await reject(owner, 'pos_update_business', { ...update, email_address: 'invalid' },
    'Invalid business email rejected', '22023', [400]);
  check(await owner.rpc('pos_update_business', update) === 2, 'Owner updates business settings with its version');
  // PostgREST maps SQLSTATE class 40 to HTTP 500. Require the exact conflict
  // code as well; unrelated server failures must never pass this check.
  await reject(owner, 'pos_update_business', update,
    'Stale business edit rejected', '40001', [500]);
  await recordBranch({ id: branchRequest.request_id, businessId: business.id });
  const branchReplies = await Promise.allSettled([
    owner.rpc('pos_create_branch', branchRequest), owner.rpc('pos_create_branch', branchRequest),
  ]);
  const failedBranch = branchReplies.find(result => result.status === 'rejected');
  if (failedBranch) throw failedBranch.reason;
  check(branchReplies.every(result => result.value === branchRequest.request_id),
    'Concurrent branch retries return one stable branch identity');
  await reject(owner, 'pos_create_branch', { ...branchRequest, branch_name: 'Changed retry' },
    'Branch retry with changed details rejected', '22023', [400]);
  await reject(owner, 'pos_create_branch', { ...branchRequest, request_id: otherBusiness.branch },
    'Cross-business branch identity cannot be claimed');
  check(await owner.rpc('pos_update_branch', branchEdit) === 2, 'Owner edits branch without replacing its identity');
  await reject(owner, 'pos_update_branch', branchEdit, 'Stale branch edit rejected', '40001', [500]);
  await reject(owner, 'pos_update_branch', { ...branchEdit, branch: otherBusiness.branch },
    'Cross-business branch edit rejected');
  const updated = await owner.rpc('pos_business_settings', { business: business.id });
  const changedMain = updated?.branches?.find(row => row.id === business.branch);
  const created = updated?.branches?.filter(row => row.id === branchRequest.request_id);
  check(updated?.business?.id === business.id && updated.business.name === update.business_name &&
    updated.business.address === update.business_address && updated.business.contact_phone === update.phone_number &&
    updated.business.contact_email === update.email_address && updated.business.receipt_footer === update.footer &&
    updated.business.settings_version === 2, 'Business details round-trip through the settings RPC');
  check(updated.branches.length === initial.branches.length + 1 && created?.length === 1 &&
    created[0].business_id === business.id && created[0].name === branchRequest.branch_name &&
    created[0].address === branchRequest.branch_address && changedMain?.settings_version === 2 &&
    changedMain.name === branchEdit.branch_name && changedMain.address === branchEdit.branch_address,
  'Branch retries create one row and branch edits retain scope and version');
  return updated;
}

export async function saveReport(reportPath, report) {
  requireValue(reportPath.endsWith('.local.json'), 'Acceptance reports must use an ignored .local.json filename.');
  const pendingPath = reportPath.replace(/\.local\.json$/, '.pending.local.json');
  await mkdir(dirname(reportPath), { recursive: true });
  await writeFile(pendingPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  // Preserve the previous complete manifest if a write is interrupted.
  await rename(pendingPath, reportPath);
}

export async function runAcceptance(raw, {
  writeFixtures = false, fetchImpl = fetch, record = async () => {}, log = () => {},
} = {}) {
  const config = validateConfig(raw, writeFixtures);
  const report = {
    runId: randomUUID(), projectUrl: config.projectUrl, startedAt: new Date().toISOString(),
    status: 'running', checks: [], fixtures: { businesses: [], branches: [], sales: [] },
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
    try { await expectRejection(() => api.rpc(name, args), code, statuses); }
    catch (error) { throw new AcceptanceError(`${label}: ${error.message}`); }
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

    const settings = await checkBusinessSettings({
      owner: ownerA, unrelated: ownerB, staff, anonymous, business: a, otherBusiness: b, check,
      recordBranch: async branch => { report.fixtures.branches.push(branch); await record(report); },
    });
    check(onlyIds(await rowsFor(staff, 'pos_branches', a.id), [a.branch]),
      'Creating a branch does not silently assign staff access');
    for (const [table, body] of [
      ['pos_businesses', { name: 'Denied direct rename' }],
      ['pos_branches', { address: 'Denied direct address' }],
    ]) {
      const query = table === 'pos_businesses' ? `id=eq.${a.id}` : `business_id=eq.${a.id}`;
      await expectRejection(() => ownerA.request(`/rest/v1/${table}?${query}`,
        { method: 'PATCH', body }), '42501', [403]);
      check(true, `Direct ${table} settings edits denied through REST`);
    }

    const sale = {
      id: randomUUID(), business_id: a.id, branch_id: a.branch, device_id: randomUUID(),
      occurred_at: new Date().toISOString(), cash_cents: product.cents,
      items: [{ product_id: productId, name: product.name, sku: product.sku, quantity: 1, unit_cents: product.cents }],
      receipt_details: receiptBranding(settings, a.branch),
    };
    report.fixtures.sales.push(sale.id);
    await record(report);
    const saleReplies = await concurrentSaleUploads(staff, sale);
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
    const details = settings.business;
    check(await ownerA.rpc('pos_update_business', {
      business: a.id, expected_version: details.settings_version, business_name: `${details.name} later`,
      business_address: details.address, phone_number: details.contact_phone,
      email_address: details.contact_email, footer: 'Acceptance footer B',
    }) === 3, 'Later business rename and footer update succeed');
    check(await ownerA.rpc('pos_update_branch', {
      business: a.id, branch: a.branch, expected_version: 2,
      branch_name: 'Acceptance later branch name', branch_address: 'Acceptance later branch address',
    }) === 3, 'Later branch rename succeeds');
    const savedRows = await rowsFor(ownerA, 'pos_cash_sales', a.id, 'id,payload');
    const recordedBranding = savedRows.find(row => row.id === sale.id)?.payload?.receipt_details;
    check(recordedBranding && Object.entries(sale.receipt_details).every(([key, value]) =>
      recordedBranding[key] === value), 'Saved receipt preserves every branding field after settings edits');
    check(await staff.rpc('pos_sync_cash_sale', { sale }) === sale.id && await quantity() === 9,
      'Original branded receipt retry remains idempotent after settings edits');
    await denied(staff, 'pos_sync_cash_sale', { sale: {
      ...sale, receipt_details: { ...sale.receipt_details, footer: 'Changed historical footer' },
    } }, 'Existing receipt rejects changed branding', '22023', [400]);
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
    const laterSettings = await ownerA.rpc('pos_business_settings', { business: a.id });
    const laterSale = { ...sale, id: randomUUID(), receipt_details: receiptBranding(laterSettings, a.branch) };
    report.fixtures.sales.push(laterSale.id);
    await record(report);
    check(await staff.rpc('pos_sync_cash_sale', { sale: laterSale }) === laterSale.id &&
      laterSale.receipt_details.footer === 'Acceptance footer B' && await quantity() === 7,
    'New receipt uses refreshed branding and deducts stock once');
    const brandedRows = await rowsFor(ownerA, 'pos_cash_sales', a.id, 'id,payload');
    check([sale, pendingSale, laterSale].every(expected => {
      const branding = brandedRows.find(row => row.id === expected.id)?.payload?.receipt_details;
      return branding && Object.entries(expected.receipt_details).every(([key, value]) => branding[key] === value);
    }), 'Restored and newer receipts retain their own recorded branding on the server');

    await ownerA.rpc('pos_change_staff_access', { business: a.id, member: users.staff.id, new_role: null });
    check(onlyIds(await rowsFor(staff, 'pos_items', a.id), []), 'Removed membership loses catalog access');
    await denied(staff, 'pos_sync_cash_sale', { sale: pendingSale }, 'Removed member cannot upload receipts');
    check(onlyIds(await rowsFor(ownerA, 'pos_cash_sales', a.id), [sale.id, pendingSale.id, laterSale.id]),
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
  try {
    const report = await runAcceptance(raw, {
      writeFixtures: true, log: console.log,
      record: async result => {
        const target = reportPath ?? resolve('config', `acceptance-${result.runId}.local.json`);
        await saveReport(target, result);
        reportPath = target;
      },
    });
    console.log(`Hosted acceptance passed: ${report.checks.length} checks. Fixtures retained.`);
  } finally {
    if (reportPath) console.log(`Acceptance report: ${reportPath}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    console.error(error instanceof AcceptanceError ? error.message : 'Local runner failed; no hosted result is assumed.');
    process.exitCode = 1;
  });
}
