-- Alteo admin operations, explicit mutation grants, and audited assignments.
-- Additive migration. Mutations remain protected by server-side role checks and RLS.

grant insert, update, delete on public.service_controls, public.app_banners, public.offers to authenticated;
create index if not exists service_controls_updated_by_idx on public.service_controls(updated_by);
create index if not exists app_banners_created_by_idx on public.app_banners(created_by);
create index if not exists offers_created_by_idx on public.offers(created_by);

create or replace function public.admin_grant_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_user_id is null or p_role not in ('admin','customer','driver_partner','delivery_partner','seller','dark_store') then
    raise exception 'invalid user or role' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  insert into public.user_roles(user_id, role, granted_by)
  values (p_user_id, p_role, (select auth.uid()))
  on conflict (user_id, role) do nothing;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'user.role_granted', 'user', p_user_id, jsonb_build_object('role', p_role));
end;
$$;
revoke all on function public.admin_grant_user_role(uuid, text) from public, anon;
grant execute on function public.admin_grant_user_role(uuid, text) to authenticated;

create or replace function public.admin_assign_delivery_partner(p_delivery_job_id uuid, p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.user_roles ur where ur.user_id = p_partner_id and ur.role = 'delivery_partner') then
    raise exception 'user is not an approved delivery partner' using errcode = '42501';
  end if;
  select status into v_status from public.delivery_jobs where id = p_delivery_job_id for update;
  if not found then raise exception 'delivery job not found' using errcode = 'P0002'; end if;
  if v_status in ('delivered','cancelled','failed') then
    raise exception 'cannot assign a closed delivery job' using errcode = '22023';
  end if;
  update public.delivery_assignments
    set status = 'revoked', updated_at = now()
    where delivery_job_id = p_delivery_job_id and status in ('offered','accepted');
  update public.delivery_jobs
    set delivery_partner_id = p_partner_id, status = 'assigned', updated_at = now()
    where id = p_delivery_job_id;
  insert into public.delivery_assignments(delivery_job_id, partner_id, assigned_by, status)
    values (p_delivery_job_id, p_partner_id, (select auth.uid()), 'offered');
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'delivery.partner_assigned', 'delivery_job', p_delivery_job_id,
      jsonb_build_object('partner_id', p_partner_id, 'assigned_manually', true));
end;
$$;
revoke all on function public.admin_assign_delivery_partner(uuid, uuid) from public, anon;
grant execute on function public.admin_assign_delivery_partner(uuid, uuid) to authenticated;

create or replace function public.admin_assign_driver(p_ride_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.user_roles ur where ur.user_id = p_driver_id and ur.role = 'driver_partner') then
    raise exception 'user is not an approved driver' using errcode = '42501';
  end if;
  select status into v_status from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride not found' using errcode = 'P0002'; end if;
  if v_status not in ('requested','accepted') then
    raise exception 'ride is no longer assignable' using errcode = '22023';
  end if;
  update public.rides set driver_id = p_driver_id, updated_at = now() where id = p_ride_id;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'ride.driver_assigned', 'ride', p_ride_id,
      jsonb_build_object('driver_id', p_driver_id, 'assigned_manually', true));
end;
$$;
revoke all on function public.admin_assign_driver(uuid, uuid) from public, anon;
grant execute on function public.admin_assign_driver(uuid, uuid) to authenticated;

create or replace function public.admin_set_service_control(
  p_area_code text,
  p_service text,
  p_enabled boolean,
  p_automatic_assignment boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 or p_service not in ('ride','parcel','food','shopping','quick') then
    raise exception 'invalid service control' using errcode = '22023';
  end if;
  insert into public.service_controls(area_code, service, enabled, automatic_assignment, updated_by, updated_at)
  values (v_area, p_service, coalesce(p_enabled,false), coalesce(p_automatic_assignment,false), (select auth.uid()), now())
  on conflict (area_code, service) do update
  set enabled = excluded.enabled, automatic_assignment = excluded.automatic_assignment,
      updated_by = excluded.updated_by, updated_at = now();
  insert into public.audit_events(actor_id, action, entity_type, metadata)
  values ((select auth.uid()), 'service.control_changed', 'service_control',
    jsonb_build_object('area_code', v_area, 'service', p_service, 'enabled', p_enabled, 'automatic_assignment', p_automatic_assignment));
end;
$$;
revoke all on function public.admin_set_service_control(text, text, boolean, boolean) from public, anon;
grant execute on function public.admin_set_service_control(text, text, boolean, boolean) to authenticated;

comment on function public.admin_grant_user_role(uuid, text) is 'Admin-only audited provisioning. Users cannot grant roles to themselves.';
comment on function public.admin_assign_delivery_partner(uuid, uuid) is 'Admin-only audited manual delivery assignment; assignment offer must still be accepted by partner.';
comment on function public.admin_assign_driver(uuid, uuid) is 'Admin-only audited manual driver assignment; driver trip state changes remain a separate workflow.';
