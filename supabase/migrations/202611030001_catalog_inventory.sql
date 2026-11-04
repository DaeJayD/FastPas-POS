-- Owner catalog and online inventory. Existing sales and local queues survive.
begin;

do $$ declare relation text; begin
  foreach relation in array array['pos_brands','pos_categories','pos_product_families'] loop
    execute format('create table public.%I (
      id uuid primary key, business_id uuid not null references public.pos_businesses(id),
      name text not null check(length(btrim(name)) between 1 and 120),
      active boolean not null default true, version integer not null default 1 check(version > 0),
      unique(business_id,id))', relation);
    execute format('create unique index %I on public.%I(business_id,lower(btrim(name)))', relation||'_name',relation);
    execute format('alter table public.%I enable row level security',relation);
    execute format('revoke all on public.%I from public,anon,authenticated',relation);
    execute format('grant select on public.%I to authenticated',relation);
    execute format('create policy member_read on public.%I for select to authenticated using(fastpas_private.is_member(business_id))',relation);
  end loop;
end $$;

alter table public.pos_items
  add column base_name text not null default '' check(length(base_name)<=120),
  add column brand_id uuid,
  add column category_id uuid,
  add column family_id uuid,
  add column variant_label text not null default '' check(length(variant_label)<=120),
  add column version integer not null default 1 check(version>0),
  add foreign key(business_id,brand_id) references public.pos_brands(business_id,id),
  add foreign key(business_id,category_id) references public.pos_categories(business_id,id),
  add foreign key(business_id,family_id) references public.pos_product_families(business_id,id),
  add check((family_id is null and variant_label='') or
    (family_id is not null and length(btrim(variant_label)) between 1 and 120));
update public.pos_items set base_name=name;
create unique index pos_variant_identity on public.pos_items(business_id,family_id,lower(btrim(variant_label)))
  where family_id is not null;
alter table public.pos_item_stock
  add column stock_version bigint not null default 1 check(stock_version>0),
  add column low_stock_threshold integer not null default 0 check(low_stock_threshold>=0);

create table fastpas_private.inventory_requests (
  id uuid primary key, business_id uuid not null references public.pos_businesses(id),
  actor_id uuid not null references auth.users(id), payload jsonb not null, result jsonb not null,
  created_at timestamptz not null default now()
);
revoke all on fastpas_private.inventory_requests from public,anon,authenticated;

create table public.pos_stock_movements (
  id uuid primary key default gen_random_uuid(), business_id uuid not null,
  branch_id uuid not null, product_id uuid not null,
  kind text not null check(kind in ('snapshot','opening','sale','receive','count','transfer')),
  quantity_delta bigint not null, before_quantity bigint not null, after_quantity bigint not null,
  product_name text not null, sku text not null, branch_name text not null,
  reason text not null, actor_id uuid not null references auth.users(id),
  request_id uuid, sale_id uuid references public.pos_cash_sales(id) deferrable initially deferred,
  created_at timestamptz not null default now(),
  foreign key(business_id,branch_id) references public.pos_branches(business_id,id),
  foreign key(business_id,product_id) references public.pos_items(business_id,id),
  check(after_quantity-before_quantity=quantity_delta)
);
create index pos_stock_history on public.pos_stock_movements(business_id,branch_id,created_at desc,id);
alter table public.pos_stock_movements enable row level security;
revoke all on public.pos_stock_movements from public,anon,authenticated;
grant select on public.pos_stock_movements to authenticated;
create policy owner_read on public.pos_stock_movements for select to authenticated
  using(fastpas_private.is_owner(business_id));
-- This is a migration-time baseline, not fabricated historical receiving.
insert into public.pos_stock_movements(business_id,branch_id,product_id,kind,quantity_delta,
  before_quantity,after_quantity,product_name,sku,branch_name,reason,actor_id)
select s.business_id,s.branch_id,s.product_id,'snapshot',s.quantity,0,s.quantity,
  i.name,i.sku,b.name,'Stock at inventory migration',w.created_by
from public.pos_item_stock s join public.pos_items i on i.id=s.product_id
join public.pos_branches b on b.id=s.branch_id join public.pos_businesses w on w.id=s.business_id;

