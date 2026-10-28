CREATE OR REPLACE FUNCTION public.admin_set_service_control(p_area_code text, p_service text, p_enabled boolean, p_automatic_assignment boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
  v_before jsonb;
  v_control_id uuid;
  v_global_enabled boolean;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 or p_service not in ('ride','parcel','food','shopping','quick') then
    raise exception 'invalid service control' using errcode = '22023';
  end if;
  if v_area <> 'DEFAULT' and not exists (
    select 1 from public.service_areas a
    where a.pincode = v_area and a.active = true
  ) then
    raise exception 'Add and activate the PIN code in Service Availability first.' using errcode = '22023';
  end if;
  if v_area <> 'DEFAULT' and coalesce(p_enabled, false) then
    select sc.enabled into v_global_enabled
      from public.service_controls sc
      where sc.area_code = 'DEFAULT' and sc.service = p_service
      limit 1;
    if not coalesce(v_global_enabled, false) then
      raise exception 'Enable the global service before enabling this PIN code.' using errcode = '22023';
    end if;
  end if;
  if coalesce(p_enabled, false) and not exists (
    select 1 from public.pricing_rules p
    where p.service = p_service and p.active = true
      and (p.city_code = v_area or (v_area <> 'DEFAULT' and p.city_code = 'DEFAULT'))
  ) then
    raise exception 'Configure active pricing before enabling this service.' using errcode = '22023';
  end if;
  select to_jsonb(sc) into v_before
    from public.service_controls sc
    where sc.area_code = v_area and sc.service = p_service;
  insert into public.service_controls(area_code,service,enabled,automatic_assignment,updated_by,updated_at)
  values(v_area,p_service,coalesce(p_enabled,false),coalesce(p_automatic_assignment,false),(select auth.uid()),now())
  on conflict(area_code,service) do update set enabled=excluded.enabled,
    automatic_assignment=excluded.automatic_assignment,updated_by=excluded.updated_by,updated_at=now()
  returning id into v_control_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'service.control_changed','service_control',v_control_id,
      jsonb_build_object('area_code',v_area,'service',p_service,'before',v_before,
        'after',jsonb_build_object('enabled',coalesce(p_enabled,false),
          'automatic_assignment',coalesce(p_automatic_assignment,false),'updated_by',(select auth.uid()))));
  if coalesce(p_enabled,false) and coalesce(p_automatic_assignment,false) then
    if v_area = 'DEFAULT' then
      if p_service = 'ride' then perform private.dispatch_pending_rides(v_area); end if;
      perform private.dispatch_pending_deliveries(v_area);
    else
      select sc.enabled into v_global_enabled
        from public.service_controls sc where sc.area_code = 'DEFAULT' and sc.service = p_service limit 1;
      if coalesce(v_global_enabled,false) then
        if p_service = 'ride' then perform private.dispatch_pending_rides(v_area); end if;
        perform private.dispatch_pending_deliveries(v_area);
      end if;
    end if;
  end if;
end;
$function$;
