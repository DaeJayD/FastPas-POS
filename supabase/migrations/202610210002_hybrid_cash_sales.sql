-- Staged retail contract for the new workspaces; no legacy table changes.
begin;
create table public.pos_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pos_businesses(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  sku text not null check (length(btrim(sku)) between 1 and 80),
  price_cents bigint not null check (price_cents between 0 and 1000000000),
  active boolean not null default true,
  unique (business_id, id), unique (business_id, sku)
);
create table public.pos_item_stock (
  business_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  quantity bigint not null,
  primary key (business_id, branch_id, product_id),
  foreign key (business_id, branch_id) references public.pos_branches(business_id, id),
  foreign key (business_id, product_id) references public.pos_items(business_id, id)
);
create table public.pos_cash_sales (
  id uuid primary key,
  business_id uuid not null,
  branch_id uuid not null,
  created_by uuid not null references auth.users(id),
  device_id uuid not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  total_cents bigint not null,
  cash_cents bigint not null,
  payload jsonb not null,
  foreign key (business_id, branch_id) references public.pos_branches(business_id, id)
);
create index pos_cash_sales_branch on public.pos_cash_sales(business_id, branch_id, received_at);
alter table public.pos_items enable row level security;
alter table public.pos_item_stock enable row level security;
alter table public.pos_cash_sales enable row level security;
revoke all on public.pos_items, public.pos_item_stock, public.pos_cash_sales
  from public, anon, authenticated;
grant select on public.pos_items, public.pos_item_stock, public.pos_cash_sales to authenticated;
create policy item_read on public.pos_items for select to authenticated
  using (fastpas_private.is_member(business_id));
create policy item_stock_read on public.pos_item_stock for select to authenticated
  using (fastpas_private.can_read_branch(business_id, branch_id));
create policy cash_sale_read on public.pos_cash_sales for select to authenticated
  using (fastpas_private.can_read_branch(business_id, branch_id) and
    (created_by = auth.uid() or exists(select 1 from public.pos_memberships m
      where m.business_id = pos_cash_sales.business_id and m.user_id = auth.uid()
        and m.role in ('owner', 'manager'))));

create function public.pos_add_item(business uuid, branch uuid, product_name text,
  product_sku text, unit_cents bigint, opening_quantity integer)
returns uuid language plpgsql security definer set search_path = '' as $$
declare product uuid;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  if opening_quantity is null or opening_quantity < 0 then
    raise exception 'Invalid opening stock' using errcode = '22023';
  end if;
  insert into public.pos_items(business_id, name, sku, price_cents)
    values(business, btrim(product_name), btrim(product_sku), unit_cents) returning id into product;
  insert into public.pos_item_stock values(business, branch, product, opening_quantity);
  return product;
end;
$$;

create function public.pos_sync_cash_sale(sale jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); business uuid := (sale->>'business_id')::uuid;
  branch uuid := (sale->>'branch_id')::uuid; sale_id uuid := (sale->>'id')::uuid;
  saved public.pos_cash_sales%rowtype; line jsonb; product public.pos_items%rowtype;
  total bigint := 0; qty integer; unit bigint; cash bigint := (sale->>'cash_cents')::bigint;
begin
  if actor is null or not fastpas_private.can_read_branch(business, branch)
    or not exists(select 1 from public.pos_memberships where business_id = business
      and user_id = actor and role in ('owner', 'manager', 'cashier')) then
    raise exception 'Selling access required' using errcode = '42501';
  end if;
  if sale_id is null or sale->>'device_id' is null or sale->>'occurred_at' is null
    or cash is null or cash < 0 or jsonb_typeof(sale->'items') is distinct from 'array' then
    raise exception 'Invalid sale' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(sale_id::text, 1));
  select * into saved from public.pos_cash_sales where id = sale_id;
  if found then
    if saved.business_id <> business or saved.created_by <> actor or saved.payload <> sale then
      raise exception 'Sale ID conflict' using errcode = '22023';
    end if;
    return sale_id;
  end if;
  if jsonb_array_length(sale->'items') not between 1 and 200 or
    (select count(distinct value->>'product_id') from jsonb_array_elements(sale->'items'))
      <> jsonb_array_length(sale->'items') then
    raise exception 'Invalid sale items' using errcode = '22023';
  end if;
  -- Fixed order prevents opposing carts from locking stock in opposite order.
  for line in select value from jsonb_array_elements(sale->'items') order by value->>'product_id' loop
    qty := (line->>'quantity')::integer; unit := (line->>'unit_cents')::bigint;
    select * into product from public.pos_items where business_id = business
      and id = (line->>'product_id')::uuid and active for share;
    if not found or qty is null or qty not between 1 and 100000
      or unit is null or unit <> product.price_cents
      or line->>'name' is distinct from product.name or line->>'sku' is distinct from product.sku then
      raise exception 'Catalog changed; sale needs review' using errcode = '22023';
    end if;
    update public.pos_item_stock set quantity = quantity - qty
      where business_id = business and branch_id = branch and product_id = product.id;
    if not found then
      raise exception 'Product unavailable at branch' using errcode = '22023';
    end if;
    total := total + unit * qty;
  end loop;
  if cash < total or total > 9000000000000 then
    raise exception 'Invalid cash amount' using errcode = '22023';
  end if;
  -- Negative stock is retained for explicit offline shortage reconciliation.
  insert into public.pos_cash_sales(id, business_id, branch_id, created_by,
    device_id, occurred_at, total_cents, cash_cents, payload)
    values(sale_id, business, branch, actor, (sale->>'device_id')::uuid,
      (sale->>'occurred_at')::timestamptz, total, cash, sale);
  return sale_id;
end;
$$;
revoke all on function public.pos_add_item(uuid, uuid, text, text, bigint, integer),
  public.pos_sync_cash_sale(jsonb) from public, anon, authenticated;
grant execute on function public.pos_add_item(uuid, uuid, text, text, bigint, integer),
  public.pos_sync_cash_sale(jsonb) to authenticated;
commit;