create function fastpas_private.inventory_retry(business uuid, request_id uuid, details jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved fastpas_private.inventory_requests%rowtype;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode='42501';
  end if;
  if request_id is null then raise exception 'Request ID required' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(request_id::text,5));
  select * into saved from fastpas_private.inventory_requests r where r.id=request_id;
  if found then
    if saved.business_id<>business or saved.actor_id<>auth.uid() then
      raise exception 'Request unavailable' using errcode='42501';
    end if;
    if saved.payload<>details then raise exception 'Request details changed' using errcode='22023'; end if;
    return saved.result;
  end if;
  return null;
end $$;

create function fastpas_private.inventory_done(business uuid, request_id uuid, details jsonb, result jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  insert into fastpas_private.inventory_requests(id,business_id,actor_id,payload,result)
    values(request_id,business,auth.uid(),details,result);
  return result;
end $$;

create function fastpas_private.stock_version() returns trigger language plpgsql
security definer set search_path='' as $$
begin
  if tg_op='INSERT' then new.stock_version:=1;
  elsif new.quantity is distinct from old.quantity or new.low_stock_threshold is distinct from old.low_stock_threshold then
    new.stock_version:=old.stock_version+1;
  else new.stock_version:=old.stock_version;
  end if;
  return new;
end $$;
create trigger stock_version before insert or update on public.pos_item_stock
  for each row execute function fastpas_private.stock_version();

create function fastpas_private.stock_movement() returns trigger language plpgsql
security definer set search_path='' as $$
declare
  previous bigint:=0; context jsonb:=coalesce(nullif(current_setting('fastpas.stock_context',true),''),'{}')::jsonb;
begin
  if tg_op='UPDATE' then previous:=old.quantity; end if;
  if new.quantity=previous then return null; end if;
  insert into public.pos_stock_movements(business_id,branch_id,product_id,kind,quantity_delta,
    before_quantity,after_quantity,product_name,sku,branch_name,reason,actor_id,request_id,sale_id)
  select new.business_id,new.branch_id,new.product_id,
    coalesce(context->>'kind',case when tg_op='INSERT' then 'opening' else 'sale' end),
    new.quantity-previous,previous,new.quantity,i.name,i.sku,b.name,
    coalesce(context->>'reason',case when tg_op='INSERT' then 'Opening stock' else 'Cash sale' end),
    auth.uid(),(context->>'request_id')::uuid,(context->>'sale_id')::uuid
  from public.pos_items i join public.pos_branches b on b.id=new.branch_id where i.id=new.product_id;
  return null;
end $$;
create trigger stock_movement after insert or update on public.pos_item_stock
  for each row execute function fastpas_private.stock_movement();

-- Retain the established cash validation/idempotency implementation unchanged.
alter function public.pos_sync_cash_sale(jsonb) set schema fastpas_private;
revoke all on function fastpas_private.pos_sync_cash_sale(jsonb) from public,anon,authenticated;
create function public.pos_sync_cash_sale(sale jsonb) returns uuid language plpgsql
security definer set search_path='' as $$
declare result uuid; previous text:=coalesce(current_setting('fastpas.stock_context',true),'');
begin
  perform set_config('fastpas.stock_context',jsonb_build_object('kind','sale','reason','Cash sale','sale_id',sale->>'id')::text,true);
  result:=fastpas_private.pos_sync_cash_sale(sale);
  perform set_config('fastpas.stock_context',previous,true);
  return result;
end $$;

create function public.pos_catalog_labels(business uuid) returns jsonb language plpgsql
security definer set search_path='' as $$
begin
  if not fastpas_private.is_member(business) then raise exception 'Workspace access required' using errcode='42501'; end if;
  return jsonb_build_object('business_id',business,
    'brands',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from public.pos_brands x where x.business_id=business),
    'categories',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from public.pos_categories x where x.business_id=business),
    'families',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from public.pos_product_families x where x.business_id=business));
end $$;

