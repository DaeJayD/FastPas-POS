-- Read-only metadata export for migration planning. No customer rows are read.
-- Run in the existing project's SQL Editor and save the schema_inventory cell.
select jsonb_build_object(
  'columns', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
    from (select table_schema, table_name, column_name, data_type, udt_name,
      is_nullable, column_default from information_schema.columns
      where table_schema = 'public' order by table_name, ordinal_position) c),
  'constraints', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
    from (select r.relname as table_name, c.conname as name,
      pg_get_constraintdef(c.oid) as definition
      from pg_constraint c join pg_class r on r.oid = c.conrelid
      join pg_namespace n on n.oid = r.relnamespace
      where n.nspname = 'public') c),
  'indexes', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
    from pg_indexes i where schemaname = 'public'),
  'policies', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
    from pg_policies p where schemaname in ('public', 'storage')),
  'row_security', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (select c.relname as table_name, c.relrowsecurity as enabled,
      c.relforcerowsecurity as forced
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r') r),
  'views', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb)
    from pg_views v where schemaname = 'public'),
  'grants', (select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb)
    from information_schema.table_privileges g where table_schema = 'public'),
  'triggers', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
    from (select r.relname as table_name, pg_get_triggerdef(t.oid) as definition
      from pg_trigger t join pg_class r on r.oid = t.tgrelid
      join pg_namespace n on n.oid = r.relnamespace
      where n.nspname = 'public' and not t.tgisinternal) t)
) as schema_inventory;
