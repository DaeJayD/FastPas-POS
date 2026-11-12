import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

// All restoration writes go to this isolated in-memory PostgreSQL instance.
const backup = JSON.parse(await readFile(resolve(process.argv[2] ?? 'config/phase10-backup.local.json'), 'utf8'));
assert.equal(backup.format_version, 1, 'Unsupported application backup format');
assert.ok(Array.isArray(backup.tables) && Array.isArray(backup.auth_user_ids), 'Incomplete backup');
const db = new PGlite();
const report = { status: 'running', restored: [], checks: [] };
const check = (condition, label) => {
  assert.ok(condition, label);
  report.checks.push(label);
};
const identifier = (name) => {
  assert.match(name, /^(public|fastpas_private)\.[a-z_]+$/);
  return name.split('.').map(part => '"' + part + '"').join('.');
};
const sortedObject = (value) => {
  if (Array.isArray(value)) return value.map(sortedObject);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortedObject(value[key])]));
  }
  return value;
};
const digest = (rows) => createHash('sha256')
  .update(JSON.stringify(rows.map(row => JSON.stringify(sortedObject(row))).sort())).digest('hex');
let failed = false;
try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated;
    grant execute on function auth.uid() to anon,authenticated;`);
  const migrations = (await readdir(new URL('../migrations/', import.meta.url)))
    .filter(file => file.endsWith('.sql')).sort();
  for (const file of migrations) {
    const text = (await readFile(new URL('../migrations/' + file, import.meta.url), 'utf8')).replace(/\r/g, '');
    const version = file.split('_')[0], name = file.slice(version.length + 1, -4);
    const saved = backup.migrations.find(row => row.version === version && row.name === name);
    check(saved?.statements?.length === 1 && saved.statements[0].replace(/\r/g, '').trim() === text.trim(),
      'Backup history matches ' + file);
    await db.exec(text);
  }
  check(backup.migrations.length === migrations.length, 'Migration history has the complete local chain');
  const schemaQuery = await readFile(new URL('../schema_fingerprint.sql', import.meta.url), 'utf8');
  const expected = (await db.query(schemaQuery)).rows[0].schema;
  for (const section of ['tables', 'functions']) {
    check(backup.schema[section].length === expected[section].length, 'Schema ' + section + ' count matches');
    for (const row of expected[section]) {
      const match = backup.schema[section].find(item => item.name === row.name &&
        (section !== 'functions' || item.args === row.args));
      assert.deepEqual(match, row, 'Schema differs for ' + row.name);
      report.checks.push('Schema matches ' + row.name);
    }
  }
  const names = new Set(expected.tables.map(table => table.name));
  check(backup.tables.length === names.size &&
    new Set(backup.tables.map(table => table.name)).size === names.size &&
    backup.tables.every(table => names.has(table.name)), 'Backup contains every application table once');
  const remaining = [...backup.tables];
  const ordered = [];
  while (remaining.length) {
    const index = remaining.findIndex(table => backup.dependencies
      .filter(edge => edge.table === table.name && names.has(edge.references) && edge.references !== table.name)
      .every(edge => ordered.some(parent => parent.name === edge.references)));
    assert.ok(index >= 0, 'Application foreign keys contain an unsupported dependency cycle');
    ordered.push(remaining.splice(index, 1)[0]);
  }
  await db.exec('begin');
  for (const id of backup.auth_user_ids) {
    assert.match(id, /^[0-9a-f-]{36}$/);
    await db.query('insert into auth.users(id) values($1)', [id]);
  }
  for (const table of ordered) {
    await db.exec('alter table ' + identifier(table.name) + ' disable trigger user');
  }
  for (const table of ordered) {
    await db.query('insert into ' + identifier(table.name) +
      ' select * from jsonb_populate_recordset(null::' + identifier(table.name) + ',$1::jsonb)',
    [JSON.stringify(table.rows)]);
  }
  await db.exec('commit');
  for (const table of ordered) {
    await db.exec('alter table ' + identifier(table.name) + ' enable trigger user');
  }
  for (const table of ordered) {
    const rows = (await db.query('select coalesce(jsonb_agg(to_jsonb(source)),\'[]\'::jsonb) as rows from ' +
      identifier(table.name) + ' source')).rows[0].rows;
    const hash = digest(rows);
    assert.equal(hash, digest(table.rows), 'Restored row digest differs for ' + table.name);
    report.restored.push({ table: table.name, rows: rows.length, sha256: hash });
  }
  const receipts = backup.tables.find(table => table.name === 'public.pos_cash_sales').rows;
  const memberships = backup.tables.find(table => table.name === 'public.pos_memberships').rows;
  const receipt = receipts.find(sale => memberships.some(member =>
    member.business_id === sale.business_id && member.user_id === sale.created_by && member.role === 'owner'));
  check(Boolean(receipt), 'Restored data contains an owner receipt for retry verification');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [receipt.created_by]);
  await db.exec('set role authenticated');
  const retried = (await db.query('select public.pos_sync_cash_sale($1) as id', [JSON.stringify(receipt.payload)])).rows[0].id;
  check(retried === receipt.id, 'A restored receipt retries with its original ID');
  await db.exec('reset role');
  const stock = backup.tables.find(table => table.name === 'public.pos_item_stock');
  const currentStock = (await db.query('select jsonb_agg(to_jsonb(stock)) as rows from public.pos_item_stock stock')).rows[0].rows;
  check(digest(currentStock) === digest(stock.rows), 'Restored retry preserves all stock quantities');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", ['00000000-0000-4000-8000-000000000001']);
  await db.exec('set role authenticated');
  for (const name of names) {
    if (name.startsWith('fastpas_private.')) {
      await assert.rejects(db.query('select count(*) from ' + identifier(name)), error => error.code === '42501');
    } else {
      assert.equal((await db.query('select count(*)::int as count from ' + identifier(name))).rows[0].count, 0,
        'An unrelated account can read restored data in ' + name);
    }
    report.checks.push('Restored isolation protects ' + name);
  }
  report.status = 'passed';
  report.sourceCapturedAt = backup.captured_at;
  report.rowCount = report.restored.reduce((sum, table) => sum + table.rows, 0);
} catch (error) {
  failed = true;
  report.status = 'failed';
  report.error = error.message;
} finally {
  await db.close();
  await writeFile('config/phase10-restore.local.json', JSON.stringify(report, null, 2) + '\n');
}
console.log(JSON.stringify({ status: report.status, tables: report.restored.length,
  rows: report.rowCount, checks: report.checks.length, error: report.error }));
process.exitCode = failed ? 1 : 0;