create function public.pos_save_catalog_label(business uuid, request_id uuid, label_id uuid,
  kind text, expected_version integer, label_name text, enabled boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  details jsonb:=jsonb_build_array('label',label_id,kind,expected_version,label_name,enabled);
  saved jsonb; relation text; current_version integer;
begin
  saved:=fastpas_private.inventory_retry(business,request_id,details); if saved is not null then return saved; end if;
  relation:=case kind when 'brand' then 'pos_brands' when 'category' then 'pos_categories' when 'family' then 'pos_product_families' end;
  if relation is null or label_id is null or expected_version is null or expected_version<0
    or enabled is null or label_name is null or length(btrim(label_name)) not between 1 and 120 then
    raise exception 'Invalid catalog label' using errcode='22023';
  end if;
  if expected_version=0 then
    execute format('insert into public.%I(id,business_id,name,active) values($1,$2,$3,$4)',relation)
      using label_id,business,btrim(label_name),enabled;
    current_version:=1;
  else
    execute format('select version from public.%I where id=$1 and business_id=$2 for update',relation)
      into current_version using label_id,business;
    if current_version is null then raise exception 'Label unavailable' using errcode='42501'; end if;
    if current_version<>expected_version then raise exception 'Label changed; refresh' using errcode='40001'; end if;
    execute format('update public.%I set name=$1,active=$2,version=version+1 where id=$3 and business_id=$4',relation)
      using btrim(label_name),enabled,label_id,business;
    current_version:=current_version+1;
  end if;
  insert into fastpas_private.access_audit(business_id,actor_id,target_id,action)
    values(business,auth.uid(),label_id,'catalog_label_updated');
  return fastpas_private.inventory_done(business,request_id,details,
    jsonb_build_object('id',label_id,'business_id',business,'version',current_version));
end $$;

create function public.pos_catalog_items(business uuid, branch uuid, page_offset integer default 0,
  page_size integer default 50, search_text text default '', include_archived boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if not fastpas_private.is_owner(business) then raise exception 'Owner access required' using errcode='42501'; end if;
  if not exists(select 1 from public.pos_branches b where b.id=branch and b.business_id=business) then
    raise exception 'Branch unavailable' using errcode='42501'; end if;
  if page_offset is null or page_offset<0 or page_size is null or page_size not between 1 and 100
    or search_text is null or length(search_text)>120 or include_archived is null then
    raise exception 'Invalid catalog page' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]') from (
    select i.*,coalesce(s.quantity,0) quantity,coalesce(s.stock_version,0) stock_version,
      coalesce(s.low_stock_threshold,0) low_stock_threshold
    from public.pos_items i left join public.pos_item_stock s
      on s.product_id=i.id and s.branch_id=branch and s.business_id=business
    where i.business_id=business and (include_archived or i.active)
      and position(lower(btrim(search_text)) in lower(i.name||' '||i.sku))>0
    order by i.name,i.id offset page_offset limit page_size) x);
end $$;

