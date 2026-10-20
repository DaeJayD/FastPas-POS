// Disposable embedded PostgreSQL tests. Pass an installed PGlite module path.
// Auth stubs emulate identity only; local Supabase acceptance is a separate gate.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const owner = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
const staff = '10000000-0000-4000-8000-000000000003';
const pending = '10000000-0000-4000-8000-000000000004';
const business = '20000000-0000-4000-8000-000000000001';
const business2 = '20000000-0000-4000-8000-000000000002';
let checks = 0;
const equal = (a, b) => { assert.equal(a, b); checks++; };
async function scalar(sql, args = []) { return Object.values((await db.query(sql, args)).rows[0])[0]; }
async function identity(id, role = 'authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
  await db.exec(`set role ${role}`);
}
async function denied(sql, args, code) {
  await assert.rejects(db.query(sql, args), error => error.code === code);
  checks++;
}
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
  `);
  for (const [id, email, verified] of [
    [owner, 'owner@example.test', true], [other, 'other@example.test', true],
    [staff, 'staff@example.test', true], [pending, 'pending@example.test', false],
  ]) await db.query('insert into auth.users values ($1, $2, $3)', [id, email, verified ? new Date() : null]);
  await db.exec(await readFile(new URL('../migrations/202610210001_business_workspaces.sql', import.meta.url), 'utf8'));
  const create = 'select public.pos_create_business($1, $2, $3)';
  await identity(owner, 'anon');
  await denied(create, [business, 'A', 'Main'], '42501');
  await identity(pending);
  await denied(create, [business, 'A', 'Main'], '42501');
  await identity(owner);
  equal(await scalar(create, [business, 'Store A', 'Main']), business);
  equal(await scalar(create, [business, 'Store A retry', 'Main retry']), business);
  equal(await scalar('select count(*)::int from public.pos_branches'), 1);
  equal(await scalar('select role from public.pos_memberships'), 'owner');
  const branch = await scalar('select id from public.pos_branches');
  await denied('insert into public.pos_memberships values ($1, $2, $3)', [business, other, 'owner'], '42501');
  await identity(other);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 0);
  equal(await scalar('select count(*)::int from public.pos_branches'), 0);
  await denied(create, [business, 'Stolen', 'Main'], '42501');
  await scalar(create, [business2, 'Store B', 'Other branch']);
  await identity(owner);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 1);
  const invite = 'select public.pos_invite_staff($1, $2, $3, $4)';
  await denied(invite, [business2, branch, 'staff@example.test', 'cashier'], '42501');
  await denied(invite, [business, branch, 'staff@example.test', 'owner'], '22023');
  await denied(invite, [business, '30000000-0000-4000-8000-000000000001', 'staff@example.test', 'cashier'], '23503');
  const code = await scalar(invite, [business, branch, 'STAFF@example.test', 'cashier']);
  await identity(other);
  await denied('select public.pos_accept_invitation($1)', [code], '42501');
  await identity(staff);
  equal(await scalar('select public.pos_accept_invitation($1)', [code]), business);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 1);
  equal(await scalar('select count(*)::int from public.pos_branches'), 1);
  equal(await scalar('select role from public.pos_memberships'), 'cashier');
  await denied('select public.pos_accept_invitation($1)', [code], '42501');
  await denied(invite, [business, branch, 'other@example.test', 'manager'], '42501');
  await denied("update public.pos_memberships set role = 'owner'", [], '42501');
  await db.exec('reset role');
  await db.query('insert into public.pos_branches(business_id, name) values ($1, $2)', [business, 'Restricted']);
  await identity(staff);
  equal(await scalar('select count(*)::int from public.pos_branches'), 1);
  await identity(owner);
  const secondBranch = await scalar('select id from public.pos_branches where name = $1', ['Restricted']);
  await identity(other);
  const otherBranch = await scalar('select id from public.pos_branches');
  await identity(owner);
  await denied(invite, [business, otherBranch, 'staff@example.test', 'cashier'], '23503');
  const expired = await scalar(invite, [business, secondBranch, 'staff@example.test', 'cashier']);
  const differentRole = await scalar(invite, [business, secondBranch, 'staff@example.test', 'manager']);
  await db.exec('reset role');
  await db.query("update fastpas_private.invitations set expires_at = now() - interval '1 day' where code = $1", [expired]);
  await identity(staff);
  await denied('select public.pos_accept_invitation($1)', [expired], '42501');
  await denied('select public.pos_accept_invitation($1)', [differentRole], '22023');
  equal(await scalar('select role from public.pos_memberships'), 'cashier');
  await identity(owner);
  const thirdBusiness = '20000000-0000-4000-8000-000000000003';
  await scalar(create, [thirdBusiness, 'Second owned business', 'Main']);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 2);
  await identity(other);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 1);
  await db.exec('reset role');
  await db.exec(await readFile(new URL('../migrations/202610210002_hybrid_cash_sales.sql', import.meta.url), 'utf8'));
  await identity(owner);
  const addItem = 'select public.pos_add_item($1, $2, $3, $4, $5, $6)';
  const product = await scalar(addItem, [business, branch, 'Coffee', 'COF', 100, 5]);
  await denied(addItem, [business, otherBranch, 'Wrong', 'WRONG', 100, 1], '23503');
  equal(await scalar('select count(*)::int from public.pos_items'), 1);
  const sync = 'select public.pos_sync_cash_sale($1::jsonb)';
  const sale = {id: '40000000-0000-4000-8000-000000000001', business_id: business,
    branch_id: branch, device_id: '50000000-0000-4000-8000-000000000001',
    occurred_at: '2026-10-21T01:00:00Z', cash_cents: 500,
    items: [{product_id: product, name: 'Coffee', sku: 'COF', quantity: 2, unit_cents: 100}]};
  await identity(staff);
  await denied(addItem, [business, branch, 'Other', 'OTHER', 100, 1], '42501');
  equal(await scalar(sync, [JSON.stringify(sale)]), sale.id);
  equal(await scalar(sync, [JSON.stringify(sale)]), sale.id);
  equal(await scalar('select quantity::int from public.pos_item_stock'), 3);
  equal(await scalar('select count(*)::int from public.pos_cash_sales'), 1);
  await denied(sync, [JSON.stringify({...sale, cash_cents: 600})], '22023');
  const next = {...sale, id: '40000000-0000-4000-8000-000000000002'};
  await denied(sync, [JSON.stringify({...next, cash_cents: 0})], '22023');
  equal(await scalar('select quantity::int from public.pos_item_stock'), 3);
  await denied(sync, [JSON.stringify({...next, items: [{...sale.items[0], unit_cents: 1}]})], '22023');
  await denied(sync, [JSON.stringify({...next, items: [sale.items[0], sale.items[0]]})], '22023');
  equal(await scalar('select count(*)::int from public.pos_cash_sales'), 1);
  await identity(other);
  equal(await scalar('select count(*)::int from public.pos_cash_sales'), 0);
  equal(await scalar('select count(*)::int from public.pos_items'), 0);
  await denied(sync, [JSON.stringify(next)], '42501');
  await identity(staff);
  const shortage = {...next, cash_cents: 1000, items: [{...sale.items[0], quantity: 10}]};
  await scalar(sync, [JSON.stringify(shortage)]);
  equal(await scalar('select quantity::int from public.pos_item_stock'), -7);
  await db.exec('reset role');
  await db.exec(await readFile(new URL('../migrations/202610210003_staff_access.sql', import.meta.url), 'utf8'));
  const access = 'select public.pos_staff_access($1)';
  const change = 'select public.pos_change_staff_access($1, $2, $3)';
  await identity(staff);
  await denied(access, [business], '42501');
  await denied(change, [business, staff, 'owner'], '42501');
  await identity(other);
  await denied(access, [business], '42501');
  await denied(change, [business, staff, 'employee'], '42501');
  await identity(owner);
  equal((await scalar(access, [business])).members.length, 2);
  await denied(change, [business, owner, null], '22023');
  await denied(change, [business, staff, 'owner'], '22023');
  await scalar(change, [business, staff, 'employee']);
  await identity(staff);
  await denied(sync, [JSON.stringify({...next, id: '40000000-0000-4000-8000-000000000003'})], '42501');
  await identity(owner);
  const cancelled = await scalar(invite, [business, branch, 'other@example.test', 'cashier']);
  await identity(other);
  await denied('select public.pos_cancel_invitation($1)', [cancelled], '42501');
  await identity(owner);
  await scalar('select public.pos_cancel_invitation($1)', [cancelled]);
  await identity(other);
  await denied('select public.pos_accept_invitation($1)', [cancelled], '42501');
  await identity(owner);
  await scalar(change, [business, staff, null]);
  await identity(staff);
  equal(await scalar('select count(*)::int from public.pos_businesses'), 0);
  await denied(sync, [JSON.stringify(sale)], '42501');
  await identity(owner);
  equal(await scalar('select count(*)::int from public.pos_cash_sales'), 2);
  await denied('select * from fastpas_private.access_audit', [], '42501');
  await db.exec('reset role');
  equal(await scalar('select count(*)::int from fastpas_private.access_audit'), 3);
  equal(await scalar("select count(*)::int from fastpas_private.invitations where email = 'staff@example.test' and accepted_at is null"), 0);
  console.log(`${checks} workspace, hybrid cash-sale, and staff access checks passed (embedded PostgreSQL; Auth stubbed).`);
} finally { await db.close(); }
