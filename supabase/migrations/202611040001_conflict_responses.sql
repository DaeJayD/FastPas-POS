-- Application revision conflicts must not be retried as transaction failures.
-- PostgREST 14 can retry custom 40001 exceptions indefinitely. PT409 maps to
-- HTTP 409 and leaves real database serialization failures to the platform.
begin;
do $$
declare signature text; definition text; corrected text;
begin
  foreach signature in array array[
    'public.pos_update_business(uuid,integer,text,text,text,text,text)',
    'public.pos_update_branch(uuid,uuid,integer,text,text)',
    'public.pos_save_catalog_label(uuid,uuid,uuid,text,integer,text,boolean)',
    'public.pos_save_catalog_item(uuid,uuid,jsonb)',
    'public.pos_post_stock(uuid,uuid,jsonb)'
  ] loop
    if to_regprocedure(signature) is null then
      raise exception 'Required function missing: %',signature;
    end if;
    definition:=pg_get_functiondef(to_regprocedure(signature));
    corrected:=regexp_replace(definition,$pattern$errcode\s*=\s*'40001'$pattern$,
      $replacement$errcode = 'PT409'$replacement$,'g');
    if corrected=definition then
      raise exception 'Expected revision conflict not found: %',signature;
    end if;
    -- pg_get_functiondef preserves signatures, security settings and grants
    -- through CREATE OR REPLACE. No business records are changed here.
    execute corrected;
  end loop;
end $$;
notify pgrst,'reload schema';
commit;
