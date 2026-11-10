-- Cash returns are separate records tied to a synced receipt.
begin;

alter table public.pos_stock_movements drop constraint pos_stock_movements_kind_check;
alter table public.pos_stock_movements add constraint pos_stock_movements_kind_check
  check (kind in ('snapshot','opening','sale','receive','count','transfer','return'));

create table fastpas_private.cash_returns (
  id uuid primary key,
  sale_id uuid not null references public.pos_cash_sales(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  reason text not null,
  total_cents bigint not null check (total_cents between 0 and 9000000000000),
  selection jsonb not null
);
create index cash_returns_sale on fastpas_private.cash_returns(sale_id);
create table fastpas_private.cash_return_lines (
  return_id uuid not null references fastpas_private.cash_returns(id),
  product_id uuid not null,
  product_name text not null,
  sku text not null,
  quantity integer not null check (quantity between 1 and 100000),
  unit_cents bigint not null check (unit_cents between 0 and 1000000000),
  restock boolean not null,
  primary key (return_id, product_id)
);
create table fastpas_private.cash_return_quantities (
  sale_id uuid not null references public.pos_cash_sales(id),
  product_id uuid not null,
  quantity integer not null check (quantity between 1 and 100000),
  primary key (sale_id, product_id)
);
alter table fastpas_private.cash_returns enable row level security;
alter table fastpas_private.cash_return_lines enable row level security;
alter table fastpas_private.cash_return_quantities enable row level security;
revoke all on fastpas_private.cash_returns, fastpas_private.cash_return_lines, fastpas_private.cash_return_quantities
  from public, anon, authenticated;

create function fastpas_private.require_cash_return_access(p_business uuid, p_branch uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if fastpas_private.can_read_branch(p_business, p_branch) is not true or not exists (
    select 1 from public.pos_memberships m where m.business_id = p_business
      and m.user_id = auth.uid() and m.role in ('owner', 'manager')
  ) then
    raise exception 'Branch owner or manager access required' using errcode = '42501';
  end if;
end;
$$;
revoke all on function fastpas_private.require_cash_return_access(uuid, uuid)
  from public, anon, authenticated;

create function public.pos_cash_return_options(p_business uuid, p_branch uuid, p_sale uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare receipt jsonb;
begin
  perform fastpas_private.require_cash_return_access(p_business, p_branch);
  select s.payload into receipt from public.pos_cash_sales s
    where s.id = p_sale and s.business_id = p_business and s.branch_id = p_branch;
  if not found then
    raise exception 'Synced receipt unavailable in this branch' using errcode = '22023';
  end if;
  return (
    select jsonb_agg(jsonb_build_object(
      'product_id', sold.line->>'product_id', 'name', sold.line->>'name',
      'sku', sold.line->>'sku', 'unit_cents', (sold.line->>'unit_cents')::bigint,
      'quantity', (sold.line->>'quantity')::integer,
      'remaining_quantity', (sold.line->>'quantity')::integer - coalesce(returned.quantity, 0)
    ) order by sold.position)
    from jsonb_array_elements(receipt->'items') with ordinality as sold(line, position)
    left join fastpas_private.cash_return_quantities returned on returned.sale_id = p_sale
      and returned.product_id = (sold.line->>'product_id')::uuid
  );
end;
$$;

create function public.pos_record_cash_return(
  p_business uuid, p_branch uuid, p_sale uuid, p_request uuid, p_reason text, p_items jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  reason text := btrim(p_reason);
  receipt jsonb;
  selection jsonb;
  saved fastpas_private.cash_returns%rowtype;
  item record;
  sold jsonb;
  product_count bigint;
  sold_quantity integer;
  refund_total bigint := 0;
  previous_context text := coalesce(current_setting('fastpas.stock_context', true), '');
begin
  perform fastpas_private.require_cash_return_access(p_business, p_branch);
  if p_request is null or reason is null or reason !~ '[^[:space:]]'
    or length(reason) > 240 or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Supply a return request, reason and items' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 200 then
    raise exception 'Select between 1 and 200 return lines' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) as item(value)
    where jsonb_typeof(value) is distinct from 'object'
      or jsonb_typeof(value->'product_id') is distinct from 'string'
      or jsonb_typeof(value->'quantity') is distinct from 'number'
      or (value->>'quantity') !~ '^[1-9][0-9]{0,5}$'
      or jsonb_typeof(value->'restock') is distinct from 'boolean'
  ) then
    raise exception 'Invalid return line' using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object(
      'product_id', requested.product_id, 'quantity', requested.quantity, 'restock', requested.restock
    ) order by requested.product_id), count(distinct requested.product_id)
    into selection, product_count
    from jsonb_to_recordset(p_items) as requested(product_id uuid, quantity integer, restock boolean);
  if product_count <> jsonb_array_length(p_items) then
    raise exception 'Return lines must name distinct products' using errcode = '22023';
  end if;

  -- A reused request ID must resolve to the same committed return.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text, 7));
  select s.payload into receipt from public.pos_cash_sales s
    where s.id = p_sale and s.business_id = p_business and s.branch_id = p_branch;
  if not found then
    raise exception 'Synced receipt unavailable in this branch' using errcode = '22023';
  end if;
  select * into saved from fastpas_private.cash_returns r where r.id = p_request;
  if found then
    if saved.sale_id <> p_sale or saved.created_by <> actor or saved.reason <> reason
      or saved.selection <> selection then
      raise exception 'Return request ID already used' using errcode = 'PT409';
    end if;
    return jsonb_build_object('id', saved.id, 'total_cents', saved.total_cents, 'created_at', saved.created_at);
  end if;

  insert into fastpas_private.cash_returns(id, sale_id, created_by, reason, total_cents, selection)
    values (p_request, p_sale, actor, reason, 0, selection);
  perform set_config('fastpas.stock_context', jsonb_build_object(
    'kind', 'return', 'reason', reason, 'request_id', p_request, 'sale_id', p_sale
  )::text, true);
  -- Consistent product order matches checkout when locking shared stock rows.
  for item in select * from jsonb_to_recordset(selection)
    as requested(product_id uuid, quantity integer, restock boolean) order by product_id
  loop
    select value into sold from jsonb_array_elements(receipt->'items')
      where (value->>'product_id')::uuid = item.product_id;
    if not found then
      raise exception 'Product was not on this receipt' using errcode = '22023';
    end if;
    sold_quantity := (sold->>'quantity')::integer;
    if item.quantity > sold_quantity then
      raise exception 'Return quantity exceeds the remaining units' using errcode = 'PT409';
    end if;
    -- The conditional update checks the latest committed counter under its row lock.
    insert into fastpas_private.cash_return_quantities as returned(sale_id, product_id, quantity)
      values (p_sale, item.product_id, item.quantity)
      on conflict (sale_id, product_id) do update set quantity = returned.quantity + excluded.quantity
        where returned.quantity + excluded.quantity <= sold_quantity;
    if not found then
      raise exception 'Return quantity exceeds the remaining units' using errcode = 'PT409';
    end if;

    insert into fastpas_private.cash_return_lines(return_id, product_id, product_name, sku, quantity, unit_cents, restock)
      values (p_request, item.product_id, sold->>'name', sold->>'sku',
        item.quantity, (sold->>'unit_cents')::bigint, item.restock);
    refund_total := refund_total + item.quantity * (sold->>'unit_cents')::bigint;
    if item.restock then
      update public.pos_item_stock set quantity = quantity + item.quantity
        where business_id = p_business and branch_id = p_branch and product_id = item.product_id;
      if not found then
        raise exception 'Product stock unavailable in this branch' using errcode = 'PT409';
      end if;
    end if;
  end loop;
  perform set_config('fastpas.stock_context', previous_context, true);
  update fastpas_private.cash_returns set total_cents = refund_total where id = p_request returning * into saved;
  return jsonb_build_object('id', saved.id, 'total_cents', saved.total_cents, 'created_at', saved.created_at);
end;
$$;

revoke all on function public.pos_cash_return_options(uuid, uuid, uuid),
  public.pos_record_cash_return(uuid, uuid, uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.pos_cash_return_options(uuid, uuid, uuid),
  public.pos_record_cash_return(uuid, uuid, uuid, uuid, text, jsonb) to authenticated;
commit;
