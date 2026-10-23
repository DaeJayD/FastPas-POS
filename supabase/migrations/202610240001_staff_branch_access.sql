-- Explicit branch reassignment preserves membership and historical sales.
begin;

alter table fastpas_private.access_audit
  add column previous_branches uuid[],
  add column new_branches uuid[];

create or replace function public.pos_staff_access(business uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'branches', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'name', b.name) order by b.name, b.id), '[]'::jsonb)
      from public.pos_branches b where b.business_id = business),
    'members', (select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id, 'email', u.email, 'role', m.role,
      'branch_ids', (select coalesce(jsonb_agg(a.branch_id order by a.branch_id), '[]'::jsonb)
        from public.pos_branch_access a
        where a.business_id = business and a.user_id = m.user_id))
      order by u.email, m.user_id), '[]'::jsonb)
      from public.pos_memberships m join auth.users u on u.id = m.user_id
      where m.business_id = business),
    'invitations', (select coalesce(jsonb_agg(jsonb_build_object(
      'code', i.code, 'email', i.email, 'role', i.role, 'expires_at', i.expires_at)
      order by i.expires_at, i.code), '[]'::jsonb)
      from fastpas_private.invitations i where i.business_id = business
        and i.accepted_at is null and i.expires_at > now())
  );
end;
$$;

create function public.pos_set_staff_branches(business uuid, member uuid, branches uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare member_role text; previous uuid[]; selected uuid[];
begin
  if not fastpas_private.is_owner(business) then
    raise exception 'Owner access required' using errcode = '42501';
  end if;
  select role into member_role from public.pos_memberships
    where business_id = business and user_id = member for update;
  if not found or member_role = 'owner' then
    raise exception 'Select an existing staff membership' using errcode = '22023';
  end if;
  if branches is null or array_position(branches, null) is not null then
    raise exception 'Supply a branch list, using an empty list to clear access' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct branch_id order by branch_id), '{}'::uuid[])
    into selected from unnest(branches) as requested(branch_id);
  if exists(select 1 from unnest(selected) as requested(branch_id)
    where not exists(select 1 from public.pos_branches b
      where b.business_id = business and b.id = requested.branch_id)) then
    raise exception 'Branch does not belong to this business' using errcode = '23503';
  end if;
  select coalesce(array_agg(branch_id order by branch_id), '{}'::uuid[])
    into previous from public.pos_branch_access
    where business_id = business and user_id = member;

  delete from public.pos_branch_access where business_id = business and user_id = member;
  insert into public.pos_branch_access(business_id, branch_id, user_id)
    select business, branch_id, member from unnest(selected) as requested(branch_id);
  -- An old unused code must not undo an explicit access change later.
  delete from fastpas_private.invitations where business_id = business
    and lower(email) = (select lower(email) from auth.users where id = member)
    and accepted_at is null;
  insert into fastpas_private.access_audit(business_id, actor_id, target_id,
    action, previous_role, new_role, previous_branches, new_branches)
    values(business, auth.uid(), member, 'branches_changed', member_role,
      member_role, previous, selected);
end;
$$;

revoke all on function public.pos_set_staff_branches(uuid, uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.pos_set_staff_branches(uuid, uuid, uuid[])
  to authenticated;
commit;
