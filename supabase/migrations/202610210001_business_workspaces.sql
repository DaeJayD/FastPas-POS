-- Additive foundation. Legacy retail tables are intentionally not connected.
begin;

create schema if not exists fastpas_private;
revoke all on schema fastpas_private from public, anon, authenticated;
grant usage on schema fastpas_private to authenticated;

create table public.pos_businesses (
  id uuid primary key,
  name text not null check (length(btrim(name)) between 1 and 120),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create table public.pos_memberships (
  business_id uuid not null references public.pos_businesses(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('owner', 'manager', 'cashier', 'employee')),
  primary key (business_id, user_id)
);
create index pos_memberships_user on public.pos_memberships(user_id, business_id);
create table public.pos_branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pos_businesses(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  unique (business_id, id)
);
create table public.pos_branch_access (
  business_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null,
  primary key (business_id, branch_id, user_id),
  foreign key (business_id, branch_id)
    references public.pos_branches(business_id, id),
  foreign key (business_id, user_id)
    references public.pos_memberships(business_id, user_id)
);
create table fastpas_private.invitations (
  code uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  email text not null check (length(email) between 3 and 320),
  role text not null check (role in ('manager', 'cashier', 'employee')),
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  foreign key (business_id, branch_id)
    references public.pos_branches(business_id, id)
);
revoke all on all tables in schema fastpas_private from public, anon, authenticated;

-- Definer helpers avoid recursive membership RLS. Never expose this schema
-- through the API; the only caller identity comes from auth.uid().
create function fastpas_private.is_member(business uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.pos_memberships
    where business_id = business and user_id = auth.uid());
$$;
create function fastpas_private.is_owner(business uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.pos_memberships
    where business_id = business and user_id = auth.uid() and role = 'owner');
$$;
create function fastpas_private.can_read_branch(business uuid, branch uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select fastpas_private.is_owner(business) or exists(
    select 1 from public.pos_branch_access a
    join public.pos_memberships m using (business_id, user_id)
    where a.business_id = business and a.branch_id = branch
      and a.user_id = auth.uid());
$$;
revoke all on all functions in schema fastpas_private from public, anon, authenticated;
grant execute on function fastpas_private.is_member(uuid),
  fastpas_private.is_owner(uuid), fastpas_private.can_read_branch(uuid, uuid)
  to authenticated;

alter table public.pos_businesses enable row level security;
alter table public.pos_memberships enable row level security;
alter table public.pos_branches enable row level security;
alter table public.pos_branch_access enable row level security;
revoke all on public.pos_businesses, public.pos_memberships,
  public.pos_branches, public.pos_branch_access from public, anon, authenticated;
grant select on public.pos_businesses, public.pos_memberships,
  public.pos_branches, public.pos_branch_access to authenticated;
create policy business_read on public.pos_businesses for select to authenticated
  using (fastpas_private.is_member(id));
create policy membership_read on public.pos_memberships for select to authenticated
  using (user_id = auth.uid() or fastpas_private.is_owner(business_id));
create policy branch_read on public.pos_branches for select to authenticated
  using (fastpas_private.can_read_branch(business_id, id));
create policy branch_access_read on public.pos_branch_access for select to authenticated
  using (user_id = auth.uid() or fastpas_private.is_owner(business_id));

create function public.pos_create_business(
  request_id uuid, business_name text, branch_name text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); existing_creator uuid;
begin
  if actor is null or not exists(select 1 from auth.users
      where id = actor and email_confirmed_at is not null) then
    raise exception 'A verified account is required' using errcode = '42501';
  end if;
  if request_id is null or business_name is null or branch_name is null
    or length(btrim(business_name)) not between 1 and 120
    or length(btrim(branch_name)) not between 1 and 120 then
    raise exception 'Business and branch names are required' using errcode = '22023';
  end if;
  -- Serialize the same request so retrying cannot create duplicate branches.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(request_id::text, 0));
  select created_by into existing_creator from public.pos_businesses where id = request_id;
  if found then
    if existing_creator <> actor or not fastpas_private.is_owner(request_id) then
      raise exception 'Request ID unavailable' using errcode = '42501';
    end if;
    return request_id;
  end if;
  insert into public.pos_businesses(id, name, created_by)
    values(request_id, btrim(business_name), actor);
  insert into public.pos_memberships values(request_id, actor, 'owner');
  insert into public.pos_branches(business_id, name) values(request_id, btrim(branch_name));
  return request_id;
end;
$$;

create function public.pos_invite_staff(
  business uuid, branch uuid, invite_email text, invite_role text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare invite_code uuid;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  if invite_role is null or invite_role not in ('manager', 'cashier', 'employee')
    or invite_email is null or btrim(invite_email) not like '%_@_%._%' then
    raise exception 'Invalid invitation' using errcode = '22023';
  end if;
  insert into fastpas_private.invitations(business_id, branch_id, email, role, created_by)
    values(business, branch, lower(btrim(invite_email)), invite_role, auth.uid())
    returning code into invite_code;
  return invite_code;
end;
$$;

create function public.pos_accept_invitation(invite_code uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invitation fastpas_private.invitations%rowtype; actor uuid := auth.uid();
  actor_email text; existing_role text;
begin
  select lower(email) into actor_email from auth.users
    where id = actor and email_confirmed_at is not null;
  if actor_email is null then
    raise exception 'A verified account is required' using errcode = '42501';
  end if;
  select * into invitation from fastpas_private.invitations
    where code = invite_code for update;
  if not found or invitation.accepted_at is not null
    or invitation.expires_at <= now() or invitation.email <> actor_email
    or not exists(select 1 from public.pos_memberships
      where business_id = invitation.business_id and user_id = invitation.created_by
        and role = 'owner') then
    raise exception 'Invitation unavailable' using errcode = '42501';
  end if;
  select role into existing_role from public.pos_memberships
    where business_id = invitation.business_id and user_id = actor for update;
  if found and existing_role <> invitation.role then
    raise exception 'Existing role requires an explicit membership change' using errcode = '22023';
  end if;
  insert into public.pos_memberships values(invitation.business_id, actor, invitation.role)
    on conflict do nothing;
  insert into public.pos_branch_access values(invitation.business_id, invitation.branch_id, actor)
    on conflict do nothing;
  update fastpas_private.invitations set accepted_at = now() where code = invite_code;
  return invitation.business_id;
end;
$$;

revoke all on function public.pos_create_business(uuid, text, text),
  public.pos_invite_staff(uuid, uuid, text, text), public.pos_accept_invitation(uuid)
  from public, anon, authenticated;
grant execute on function public.pos_create_business(uuid, text, text),
  public.pos_invite_staff(uuid, uuid, text, text), public.pos_accept_invitation(uuid)
  to authenticated;
commit;
