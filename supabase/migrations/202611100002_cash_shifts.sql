begin;

create table fastpas_private.cash_shifts (
  id uuid primary key,
  business_id uuid not null,
  branch_id uuid not null,
  cashier_id uuid not null references auth.users(id),
  device_id uuid not null,
  opening_cents bigint not null check (opening_cents between 0 and 9000000000000),
  opened_at timestamptz not null default clock_timestamp(),
  close_request_id uuid unique,
  counted_cents bigint check (counted_cents between 0 and 9000000000000),
  expected_at_close bigint,
  closed_at timestamptz,
  ledger_revision bigint not null default 0,
  foreign key (business_id, branch_id) references public.pos_branches(business_id, id)
);
create unique index cash_shifts_one_open
  on fastpas_private.cash_shifts(business_id, branch_id, cashier_id, device_id)
  where closed_at is null;
create table fastpas_private.cash_shift_entries (
  shift_id uuid not null references fastpas_private.cash_shifts(id),
  kind text not null check (kind in ('sale', 'refund', 'movement')),
  source_id uuid not null,
  cents bigint not null,
  reason text,
  posted_at timestamptz not null default clock_timestamp(),
  primary key (kind, source_id),
  check ((kind = 'sale' and cents >= 0 and reason is null)
    or (kind = 'refund' and cents <= 0 and reason is null)
    or (kind = 'movement' and cents <> 0 and reason is not null))
);
create index cash_shift_entries_by_shift on fastpas_private.cash_shift_entries(shift_id);
alter table fastpas_private.cash_shifts enable row level security;
alter table fastpas_private.cash_shift_entries enable row level security;
revoke all on fastpas_private.cash_shifts, fastpas_private.cash_shift_entries
  from public, anon, authenticated;

-- Mark the locked drawer row as changed so a stale transaction snapshot cannot
-- close it after an entry has committed, even at repeatable read.
create function fastpas_private.advance_cash_shift_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update fastpas_private.cash_shifts set ledger_revision = ledger_revision + 1 where id = new.shift_id;
  return null;
end;
$$;
revoke all on function fastpas_private.advance_cash_shift_revision() from public, anon, authenticated;
create trigger cash_shift_revision after insert on fastpas_private.cash_shift_entries
  for each row execute function fastpas_private.advance_cash_shift_revision();

create function fastpas_private.require_cash_shift_access(p_business uuid, p_branch uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if fastpas_private.can_read_branch(p_business, p_branch) is not true or not exists (
    select 1 from public.pos_memberships where business_id = p_business
      and user_id = auth.uid() and role in ('owner', 'manager', 'cashier')
  ) then
    raise exception 'Branch selling access required' using errcode = '42501';
  end if;
end;
$$;

create function fastpas_private.lock_cash_shift(
  p_business uuid, p_branch uuid, p_device uuid, p_shift uuid
) returns fastpas_private.cash_shifts language plpgsql security definer set search_path = '' as $$
declare drawer fastpas_private.cash_shifts;
begin
  perform fastpas_private.require_cash_shift_access(p_business, p_branch);
  select * into drawer from fastpas_private.cash_shifts s where s.id = p_shift
    and s.business_id = p_business and s.branch_id = p_branch
    and s.device_id = p_device and s.cashier_id = auth.uid() for update;
  if not found then
    raise exception 'Cash shift unavailable for this account and device' using errcode = '42501';
  end if;
  return drawer;
end;
$$;

create function fastpas_private.cash_shift_summary(drawer fastpas_private.cash_shifts)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', drawer.id, 'opening_cents', drawer.opening_cents,
    'sales_cents', coalesce(sum(e.cents) filter (where e.kind = 'sale'), 0),
    'refunds_cents', -coalesce(sum(e.cents) filter (where e.kind = 'refund'), 0),
    'cash_in_cents', coalesce(sum(e.cents) filter (where e.kind = 'movement' and e.cents > 0), 0),
    'cash_out_cents', -coalesce(sum(e.cents) filter (where e.kind = 'movement' and e.cents < 0), 0),
    'expected_cents', coalesce(drawer.expected_at_close, drawer.opening_cents + coalesce(sum(e.cents), 0)),
    'counted_cents', drawer.counted_cents,
    'variance_cents', drawer.counted_cents - drawer.expected_at_close,
    'closed_at', drawer.closed_at,
    'recent_movements', (
      select coalesce(jsonb_agg(to_jsonb(recent) order by recent.posted_at desc, recent.source_id desc), '[]'::jsonb)
      from (
        select m.source_id, m.cents, m.reason, m.posted_at from fastpas_private.cash_shift_entries m
        where m.shift_id = drawer.id and m.kind = 'movement'
        order by m.posted_at desc, m.source_id desc limit 10
      ) recent
    ))
  from fastpas_private.cash_shift_entries e where e.shift_id = drawer.id;
