// Test-only adapter: real PostgreSQL/RLS, stubbed Auth and HTTP routing.
// It cannot verify hosted Auth, PostgREST configuration, or network concurrency.
import assert from 'node:assert/strict';

const functions = new Set([
  'pos_create_business', 'pos_invite_staff', 'pos_accept_invitation',
  'pos_staff_access', 'pos_change_staff_access', 'pos_set_staff_branches',
  'pos_add_item', 'pos_sync_cash_sale', 'pos_business_settings',
  'pos_update_business', 'pos_create_branch', 'pos_update_branch',
]);
const tables = new Set(['pos_businesses', 'pos_branches', 'pos_memberships',
  'pos_items', 'pos_item_stock', 'pos_cash_sales']);
const identifier = value => {
  assert.match(value, /^[a-z_]+$/);
  return value;
};
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });

export function embeddedHostedTransport(db, users) {
  const tokens = new Map();
  let queue = Promise.resolve();
  let closedSessions = 0;
  const fetchImpl = async (url, options) => {
    const actor = tokens.get(options.headers.Authorization);
    if (url.pathname === '/auth/v1/token') {
      const credentials = JSON.parse(options.body);
      const user = users.find(row => row.email === credentials.email);
      assert.ok(user, 'Only embedded fixture accounts may sign in');
      const token = `embedded-${user.id}`;
      tokens.set(`Bearer ${token}`, user);
      return json({ access_token: token });
    }
    if (url.pathname === '/auth/v1/user') {
      assert.ok(actor);
      return json({ ...actor, role: 'authenticated', email_confirmed_at: '2026-01-01T00:00:00Z' });
    }
    if (url.pathname === '/auth/v1/logout') {
      assert.equal(url.search, '?scope=local');
      tokens.delete(options.headers.Authorization);
      closedSessions++;
      return new Response(null, { status: 204 });
    }
    if (options.headers['Accept-Profile'] === 'fastpas_private') return json({ code: 'PGRST106' }, 406);
    // A single PGlite connection cannot switch request roles concurrently.
    // Keep identity selection and the query together, including failed queries.
    const request = queue.then(async () => {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub', $1, false)", [actor?.id ?? '']);
      await db.exec(`set role ${actor ? 'authenticated' : 'anon'}`);
      try {
        const rpc = url.pathname.startsWith('/rest/v1/rpc/') ? url.pathname.split('/').at(-1) : null;
        if (rpc) {
          assert.ok(functions.has(rpc));
          const args = JSON.parse(options.body);
          const keys = Object.keys(args);
          const parameters = keys.map(key => {
            const value = args[key];
            if (Array.isArray(value)) {
              value.forEach(id => assert.match(id, /^[0-9a-f-]+$/));
              return `{${value.join(',')}}`;
            }
            return value !== null && typeof value === 'object' ? JSON.stringify(value) : value;
          });
          const sql = `select public.${rpc}(${keys.map((key, i) => `${identifier(key)} => $${i + 1}`).join(',')}) as result`;
          return json((await db.query(sql, parameters)).rows[0].result);
        }
        const table = url.pathname.split('/').at(-1);
        assert.ok(tables.has(table));
        const values = [];
        const filters = [];
        for (const [key, filter] of url.searchParams) {
          if (key === 'select') continue;
          const field = identifier(key);
          if (filter.startsWith('eq.')) {
            values.push(filter.slice(3));
            filters.push(`${field}=$${values.length}`);
          } else {
            assert.match(filter, /^in\.\([0-9a-f,-]+\)$/);
            const ids = filter.slice(4, -1).split(',');
            const placeholders = ids.map(id => { values.push(id); return `$${values.length}`; });
            filters.push(`${field} in (${placeholders.join(',')})`);
          }
        }
        const where = filters.length ? ` where ${filters.join(' and ')}` : '';
        if (options.method === 'PATCH') {
          const body = JSON.parse(options.body);
          const assignments = Object.entries(body).map(([key, value]) => {
            values.push(value);
            return `${identifier(key)}=$${values.length}`;
          });
          await db.query(`update public.${table} set ${assignments.join(',')}${where}`, values);
          return new Response(null, { status: 204 });
        }
        assert.equal(options.method, 'GET');
        const columns = url.searchParams.get('select').split(',').map(identifier).join(',');
        return json((await db.query(`select ${columns} from public.${table}${where}`, values)).rows);
      } catch (error) {
        if (!error.code || !/^[0-9A-Z]{5}$/.test(error.code)) throw error;
        const status = error.code === '42501' ? (actor ? 403 : 401) :
          ['23503', '23505'].includes(error.code) ? 409 : error.code.startsWith('40') ? 500 : 400;
        return json({ code: error.code }, status);
      }
    });
    queue = request.catch(() => {});
    return request;
  };
  return { fetchImpl, closedSessions: () => closedSessions };
}
