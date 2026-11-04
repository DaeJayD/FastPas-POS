-- Read-only post-deployment checks. Every row must report passed = true.
-- Schema checks do not replace signed-in account or physical-device acceptance.
with public_functions(signature) as (values
  ('public.pos_sync_cash_sale(jsonb)'),
  ('public.pos_catalog_labels(uuid)'),
  ('public.pos_save_catalog_label(uuid,uuid,uuid,text,integer,text,boolean)'),
  ('public.pos_catalog_items(uuid,uuid,integer,integer,text,boolean)'),
  ('public.pos_save_catalog_item(uuid,uuid,jsonb)'),
  ('public.pos_post_stock(uuid,uuid,jsonb)'),
  ('public.pos_stock_history(uuid,uuid,uuid,integer,integer)')
), private_functions(signature) as (values
  ('fastpas_private.pos_sync_cash_sale(jsonb)'),
  ('fastpas_private.inventory_retry(uuid,uuid,jsonb)'),
  ('fastpas_private.inventory_done(uuid,uuid,jsonb,jsonb)'),
  ('fastpas_private.stock_version()'),
  ('fastpas_private.stock_movement()')
), managed_tables(name) as (values
  ('pos_brands'),('pos_categories'),('pos_product_families'),('pos_stock_movements')
), expected_columns(relation,name) as (values
  ('pos_items','base_name'),('pos_items','brand_id'),('pos_items','category_id'),
  ('pos_items','family_id'),('pos_items','variant_label'),('pos_items','version'),
  ('pos_item_stock','stock_version'),('pos_item_stock','low_stock_threshold')
), checks as (
  select 'public RPCs are present and authenticated only' as check_name,
    coalesce(bool_and(to_regprocedure(signature) is not null
      and has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE')
      and not has_function_privilege('anon',to_regprocedure(signature),'EXECUTE')),false) as passed
    from public_functions
  union all
  select 'private helpers cannot be called by clients',
    coalesce(bool_and(to_regprocedure(signature) is not null
      and not has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE')
      and not has_function_privilege('anon',to_regprocedure(signature),'EXECUTE')),false)
    from private_functions
  union all
  select 'RPCs and helpers use security definer with an empty search path',
    count(*)=12 and coalesce(bool_and(p.prosecdef and p.proconfig @> array['search_path=""']),false)
    from (select signature from public_functions union all select signature from private_functions) f
    join pg_proc p on p.oid=to_regprocedure(f.signature)
  union all
  select 'classification and movement tables enforce RLS',
    count(*)=4 and coalesce(bool_and(c.relrowsecurity),false)
    from managed_tables t join pg_class c on c.oid=to_regclass('public.'||t.name)
  union all
  select 'managed tables allow authenticated reads without direct writes',
    coalesce(bool_and(to_regclass('public.'||name) is not null
      and has_table_privilege('authenticated',to_regclass('public.'||name),'SELECT')
      and not has_table_privilege('anon',to_regclass('public.'||name),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      and not has_table_privilege('authenticated',to_regclass('public.'||name),'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')),false)
    from managed_tables
  union all
  select 'catalog and stock version columns are installed',count(*)=8
    from expected_columns e join information_schema.columns c
      on c.table_schema='public' and c.table_name=e.relation and c.column_name=e.name
  union all
  select 'stock version and movement triggers are enabled',
    count(*)=2 and coalesce(bool_and(tgenabled<>'D'),false)
    from pg_trigger where tgrelid=to_regclass('public.pos_item_stock')
      and tgname in ('stock_version','stock_movement') and not tgisinternal
  union all
  select 'sale movements can commit with the receipt in one transaction',exists(
    select 1 from pg_constraint where conrelid=to_regclass('public.pos_stock_movements')
      and confrelid=to_regclass('public.pos_cash_sales') and contype='f' and condeferrable and condeferred)
  union all
  select 'classification references are scoped to the business',count(*)=3
    from pg_constraint where conrelid=to_regclass('public.pos_items') and contype='f'
      and array_length(conkey,1)=2 and confrelid in (
        to_regclass('public.pos_brands'),to_regclass('public.pos_categories'),to_regclass('public.pos_product_families'))
)
select check_name,passed from checks order by check_name;