$$;

create function public.pos_cash_shift_status(p_business uuid, p_branch uuid, p_device uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare drawer fastpas_private.cash_shifts;
begin
  perform fastpas_private.require_cash_shift_access(p_business, p_branch);
  select * into drawer from fastpas_private.cash_shifts s
    where s.business_id = p_business and s.branch_id = p_branch
      and s.device_id = p_device and s.cashier_id = auth.uid()
    order by (s.closed_at is null) desc, s.opened_at desc, s.id desc limit 1;
  if not found then return null; end if;
  return fastpas_private.cash_shift_summary(drawer);
end;
$$;

create function public.pos_open_cash_shift(
  p_business uuid, p_branch uuid, p_device uuid, p_request uuid, p_opening bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare drawer fastpas_private.cash_shifts;
begin
  perform fastpas_private.require_cash_shift_access(p_business, p_branch);
  if p_device is null or p_request is null or p_opening is null
    or p_opening not between 0 and 9000000000000 then
    raise exception 'Invalid opening cash amount' using errcode = '22023';
  end if;
  insert into fastpas_private.cash_shifts(id, business_id, branch_id, cashier_id, device_id, opening_cents)
    values(p_request, p_business, p_branch, auth.uid(), p_device, p_opening)
    on conflict do nothing;
  select * into drawer from fastpas_private.cash_shifts s where s.id = p_request
    and s.business_id = p_business and s.branch_id = p_branch
    and s.cashier_id = auth.uid() and s.device_id = p_device and s.opening_cents = p_opening;
  if not found then
    raise exception 'A cash shift is already open or the request ID is in use' using errcode = 'PT409';
  end if;
  return fastpas_private.cash_shift_summary(drawer);
end;
$$;

create function public.pos_post_cash_movement(
  p_business uuid, p_branch uuid, p_device uuid, p_shift uuid, p_request uuid, p_cents bigint, p_reason text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  drawer fastpas_private.cash_shifts;
  saved fastpas_private.cash_shift_entries;
  reason text := btrim(p_reason);
begin
  drawer := fastpas_private.lock_cash_shift(p_business, p_branch, p_device, p_shift);
  if p_request is null or p_cents is null or p_cents = 0
    or p_cents not between -9000000000000 and 9000000000000 or reason is null
    or reason !~ '[^[:space:]]' or length(reason) > 240 then
    raise exception 'Supply a cash amount and reason' using errcode = '22023';
  end if;
  if drawer.closed_at is null then
    insert into fastpas_private.cash_shift_entries(shift_id, kind, source_id, cents, reason)
      values(p_shift, 'movement', p_request, p_cents, reason) on conflict do nothing;
  end if;
  select * into saved from fastpas_private.cash_shift_entries e
    where e.kind = 'movement' and e.source_id = p_request;
  if not found or saved.shift_id <> p_shift or saved.cents <> p_cents or saved.reason <> reason then
    raise exception 'Cash shift closed or movement request already used' using errcode = 'PT409';
  end if;
  return fastpas_private.cash_shift_summary(drawer);
end;
$$;

create function public.pos_close_cash_shift(
  p_business uuid, p_branch uuid, p_device uuid, p_shift uuid, p_request uuid, p_counted bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare drawer fastpas_private.cash_shifts;
begin
  drawer := fastpas_private.lock_cash_shift(p_business, p_branch, p_device, p_shift);
  if p_request is null or p_counted is null or p_counted not between 0 and 9000000000000 then
    raise exception 'Invalid counted cash amount' using errcode = '22023';
  end if;
  if drawer.closed_at is null then
    update fastpas_private.cash_shifts set close_request_id = p_request, counted_cents = p_counted,
      expected_at_close = drawer.opening_cents + (select coalesce(sum(e.cents), 0)
        from fastpas_private.cash_shift_entries e where e.shift_id = p_shift),
      closed_at = clock_timestamp()
      where id = p_shift returning * into drawer;
  elsif drawer.close_request_id <> p_request or drawer.counted_cents <> p_counted then
    raise exception 'Cash shift already closed' using errcode = 'PT409';
  end if;
  return fastpas_private.cash_shift_summary(drawer);
end;
$$;

-- Lock the drawer before either workflow writes stock. Retries can read a closed drawer.
create or replace function public.pos_sync_cash_sale(sale jsonb) returns uuid language plpgsql
security definer set search_path = '' as $$
declare
  result uuid;
  drawer fastpas_private.cash_shifts;
  shift_id uuid := (sale->>'cash_shift_id')::uuid;
  sale_id uuid := (sale->>'id')::uuid;
  previous text := coalesce(current_setting('fastpas.stock_context',true),'');
begin
  if shift_id is not null then
    drawer := fastpas_private.lock_cash_shift(
      (sale->>'business_id')::uuid, (sale->>'branch_id')::uuid, (sale->>'device_id')::uuid, shift_id);
    if not exists (
      select 1 from fastpas_private.cash_shift_entries e
      where e.shift_id = drawer.id and e.kind = 'sale' and e.source_id = sale_id
    ) then
      if drawer.closed_at is not null then
        raise exception 'Sale arrived after its cash shift closed' using errcode = 'PT409';
      end if;
      if exists (select 1 from public.pos_cash_sales s where s.id = sale_id) then
        raise exception 'Sale already recorded outside this cash shift' using errcode = 'PT409';
      end if;
    end if;
  end if;
  perform set_config('fastpas.stock_context',jsonb_build_object('kind','sale','reason','Cash sale','sale_id',sale->>'id')::text,true);
  result := fastpas_private.pos_sync_cash_sale(sale);
  perform set_config('fastpas.stock_context',previous,true);
  if shift_id is not null then
    insert into fastpas_private.cash_shift_entries(shift_id, kind, source_id, cents)
      select drawer.id, 'sale', s.id, s.total_cents from public.pos_cash_sales s where s.id = result
      on conflict do nothing;
  end if;
  return result;
end;
$$;

create function public.pos_record_shift_return(
  p_business uuid, p_branch uuid, p_device uuid, p_shift uuid,
  p_sale uuid, p_request uuid, p_reason text, p_items jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  drawer fastpas_private.cash_shifts;
  result jsonb;
begin
  perform fastpas_private.require_cash_return_access(p_business, p_branch);
  drawer := fastpas_private.lock_cash_shift(p_business, p_branch, p_device, p_shift);
  -- Share the refund request lock with the legacy return RPC.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text, 7));
  if exists (select 1 from fastpas_private.cash_returns r where r.id = p_request) then
    if not exists (select 1 from fastpas_private.cash_shift_entries e
      where e.shift_id = drawer.id and e.kind = 'refund' and e.source_id = p_request) then
      raise exception 'Return request already recorded outside this cash shift' using errcode = 'PT409';
    end if;
  elsif drawer.closed_at is not null then
    raise exception 'Cash shift already closed' using errcode = 'PT409';
  end if;
  result := public.pos_record_cash_return(p_business, p_branch, p_sale, p_request, p_reason, p_items);
  insert into fastpas_private.cash_shift_entries(shift_id, kind, source_id, cents)
    values(drawer.id, 'refund', p_request, -(result->>'total_cents')::bigint) on conflict do nothing;
  return result;
end;
$$;

revoke all on function fastpas_private.require_cash_shift_access(uuid, uuid),
  fastpas_private.lock_cash_shift(uuid, uuid, uuid, uuid),
  fastpas_private.cash_shift_summary(fastpas_private.cash_shifts) from public, anon, authenticated;
revoke all on function public.pos_cash_shift_status(uuid, uuid, uuid),
  public.pos_open_cash_shift(uuid, uuid, uuid, uuid, bigint),
  public.pos_post_cash_movement(uuid, uuid, uuid, uuid, uuid, bigint, text),
  public.pos_close_cash_shift(uuid, uuid, uuid, uuid, uuid, bigint),
  public.pos_record_shift_return(uuid, uuid, uuid, uuid, uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.pos_cash_shift_status(uuid, uuid, uuid),
  public.pos_open_cash_shift(uuid, uuid, uuid, uuid, bigint),
  public.pos_post_cash_movement(uuid, uuid, uuid, uuid, uuid, bigint, text),
  public.pos_close_cash_shift(uuid, uuid, uuid, uuid, uuid, bigint),
  public.pos_record_shift_return(uuid, uuid, uuid, uuid, uuid, uuid, text, jsonb) to authenticated;
commit;
