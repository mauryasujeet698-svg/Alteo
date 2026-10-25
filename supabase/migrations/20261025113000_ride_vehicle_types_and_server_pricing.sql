-- Record the selected ride class and expose a server-priced ride request flow.
alter table public.rides
  add column if not exists vehicle_type text not null default 'bike';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.rides'::regclass and conname = 'rides_vehicle_type_check'
  ) then
    alter table public.rides
      add constraint rides_vehicle_type_check check (vehicle_type in ('bike','auto','car'));
  end if;
end $$;

create or replace function public.create_customer_ride(
  p_pickup_label text,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_destination_label text,
  p_destination_latitude double precision,
  p_destination_longitude double precision,
  p_idempotency_key text,
  p_area_code text,
  p_vehicle_type text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_customer uuid := auth.uid();
  v_area text := upper(trim(coalesce(p_area_code,'DEFAULT')));
  v_enabled boolean;
  v_straight_m integer;
  v_estimated_m integer;
  v_base bigint;
  v_per_km bigint;
  v_minimum bigint;
  v_fare bigint;
  v_multiplier numeric;
  v_ride uuid;
begin
  if v_customer is null then raise exception 'sign-in required' using errcode='42501'; end if;
  if p_vehicle_type not in ('bike','auto','car') then
    raise exception 'unsupported vehicle type' using errcode='22023';
  end if;
  if coalesce(length(trim(p_pickup_label)),0)<2 or coalesce(length(trim(p_destination_label)),0)<2 then
    raise exception 'pickup and destination are required' using errcode='22023';
  end if;
  if p_pickup_latitude not between -90 and 90 or p_destination_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_destination_longitude not between -180 and 180 then
    raise exception 'invalid pickup or destination coordinates' using errcode='22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key)<16 or char_length(p_idempotency_key)>128 then
    raise exception 'invalid idempotency key' using errcode='22023';
  end if;

  select id into v_ride from public.rides
   where customer_id=v_customer and idempotency_key=p_idempotency_key;
  if v_ride is not null then return v_ride; end if;

  select sc.enabled into v_enabled from public.service_controls sc
   where sc.service='ride' and sc.area_code in (v_area,'DEFAULT')
   order by case when sc.area_code=v_area then 0 else 1 end limit 1;
  if not coalesce(v_enabled,false) then
    raise exception 'ride service is not enabled for this area' using errcode='P0002';
  end if;

  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m<100 or v_straight_m>500000 then
    raise exception 'ride distance is outside supported limits' using errcode='22023';
  end if;
  v_estimated_m := ceil(v_straight_m*1.35)::integer;

  select base_fee_minor, per_km_minor, minimum_fee_minor into v_base, v_per_km, v_minimum
   from public.pricing_rules
   where service='ride' and active=true and city_code in (v_area,'DEFAULT')
   order by case when city_code=v_area then 0 else 1 end limit 1;
  if not found then raise exception 'ride pricing is not configured for this area' using errcode='P0002'; end if;

  v_multiplier := case p_vehicle_type when 'bike' then 1.0 when 'auto' then 1.5 when 'car' then 2.0 end;
  v_fare := ceil(greatest(v_minimum, v_base+ceil(v_estimated_m/1000.0)::bigint*v_per_km) * v_multiplier)::bigint;

  insert into public.rides(
    customer_id,status,pickup_label,destination_label,pickup_latitude,pickup_longitude,
    destination_latitude,destination_longitude,estimated_distance_m,fare_minor,idempotency_key,area_code,vehicle_type
  )
  values(
    v_customer,'requested',trim(p_pickup_label),trim(p_destination_label),p_pickup_latitude,p_pickup_longitude,
    p_destination_latitude,p_destination_longitude,v_estimated_m,v_fare,p_idempotency_key,v_area,p_vehicle_type
  )
  returning id into v_ride;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_customer,'ride.requested','ride',v_ride,jsonb_build_object(
    'area_code',v_area,'estimated_distance_m',v_estimated_m,'vehicle_type',p_vehicle_type
  ));
  return v_ride;
exception when unique_violation then
  select id into v_ride from public.rides where customer_id=auth.uid() and idempotency_key=p_idempotency_key;
  if v_ride is not null then return v_ride; end if;
  raise;
end;
$function$;

revoke all on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text,text) from public;
grant execute on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text,text) to authenticated;
