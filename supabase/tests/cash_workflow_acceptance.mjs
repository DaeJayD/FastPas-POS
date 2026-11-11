import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import {
  ApiError, ProjectApi, concurrentSaleUploads, expectRejection, validateConfig,
} from './hosted_acceptance.mjs';

// Explicit development opt-in. Every write belongs to a newly recorded fixture.
const raw = JSON.parse(await readFile(resolve(process.argv[2] ?? 'config/acceptance.local.json'), 'utf8'));
const config = validateConfig(raw, process.argv.includes('--write-fixtures'));
const clients = Object.fromEntries(['ownerA', 'ownerB', 'staff'].map(name => [name, new ProjectApi(config)]));
const report = {
  runId: randomUUID(), projectRef: raw.expectedProjectRef, startedAt: new Date().toISOString(),
  status: 'running', checks: [], businessId: randomUUID(), requests: [], sales: [],
};
const reportPath = resolve(`config/cash-workflow-${report.runId}.local.json`);
const record = () => writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
const check = (condition, label) => {
  assert.ok(condition, label);
  report.checks.push(label);
};
const attempt = async (kind) => {
  const id = randomUUID();
  report.requests.push({ kind, id });
  await record();
  return id;
};
const denied = async (api, name, args, label, code = '42501', statuses = [401, 403]) => {
  await expectRejection(() => api.rpc(name, args), code, statuses);
  check(true, label);
};
const simultaneous = async (api, name, args) => {
  const results = await Promise.allSettled([api.rpc(name, args), api.rpc(name, args)]);
  const failure = results.find(result => result.status === 'rejected');
  if (failure) throw failure.reason;
  return results.map(result => result.value);
};
let stage = 'verified sign-in';
let failed = false;
try {
  await record();
  const users = {};
  for (const [name, client] of Object.entries(clients)) {
    users[name] = await client.signIn(config.accounts[name]);
  }
  check(new Set(Object.values(users).map(user => user.id)).size === 3, 'Three verified identities');
  const { ownerA: owner, ownerB: unrelated, staff } = clients;
  const business = report.businessId;
  stage = 'dedicated fixture';
  await owner.rpc('pos_create_business', {
    request_id: business, business_name: `Cash workflow acceptance ${report.runId}`, branch_name: 'Main',
  });
  const [branchRow] = await owner.rows('pos_branches', { select: 'id', business_id: `eq.${business}` });
  const branch = branchRow.id;
  report.branchId = branch;
  await record();
  const product = await owner.rpc('pos_add_item', {
    business, branch, product_name: 'Acceptance water', product_sku: 'CASH',
    unit_cents: 2500, opening_quantity: 10,
  });
  const code = await owner.rpc('pos_invite_staff', {
    business, branch, invite_email: config.accounts.staff.email, invite_role: 'manager',
  });
  await staff.rpc('pos_accept_invitation', { invite_code: code });
  const scope = { p_business: business, p_branch: branch, p_device: randomUUID() };
  const quantity = async () => (await owner.rows('pos_item_stock', {
    select: 'quantity', business_id: `eq.${business}`, branch_id: `eq.${branch}`, product_id: `eq.${product}`,
  }))[0].quantity;
  stage = 'concurrent shift opening';
  const opening = { ...scope, p_request: await attempt('opening'), p_opening: 10000 };
  const opened = await simultaneous(owner, 'pos_open_cash_shift', opening);
  check(opened.every(row => row.id === opening.p_request && row.expected_cents === 10000),
    'Concurrent opening retries resolve the same drawer');
  const drawer = { ...scope, p_shift: opening.p_request };
  const sale = {
    id: randomUUID(), business_id: business, branch_id: branch, device_id: scope.p_device,
    cash_shift_id: drawer.p_shift, occurred_at: new Date().toISOString(), cash_cents: 10000,
    items: [{ product_id: product, name: 'Acceptance water', sku: 'CASH', quantity: 3, unit_cents: 2500 }],
  };
  report.sales.push(sale.id);
  await record();
  check((await concurrentSaleUploads(owner, sale)).every(id => id === sale.id),
    'Concurrent sale retries keep the original receipt');
  check(await quantity() === 7, 'Sale deducts three stock units once');

  stage = 'competing partial returns';
  const refund = async () => ({
    ...drawer, p_sale: sale.id, p_request: await attempt('partial return'), p_reason: 'Concurrent return check',
    p_items: [{ product_id: product, quantity: 2, restock: true }],
  });
  const competing = [await refund(), await refund()];
  const results = await Promise.allSettled(competing.map(params => owner.rpc('pos_record_shift_return', params)));
  const winner = results.findIndex(result => result.status === 'fulfilled');
  check(winner >= 0 && results.filter(result => result.status === 'fulfilled').length === 1,
    'Only one competing two-unit return can commit');
  const loser = results[1 - winner];
  check(loser.status === 'rejected' && loser.reason instanceof ApiError &&
    loser.reason.code === 'PT409' && loser.reason.status === 409, 'Excess concurrent return is an HTTP conflict');
  const winningReturn = competing[winner];
  const repeated = await simultaneous(owner, 'pos_record_shift_return', winningReturn);
  check(repeated.every(row => row.id === winningReturn.p_request && row.total_cents === 5000),
    'Concurrent refund retries retain the original amount and ID');
  check(await quantity() === 9, 'Restocking happens once after refund retries');
  const returnScope = { p_business: business, p_branch: branch, p_sale: sale.id };
  check((await owner.rpc('pos_cash_return_options', returnScope))[0].remaining_quantity === 1,
    'Failed competing return leaves the last unit returnable');
  await owner.rpc('pos_record_shift_return', {
    ...drawer, p_sale: sale.id, p_request: await attempt('non-restocked return'), p_reason: 'Disposed unit',
    p_items: [{ product_id: product, quantity: 1, restock: false }],
  });
  check(await quantity() === 9, 'A refund without restocking preserves stock');

  stage = 'cash movements and drawer ownership';
  const deposit = { ...drawer, p_request: await attempt('deposit'), p_cents: 1000, p_reason: 'Extra float' };
  await simultaneous(owner, 'pos_post_cash_movement', deposit);
  await owner.rpc('pos_post_cash_movement', {
    ...drawer, p_request: await attempt('withdrawal'), p_cents: -500, p_reason: 'Cash pickup',
  });
  await denied(staff, 'pos_post_cash_movement', deposit, 'Manager cannot post into another cashier drawer');
  await denied(unrelated, 'pos_cash_return_options', returnScope, 'Unrelated owner cannot read return options');
  stage = 'concurrent close and report reconciliation';
  const close = { ...drawer, p_request: await attempt('closing'), p_counted: 10450 };
  const closings = await simultaneous(owner, 'pos_close_cash_shift', close);
  check(closings.every(row => row.expected_cents === 10500 && row.counted_cents === 10450 &&
    row.variance_cents === -50 && row.sales_cents === 7500 && row.refunds_cents === 7500 &&
    row.cash_in_cents === 1000 && row.cash_out_cents === 500),
  'Concurrent closing freezes the exact ledger and variance');
  await owner.rpc('pos_post_cash_movement', deposit);
  await owner.rpc('pos_record_shift_return', winningReturn);
  await owner.rpc('pos_sync_cash_sale', { sale });
  check((await owner.rpc('pos_cash_shift_status', scope)).expected_cents === 10500,
    'Retries after closing preserve the frozen drawer');
  const late = { ...sale, id: randomUUID() };
  report.sales.push(late.id);
  await record();
  await denied(owner, 'pos_sync_cash_sale', { sale: late }, 'A new late sale cannot enter a closed drawer', 'PT409', [409]);
  check(await quantity() === 9, 'Rejected late sale leaves stock intact');
  const day = sale.occurred_at.substring(0, 10);
  const range = { p_business: business, p_branch: branch, p_from: day, p_through: day, p_timezone: 'UTC' };
  const daily = (await owner.rpc('pos_branch_cash_report', range)).days[0];
  check(daily.sale_count === 1 && daily.gross_cents === 7500 && daily.refund_count === 2 &&
    daily.refund_cents === 7500 && daily.shift_count === 1 &&
    daily.expected_cents === 10500 && daily.counted_cents === 10450,
  'Hosted report reconciles sales, refunds and one drawer close');
  check(JSON.stringify((await staff.rpc('pos_branch_cash_report', range)).days[0]) === JSON.stringify(daily),
    'Assigned manager reads the same reconciled report');
  await denied(unrelated, 'pos_branch_cash_report', range, 'Report rejects another business owner');
  report.status = 'passed';
} catch (error) {
  failed = true;
  report.status = 'failed';
  report.failedStage = stage;
  report.errorType = error.constructor.name;
  if (error instanceof ApiError) report.errorCode = error.code;
  if (error instanceof assert.AssertionError) report.failedCheck = error.message;
} finally {
  const closed = await Promise.allSettled(Object.values(clients).map(client => client.signOut()));
  report.sessionsClosed = closed.every(result => result.status === 'fulfilled');
  if (!report.sessionsClosed) { failed = true; report.status = 'failed'; }
  report.finishedAt = new Date().toISOString();
  await record();
}
console.log(JSON.stringify({ status: report.status, checks: report.checks.length, sessionsClosed: report.sessionsClosed }));
process.exitCode = failed ? 1 : 0;
