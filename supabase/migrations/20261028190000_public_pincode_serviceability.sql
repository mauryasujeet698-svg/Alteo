-- Public, read-only serviceability lookup so customers can browse without signing in.
-- Only active area details and effective service flags are exposed; no private partner/customer records.
create or replace function public.get_public_serviceability(p_pincode text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_pin text := trim(coalesce(p_pincode, ''));
  v_locality text;
  v_district text;
  v_state text;
  v_active boolean := false;
  v_services jsonb := '{}'::jsonb;
  v_ready jsonb := '{}'::jsonb;
  v_service text;
  v_global_enabled boolean;
  v_area_enabled boolean;
  v_pricing_ready boolean;
begin
  if v_pin !~ '^[1-9][0-9]{5}$' then
    return jsonb_build_object('serviceable', false, 'pincode', v_pin, 'message', 'Enter a valid 6-digit PIN code.');
  end if;

  select a.active, a.locality, a.district, a.state
    into v_active, v_locality, v_district, v_state
  from public.service_areas a where a.pincode = v_pin limit 1;

  if not found or not coalesce(v_active, false) then
    return jsonb_build_object('serviceable', false, 'pincode', v_pin, 'message', 'Alteo is not available in this PIN code yet.');
  end if;

  foreach v_service in array array['shopping', 'food', 'quick', 'ride', 'parcel']
  loop
    select sc.enabled into v_global_enabled
    from public.service_controls sc
    where sc.area_code = 'DEFAULT' and sc.service = v_service limit 1;

    select sc.enabled into v_area_enabled
    from public.service_controls sc
    where sc.area_code = v_pin and sc.service = v_service limit 1;

    select exists (
      select 1 from public.pricing_rules pr
      where pr.service = v_service and pr.active = true
        and pr.city_code in (v_pin, 'DEFAULT')
    ) into v_pricing_ready;

    v_services := v_services || jsonb_build_object(
      v_service, coalesce(v_global_enabled, false) and coalesce(v_area_enabled, true)
    );
    v_ready := v_ready || jsonb_build_object(
      v_service, coalesce(v_global_enabled, false)
        and coalesce(v_area_enabled, true)
        and coalesce(v_pricing_ready, false)
    );
  end loop;

  return jsonb_build_object(
    'serviceable', true, 'pincode', v_pin, 'locality', v_locality,
    'district', v_district, 'state', v_state, 'services', v_services,
    'ready_for_orders', v_ready,
    'message', 'This PIN code is in an Alteo service area. Availability depends on the selected service.'
  );
end;
$function$;

revoke all on function public.get_public_serviceability(text) from public;
grant execute on function public.get_public_serviceability(text) to anon, authenticated;
