-- Additive business/receipt details and Owner-managed branches.
begin;

alter table public.pos_businesses
  add column address text not null default '' check (length(address) <= 300),
  add column contact_phone text not null default '' check (length(contact_phone) <= 40),
  add column contact_email text not null default '' check (length(contact_email) <= 254),
  add column receipt_footer text not null default 'Thank you for shopping with us.' check (length(receipt_footer) <= 300),
  add column settings_version integer not null default 1 check (settings_version > 0);
alter table public.pos_branches
  add column address text not null default '' check (length(address) <= 300),
  add column settings_version integer not null default 1 check (settings_version > 0);

create function public.pos_business_settings(business uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'business', (select to_jsonb(b) from public.pos_businesses b where b.id = business),
    'branches', (select coalesce(jsonb_agg(to_jsonb(b) order by b.name, b.id), '[]'::jsonb)
      from public.pos_branches b where b.business_id = business)
  );
end;
$$;

create function public.pos_update_business(business uuid, expected_version integer,
  business_name text, business_address text, phone_number text, email_address text, footer text)
returns integer language plpgsql security definer set search_path = '' as $$
declare current_version integer;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  if business_name is null or length(btrim(business_name)) not between 1 and 120
    or business_address is null or length(business_address) > 300
    or phone_number is null or length(phone_number) > 40
    or email_address is null or length(email_address) > 254
    or (btrim(email_address) <> '' and btrim(email_address) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
    or footer is null or length(footer) > 300 then
    raise exception 'Invalid business details' using errcode = '22023';
  end if;
  select b.settings_version into current_version from public.pos_businesses b where b.id = business for update;
  if expected_version is null or expected_version <> current_version then
    raise exception 'Settings changed; reload before saving' using errcode = '40001';
  end if;
  update public.pos_businesses b set name = btrim(business_name), address = btrim(business_address),
    contact_phone = btrim(phone_number), contact_email = btrim(email_address), receipt_footer = btrim(footer),
    settings_version = b.settings_version + 1 where b.id = business;
  insert into fastpas_private.access_audit(business_id, actor_id, target_id, action)
    values(business, auth.uid(), business, 'business_updated');
  return current_version + 1;
end;
$$;

create function public.pos_create_branch(business uuid, request_id uuid, branch_name text, branch_address text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare existing public.pos_branches%rowtype;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  if request_id is null or branch_name is null or length(btrim(branch_name)) not between 1 and 120
    or branch_address is null or length(branch_address) > 300 then
    raise exception 'Invalid branch details' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(request_id::text, 2));
  select * into existing from public.pos_branches b where b.id = request_id;
  if found then
    if existing.business_id <> business then
      raise exception 'Request ID unavailable' using errcode = '42501';
    end if;
    if existing.name <> btrim(branch_name) or existing.address <> btrim(branch_address) then
      raise exception 'Request details changed; reload branches' using errcode = '22023';
    end if;
    return request_id;
  end if;
  insert into public.pos_branches(id, business_id, name, address)
    values(request_id, business, btrim(branch_name), btrim(branch_address));
  insert into fastpas_private.access_audit(business_id, actor_id, target_id, action)
    values(business, auth.uid(), request_id, 'branch_created');
  return request_id;
end;
$$;

create function public.pos_update_branch(business uuid, branch uuid, expected_version integer,
  branch_name text, branch_address text)
returns integer language plpgsql security definer set search_path = '' as $$
declare current_version integer;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  if branch_name is null or length(btrim(branch_name)) not between 1 and 120
    or branch_address is null or length(branch_address) > 300 then
    raise exception 'Invalid branch details' using errcode = '22023';
  end if;
  select b.settings_version into current_version from public.pos_branches b
    where b.id = branch and b.business_id = business for update;
  if not found then
    raise exception 'Branch unavailable' using errcode = '42501';
  end if;
  if expected_version is null or expected_version <> current_version then
    raise exception 'Settings changed; reload before saving' using errcode = '40001';
  end if;
  update public.pos_branches b set name = btrim(branch_name), address = btrim(branch_address),
    settings_version = b.settings_version + 1 where b.id = branch and b.business_id = business;
  insert into fastpas_private.access_audit(business_id, actor_id, target_id, action)
    values(business, auth.uid(), branch, 'branch_updated');
  return current_version + 1;
end;
$$;

revoke all on function public.pos_business_settings(uuid),
  public.pos_update_business(uuid, integer, text, text, text, text, text),
  public.pos_create_branch(uuid, uuid, text, text),
  public.pos_update_branch(uuid, uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.pos_business_settings(uuid),
  public.pos_update_business(uuid, integer, text, text, text, text, text),
  public.pos_create_branch(uuid, uuid, text, text),
  public.pos_update_branch(uuid, uuid, integer, text, text) to authenticated;

commit;
