begin;
create table fastpas_private.access_audit (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pos_businesses(id),
  actor_id uuid not null references auth.users(id),
  target_id uuid not null,
  action text not null,
  previous_role text,
  new_role text,
  created_at timestamptz not null default now()
);
revoke all on fastpas_private.access_audit from public, anon, authenticated;
create function public.pos_staff_access(business uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'members', (select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id, 'email', u.email, 'role', m.role)), '[]'::jsonb)
      from public.pos_memberships m join auth.users u on u.id = m.user_id
      where m.business_id = business),
    'invitations', (select coalesce(jsonb_agg(jsonb_build_object(
      'code', i.code, 'email', i.email, 'role', i.role, 'expires_at', i.expires_at)), '[]'::jsonb)
      from fastpas_private.invitations i where i.business_id = business
        and i.accepted_at is null and i.expires_at > now())
  );
end;
$$;

create function public.pos_change_staff_access(business uuid, member uuid, new_role text)
returns void language plpgsql security definer set search_path = '' as $$
declare member_role text;
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  select role into member_role from public.pos_memberships
    where business_id = business and user_id = member for update;
  if not found or member_role = 'owner' then
    raise exception 'Owner membership cannot be changed here' using errcode = '22023';
  end if;
  if new_role is null then
    delete from public.pos_branch_access where business_id = business and user_id = member;
    delete from public.pos_memberships where business_id = business and user_id = member;
    -- Cancel old invitations so removed staff cannot rejoin with an unused code.
    delete from fastpas_private.invitations where business_id = business
      and lower(email) = (select lower(email) from auth.users where id = member)
      and accepted_at is null;
  elsif new_role in ('manager', 'cashier', 'employee') then
    update public.pos_memberships set role = new_role
      where business_id = business and user_id = member;
  else
    raise exception 'Invalid staff role' using errcode = '22023';
  end if;
  insert into fastpas_private.access_audit(business_id, actor_id, target_id,
    action, previous_role, new_role)
    values(business, auth.uid(), member,
      case when new_role is null then 'membership_removed' else 'role_changed' end,
      member_role, new_role);
end;
$$;

create function public.pos_cancel_invitation(invite_code uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare business uuid;
begin
  select business_id into business from fastpas_private.invitations
    where code = invite_code for update;
  if not found or not fastpas_private.is_owner(business) then
    raise exception 'Invitation unavailable' using errcode = '42501';
  end if;
  delete from fastpas_private.invitations where code = invite_code and accepted_at is null;
  if found then
    insert into fastpas_private.access_audit(business_id, actor_id, target_id, action)
      values(business, auth.uid(), invite_code, 'invitation_cancelled');
  end if;
end;
$$;
revoke all on function public.pos_staff_access(uuid),
  public.pos_change_staff_access(uuid, uuid, text), public.pos_cancel_invitation(uuid)
  from public, anon, authenticated;
grant execute on function public.pos_staff_access(uuid),
  public.pos_change_staff_access(uuid, uuid, text), public.pos_cancel_invitation(uuid)
  to authenticated;
commit;
