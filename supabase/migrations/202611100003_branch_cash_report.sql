begin;

create index pos_cash_sales_occurred on public.pos_cash_sales(business_id, branch_id, occurred_at);
create index cash_returns_created on fastpas_private.cash_returns(created_at);
create index cash_shifts_closed on fastpas_private.cash_shifts(business_id, branch_id, closed_at)
  where closed_at is not null;

create function public.pos_branch_cash_report(
  p_business uuid, p_branch uuid, p_from date, p_through date, p_timezone text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  start_day date := p_from;
  end_day date := p_through;
  start_instant timestamptz;
  end_instant timestamptz;
begin
  perform fastpas_private.require_cash_return_access(p_business, p_branch);
  if not exists (
    select 1 from public.pos_branches where business_id = p_business and id = p_branch
  ) then
    raise exception 'Branch unavailable for reporting' using errcode = '42501';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Enter a valid reporting time zone' using errcode = '22023';
  end if;
  if start_day is null and end_day is null then
    end_day := timezone(p_timezone, now())::date;
    start_day := end_day - 6;
  end if;
  if start_day is null or end_day is null
    or start_day not between date '1900-01-01' and date '9999-12-31'
    or end_day not between date '1900-01-01' and date '9999-12-31' then
    raise exception 'Supply a valid start and end date' using errcode = '22023';
  end if;
  if end_day - start_day not between 0 and 92 then
    raise exception 'Choose a reporting period of 1 to 93 days' using errcode = '22023';
  end if;
  -- Bound the indexed scan in UTC, then filter by exact local date. Some zones
  -- repeat midnight, so converting an ambiguous local boundary can lose events.
  start_instant := timezone('UTC', start_day::timestamp - interval '1 day');
  end_instant := timezone('UTC', (end_day + 1)::timestamp + interval '1 day');

  return (
    with sales as (
      select timezone(p_timezone, s.occurred_at)::date as day,
        count(*) as sale_count, sum(s.total_cents) as gross_cents
      from public.pos_cash_sales s
      where s.business_id = p_business and s.branch_id = p_branch
        and s.occurred_at >= start_instant and s.occurred_at < end_instant
        and timezone(p_timezone, s.occurred_at)::date between start_day and end_day
      group by 1
    ), refunds as (
      select timezone(p_timezone, r.created_at)::date as day,
        count(*) as refund_count, sum(r.total_cents) as refund_cents
      from fastpas_private.cash_returns r join public.pos_cash_sales s on s.id = r.sale_id
      where s.business_id = p_business and s.branch_id = p_branch
        and r.created_at >= start_instant and r.created_at < end_instant
        and timezone(p_timezone, r.created_at)::date between start_day and end_day
      group by 1
    ), closings as (
      select timezone(p_timezone, d.closed_at)::date as day,
        count(*) as shift_count, sum(d.expected_at_close) as expected_cents,
        sum(d.counted_cents) as counted_cents
      from fastpas_private.cash_shifts d
      where d.business_id = p_business and d.branch_id = p_branch
        and d.closed_at >= start_instant and d.closed_at < end_instant
        and timezone(p_timezone, d.closed_at)::date between start_day and end_day
      group by 1
    ), daily as (
      select start_day + offset_days as day
      from generate_series(0, end_day - start_day) as offsets(offset_days)
    )
    select jsonb_build_object(
      'business_id', p_business, 'branch_id', p_branch, 'from_day', start_day,
      'through_day', end_day, 'timezone', p_timezone,
      'days', jsonb_agg(jsonb_build_object(
        'day', daily.day, 'sale_count', coalesce(sales.sale_count, 0),
        'gross_cents', coalesce(sales.gross_cents, 0),
        'refund_count', coalesce(refunds.refund_count, 0),
        'refund_cents', coalesce(refunds.refund_cents, 0),
        'shift_count', coalesce(closings.shift_count, 0),
        'expected_cents', coalesce(closings.expected_cents, 0),
        'counted_cents', coalesce(closings.counted_cents, 0)
      ) order by daily.day)
    ) from daily
    left join sales using (day)
    left join refunds using (day)
    left join closings using (day)
  );
end;
$$;

revoke all on function public.pos_branch_cash_report(uuid, uuid, date, date, text)
  from public, anon, authenticated;
grant execute on function public.pos_branch_cash_report(uuid, uuid, date, date, text)
  to authenticated;
commit;