create function public.pos_save_catalog_item(business uuid, request_id uuid, item jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  details jsonb:=jsonb_build_array('item',item); saved jsonb; existing public.pos_items%rowtype;
  product uuid:=(item->>'id')::uuid; expected integer:=(item->>'version')::integer;
  brand uuid:=(item->>'brand_id')::uuid; category uuid:=(item->>'category_id')::uuid;
  family uuid:=(item->>'family_id')::uuid; variant text:=btrim(coalesce(item->>'variant_label',''));
  base text:=btrim(item->>'name'); display_name text; cents bigint:=(item->>'price_cents')::bigint;
  enabled boolean:=(item->>'active')::boolean; opening bigint:=(item->>'opening_quantity')::bigint;
  branch uuid:=(item->>'branch_id')::uuid; previous text:=coalesce(current_setting('fastpas.stock_context',true),'');
begin
  saved:=fastpas_private.inventory_retry(business,request_id,details); if saved is not null then return saved; end if;
  display_name:=base||case when family is not null then ' · '||variant else '' end;
  if product is null or expected is null or expected<0 or enabled is null or base is null
    or length(base) not between 1 and 120 or length(display_name) not between 1 and 120
    or item->>'sku' is null or length(btrim(item->>'sku')) not between 1 and 80
    or cents is null or cents not between 0 and 1000000000
    or (family is null and variant<>'') or (family is not null and length(variant) not between 1 and 120) then
    raise exception 'Invalid product details' using errcode='22023'; end if;
  select * into existing from public.pos_items i where i.id=product and i.business_id=business for update;
  if expected>0 and not found then raise exception 'Product unavailable' using errcode='42501'; end if;
  if expected>0 and existing.version<>expected then raise exception 'Product changed; refresh' using errcode='40001'; end if;
  -- Keep classification eligibility stable until the product write commits.
  if (brand is not null and not exists(select 1 from public.pos_brands b where b.id=brand and b.business_id=business and (b.active or b.id=existing.brand_id) for share))
    or (category is not null and not exists(select 1 from public.pos_categories c where c.id=category and c.business_id=business and (c.active or c.id=existing.category_id) for share))
    or (family is not null and not exists(select 1 from public.pos_product_families f where f.id=family and f.business_id=business and (f.active or f.id=existing.family_id) for share)) then
    raise exception 'Classification unavailable' using errcode='42501'; end if;
  if expected=0 then
    if opening is null or opening not between 0 and 1000000000 or branch is null
      or not exists(select 1 from public.pos_branches b where b.id=branch and b.business_id=business) then
      raise exception 'Invalid opening stock or branch' using errcode='22023'; end if;
    insert into public.pos_items(id,business_id,name,base_name,sku,price_cents,active,brand_id,category_id,family_id,variant_label)
      values(product,business,display_name,base,btrim(item->>'sku'),cents,enabled,brand,category,family,variant);
    perform set_config('fastpas.stock_context',jsonb_build_object('kind','opening','reason','Opening stock','request_id',request_id)::text,true);
    insert into public.pos_item_stock(business_id,branch_id,product_id,quantity) values(business,branch,product,opening);
    perform set_config('fastpas.stock_context',previous,true);
  else
    update public.pos_items i set name=display_name,base_name=base,sku=btrim(item->>'sku'),price_cents=cents,
      active=enabled,brand_id=brand,category_id=category,family_id=family,variant_label=variant,version=i.version+1
      where i.id=product and i.business_id=business;
  end if;
  insert into fastpas_private.access_audit(business_id,actor_id,target_id,action)
    values(business,auth.uid(),product,'catalog_item_updated');
  return fastpas_private.inventory_done(business,request_id,details,
    jsonb_build_object('id',product,'business_id',business,'version',expected+1));
end $$;

create function public.pos_post_stock(business uuid, request_id uuid, change jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  details jsonb:=jsonb_build_array('stock',change); saved jsonb; kind text:=change->>'kind';
  product uuid:=(change->>'product_id')::uuid; branch uuid:=(change->>'branch_id')::uuid;
  destination uuid:=(change->>'destination_id')::uuid; amount bigint:=(change->>'quantity')::bigint;
  expected bigint:=(change->>'stock_version')::bigint; dest_expected bigint:=(change->>'destination_version')::bigint;
  source public.pos_item_stock%rowtype; target public.pos_item_stock%rowtype; inserted integer;
  reason text:=btrim(change->>'reason'); after_source numeric; after_target numeric;
  previous text:=coalesce(current_setting('fastpas.stock_context',true),'');
begin
  saved:=fastpas_private.inventory_retry(business,request_id,details); if saved is not null then return saved; end if;
  if kind is null or kind not in ('receive','count','transfer','threshold') or product is null or branch is null
    or amount is null or amount not between 0 and 1000000000 or expected is null or expected<0
    or reason is null or length(reason) not between 1 and 300
    or (kind in ('receive','transfer') and amount=0) then
    raise exception 'Invalid stock change' using errcode='22023'; end if;
  if not exists(select 1 from public.pos_items i where i.id=product and i.business_id=business)
    or not exists(select 1 from public.pos_branches b where b.id=branch and b.business_id=business)
    or (kind='transfer' and (destination is null or destination=branch or dest_expected is null or dest_expected<0
      or not exists(select 1 from public.pos_branches b where b.id=destination and b.business_id=business))) then
    raise exception 'Product or branch unavailable' using errcode='42501'; end if;
  -- Match the cash path's item-before-stock lock order.
  perform 1 from public.pos_items i where i.id=product for share;
  if expected=0 then
    insert into public.pos_item_stock(business_id,branch_id,product_id,quantity) values(business,branch,product,0)
      on conflict do nothing;
    get diagnostics inserted=row_count;
    if inserted<>1 then raise exception 'Stock changed; refresh' using errcode='40001'; end if;
  end if;
  if kind='transfer' and dest_expected=0 then
    insert into public.pos_item_stock(business_id,branch_id,product_id,quantity) values(business,destination,product,0)
      on conflict do nothing;
    get diagnostics inserted=row_count;
    if inserted<>1 then raise exception 'Destination stock changed; refresh' using errcode='40001'; end if;
  end if;
  perform 1 from public.pos_item_stock s where s.business_id=business and s.product_id=product
    and s.branch_id in (branch,destination) order by s.branch_id for update;
  select * into source from public.pos_item_stock s where s.business_id=business and s.branch_id=branch and s.product_id=product;
  if not found or (expected>0 and source.stock_version<>expected) then
    raise exception 'Stock changed; refresh' using errcode='40001'; end if;
  if kind='transfer' then
    select * into target from public.pos_item_stock s where s.business_id=business and s.branch_id=destination and s.product_id=product;
    if not found or (dest_expected>0 and target.stock_version<>dest_expected) then
      raise exception 'Destination stock changed; refresh' using errcode='40001'; end if;
    if source.quantity<amount then raise exception 'Insufficient source stock' using errcode='22023'; end if;
  end if;
  after_source:=case kind when 'receive' then source.quantity::numeric+amount when 'count' then amount
    when 'transfer' then source.quantity::numeric-amount else source.quantity end;
  after_target:=coalesce(target.quantity,0)::numeric+amount;
  if after_source not between -9000000000000 and 9000000000000
    or (kind='transfer' and after_target not between -9000000000000 and 9000000000000) then
    raise exception 'Stock quantity too large' using errcode='22023'; end if;
  perform set_config('fastpas.stock_context',jsonb_build_object('kind',kind,'reason',reason,'request_id',request_id)::text,true);
  if kind='threshold' then
    update public.pos_item_stock s set low_stock_threshold=amount::integer
      where s.business_id=business and s.branch_id=branch and s.product_id=product;
  else
    update public.pos_item_stock s set quantity=after_source::bigint
      where s.business_id=business and s.branch_id=branch and s.product_id=product;
  end if;
  if kind='transfer' then
    update public.pos_item_stock s set quantity=after_target::bigint
      where s.business_id=business and s.branch_id=destination and s.product_id=product;
  end if;
  perform set_config('fastpas.stock_context',previous,true);
  select * into source from public.pos_item_stock s where s.business_id=business and s.branch_id=branch and s.product_id=product;
  select * into target from public.pos_item_stock s where s.business_id=business and s.branch_id=destination and s.product_id=product;
  insert into fastpas_private.access_audit(business_id,actor_id,target_id,action)
    values(business,auth.uid(),product,'stock_'||kind);
  return fastpas_private.inventory_done(business,request_id,details,jsonb_build_object(
    'business_id',business,'branch_id',branch,'product_id',product,
    'quantity',source.quantity,'stock_version',source.stock_version,
    'destination_quantity',target.quantity,'destination_version',target.stock_version));
end $$;

create function public.pos_stock_history(business uuid, branch uuid, product uuid default null,
  page_offset integer default 0, page_size integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not fastpas_private.is_owner(business) then raise exception 'Owner access required' using errcode='42501'; end if;
  if not exists(select 1 from public.pos_branches b where b.id=branch and b.business_id=business) then
    raise exception 'Branch unavailable' using errcode='42501'; end if;
  if page_offset is null or page_offset<0 or page_size is null or page_size not between 1 and 100 then
    raise exception 'Invalid history page' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') from (
    select m.* from public.pos_stock_movements m where m.business_id=business and m.branch_id=branch
      and (product is null or m.product_id=product) order by m.created_at desc,m.id offset page_offset limit page_size) x);
end $$;

revoke all on function fastpas_private.inventory_retry(uuid,uuid,jsonb),
  fastpas_private.inventory_done(uuid,uuid,jsonb,jsonb),fastpas_private.stock_version(),fastpas_private.stock_movement()
  from public,anon,authenticated;
revoke all on function public.pos_sync_cash_sale(jsonb),public.pos_catalog_labels(uuid),
  public.pos_save_catalog_label(uuid,uuid,uuid,text,integer,text,boolean),
  public.pos_catalog_items(uuid,uuid,integer,integer,text,boolean),public.pos_save_catalog_item(uuid,uuid,jsonb),
  public.pos_post_stock(uuid,uuid,jsonb),public.pos_stock_history(uuid,uuid,uuid,integer,integer)
  from public,anon,authenticated;
grant execute on function public.pos_sync_cash_sale(jsonb),public.pos_catalog_labels(uuid),
  public.pos_save_catalog_label(uuid,uuid,uuid,text,integer,text,boolean),
  public.pos_catalog_items(uuid,uuid,integer,integer,text,boolean),public.pos_save_catalog_item(uuid,uuid,jsonb),
  public.pos_post_stock(uuid,uuid,jsonb),public.pos_stock_history(uuid,uuid,uuid,integer,integer)
  to authenticated;
notify pgrst,'reload schema';
commit;
