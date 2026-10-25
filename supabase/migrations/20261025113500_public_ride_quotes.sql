-- Public read-only estimate for a proposed ride. No trip or personal record is created.
create or replace function public.quote_customer_ride(
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_destination_latitude double precision,
  p_destination_longitude double precision,
  p_area_code text,
  p_vehicle_type text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_area text := upper(trim(coalesce(p_area_code,'DEFAULT')));
  v_enabled boolean;
  v_straight_m integer;
  v_estimated_m integer;
  v_base bigint;
  v_per_km bigint;
  v_minimum bigint;
  v_fare bigint;
  v_multiplier numeric;
begin
  if p_vehicle_type not in ('bike','auto','car') then
    return jsonb_build_object('enabled',false,'message','Unsupported ride type.');
  end if;
  if p_pickup_latitude not between -90 and 90 or p_destination_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_destination_longitude not between -180 and 180 then
    return jsonb_build_object('enabled',false,'message','Choose valid pickup and destination locations.');
  end if;

  select sc.enabled into v_enabled
    from public.service_controls sc
    where sc.service='ride' and sc.area_code in (v_area,'DEFAULT')
    order by case when sc.area_code=v_area then 0 else 1 end limit 1;
  if not coalesce(v_enabled,false) then
    return jsonb_build_object('enabled',false,'message','Rides are not enabled in this service area yet.');
  end if;

  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m<100 or v_straight_m>500000 then
    return jsonb_build_object('enabled',false,'message','This route is outside the supported distance range.');
  end if;
  v_estimated_m := ceil(v_straight_m*1.35)::integer;

  select base_fee_minor,per_km_minor,minimum_fee_minor into v_base,v_per_km,v_minimum
    from public.pricing_rules
    where service='ride' and active=true and city_code in (v_area,'DEFAULT')
    order by case when city_code=v_area then 0 else 1 end limit 1;
  if not found then
    return jsonb_build_object('enabled',false,'message','Ride prices are not configured yet.');
  end if;

  v_multiplier := case p_vehicle_type when 'bike' then 1.0 when 'auto' then 1.5 when 'car' then 2.0 end;
  v_fare := ceil(greatest(v_minimum,v_base+ceil(v_estimated_m/1000.0)::bigint*v_per_km)*v_multiplier)::bigint;
  return jsonb_build_object(
    'enabled',true,'vehicle_type',p_vehicle_type,'estimated_distance_m',v_estimated_m,
    'fare_minor',v_fare,'currency','INR','note','Estimated fare; final amount is calculated and checked by Alteo before creating the ride.'
  );
end;
$function$;

revoke all on function public.quote_customer_ride(double precision,double precision,double precision,double precision,text,text) from public;
grant execute on function public.quote_customer_ride(double precision,double precision,double precision,double precision,text,text) to anon, authenticated;
