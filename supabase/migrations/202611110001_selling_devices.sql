begin;

create table fastpas_private.selling_devices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  registered_at timestamptz not null,
  last_seen_at timestamptz not null,
  unique (business_id, branch_id, user_id, device_id),
  foreign key (business_id, branch_id)
    references public.pos_branches(business_id, id) on delete cascade
);
create index selling_devices_branch_page
  on fastpas_private.selling_devices(business_id, branch_id, id);
revoke all on fastpas_private.selling_devices from public, anon, authenticated;

create function public.pos_register_selling_device(
  p_business uuid, p_branch uuid, p_device uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  seen_at timestamptz := statement_timestamp();
begin
  perform fastpas_private.require_cash_shift_access(p_business, p_branch);
  if not exists (
    select 1 from public.pos_branches where business_id = p_business and id = p_branch
  ) then
    raise exception 'Branch unavailable' using errcode = '42501';
  end if;
  if p_device is null then
    raise exception 'A device ID is required' using errcode = '22023';
  end if;

  insert into fastpas_private.selling_devices as existing (
    business_id, branch_id, user_id, device_id, registered_at, last_seen_at
  ) values (p_business, p_branch, auth.uid(), p_device, seen_at, seen_at)
  on conflict (business_id, branch_id, user_id, device_id) do update
    set last_seen_at = excluded.last_seen_at
    where existing.last_seen_at <= excluded.last_seen_at - interval '5 minutes';
  return p_device;
end;
$$;

create function public.pos_branch_selling_devices(
  p_business uuid, p_branch uuid, p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if fastpas_private.is_owner(p_business) is not true or not exists (
    select 1 from public.pos_branches where business_id = p_business and id = p_branch
  ) then
    raise exception 'Owner access to this branch is required' using errcode = '42501';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(page) order by page.id), '[]'::jsonb)
    from (
      select id, device_id, registered_at, last_seen_at
      from fastpas_private.selling_devices
      where business_id = p_business and branch_id = p_branch
        and (p_after is null or id > p_after)
      order by id limit 51
    ) as page
  );
end;
$$;

revoke all on function public.pos_register_selling_device(uuid, uuid, uuid),
  public.pos_branch_selling_devices(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.pos_register_selling_device(uuid, uuid, uuid),
  public.pos_branch_selling_devices(uuid, uuid, uuid) to authenticated;

commit;
