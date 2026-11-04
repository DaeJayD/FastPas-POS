-- Read-only verification after migration 202611040001. All five rows must pass.
with signatures(signature) as (values
  ('public.pos_update_business(uuid,integer,text,text,text,text,text)'),
  ('public.pos_update_branch(uuid,uuid,integer,text,text)'),
  ('public.pos_save_catalog_label(uuid,uuid,uuid,text,integer,text,boolean)'),
  ('public.pos_save_catalog_item(uuid,uuid,jsonb)'),
  ('public.pos_post_stock(uuid,uuid,jsonb)')
)
select signature as function_name,
  coalesce(p.prosecdef and p.proconfig @> array['search_path=""']
    and position('PT409' in pg_get_functiondef(p.oid))>0
    and position('40001' in pg_get_functiondef(p.oid))=0
    and has_function_privilege('authenticated',p.oid,'EXECUTE')
    and not has_function_privilege('anon',p.oid,'EXECUTE'),false) as passed
from signatures s left join pg_proc p on p.oid=to_regprocedure(s.signature)
order by signature;
