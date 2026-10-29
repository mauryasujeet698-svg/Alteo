-- Prevent approval while a request is waiting on the applicant, and allow any partner to go offline.
create or replace function public.admin_review_role_request(
  p_request_id uuid, p_approve boolean, p_rejection_reason text default null
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.role_requests%rowtype;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'Administrator role required.' using errcode = '42501';
  end if;
  select * into v_request from public.role_requests where id = p_request_id for update;
  if not found then raise exception 'Application not found.' using errcode = 'P0002'; end if;
  if v_request.status <> 'pending' then raise exception 'Only pending applications can be reviewed.' using errcode = '22023'; end if;
  if p_approve and v_request.needs_correction then
    raise exception 'This application is awaiting applicant corrections. Review it again after they resubmit.' using errcode = '22023';
  end if;
  if p_approve then
    perform public.admin_grant_user_role(v_request.user_id, v_request.requested_role);
    update public.role_requests set status = 'approved', reviewed_at = now(), reviewed_by = (select auth.uid()),
      needs_correction = false, correction_reason = null, rejection_reason = null, updated_at = now()
    where id = p_request_id;
  else
    update public.role_requests set status = 'rejected', reviewed_at = now(), reviewed_by = (select auth.uid()),
      needs_correction = false, correction_reason = null,
      rejection_reason = coalesce(nullif(trim(p_rejection_reason), ''),
        'Please review your details and contact Alteo support if you need help.'), updated_at = now()
    where id = p_request_id;
  end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), case when p_approve then 'role_request.approved' else 'role_request.rejected' end,
    'role_request', p_request_id, jsonb_build_object('user_id', v_request.user_id, 'role', v_request.requested_role));
end;
$function$;


revoke all on function public.admin_review_role_request(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_role_request(uuid, boolean, text) to authenticated;

create or replace function public.partner_set_availability(
  p_role text, p_area_code text, p_is_online boolean,
  p_latitude double precision default null, p_longitude double precision default null
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
begin
  if (select auth.uid()) is null then raise exception 'Sign in before changing availability.' using errcode = '42501'; end if;
  if p_role not in ('driver_partner', 'delivery_partner') then raise exception 'Invalid partner role.' using errcode = '22023'; end if;
  if not exists (select 1 from public.user_roles ur where ur.user_id = (select auth.uid()) and ur.role = p_role) then
    raise exception 'Your account is not approved for this partner role.' using errcode = '42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 then raise exception 'Choose a valid service area.' using errcode = '22023'; end if;
  if coalesce(p_is_online, false) and exists (select 1 from public.service_areas) and (
    v_area !~ '^[1-9][0-9]{5}
    raise exception 'Choose an active 6-digit service PIN code before changing availability.' using errcode = '22023';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
     or (p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180)) then
    raise exception 'Invalid coordinates.' using errcode = '22023';
  end if;
  insert into public.partner_presence(user_id, role, area_code, is_online, latitude, longitude, updated_at)
  values ((select auth.uid()), p_role, v_area, coalesce(p_is_online, false), p_latitude, p_longitude, now())
  on conflict (user_id, role) do update
    set area_code = excluded.area_code, is_online = excluded.is_online,
        latitude = excluded.latitude, longitude = excluded.longitude, updated_at = now();
  insert into public.audit_events(actor_id, action, entity_type, metadata)
  values ((select auth.uid()), case when p_is_online then 'partner.online' else 'partner.offline' end,
    'partner_presence', jsonb_build_object('role', p_role, 'area_code', v_area));
  if p_is_online then
    perform private.dispatch_pending_rides(v_area);
    perform private.dispatch_pending_deliveries(v_area);
  end if;
end;
$function$;
    or not exists (select 1 from public.service_areas a where a.pincode = v_area and a.active = true)
  ) then
    raise exception 'Choose an active 6-digit service PIN code before changing availability.' using errcode = '22023';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
     or (p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180)) then
    raise exception 'Invalid coordinates.' using errcode = '22023';
  end if;
  insert into public.partner_presence(user_id, role, area_code, is_online, latitude, longitude, updated_at)
  values ((select auth.uid()), p_role, v_area, coalesce(p_is_online, false), p_latitude, p_longitude, now())
  on conflict (user_id, role) do update
    set area_code = excluded.area_code, is_online = excluded.is_online,
        latitude = excluded.latitude, longitude = excluded.longitude, updated_at = now();
  insert into public.audit_events(actor_id, action, entity_type, metadata)
  values ((select auth.uid()), case when p_is_online then 'partner.online' else 'partner.offline' end,
    'partner_presence', jsonb_build_object('role', p_role, 'area_code', v_area));
  if p_is_online then
    perform private.dispatch_pending_rides(v_area);
    perform private.dispatch_pending_deliveries(v_area);
  end if;
end;
$function$;

revoke all on function public.partner_set_availability(text, text, boolean, double precision, double precision) from public, anon;
grant execute on function public.partner_set_availability(text, text, boolean, double precision, double precision) to authenticated;
