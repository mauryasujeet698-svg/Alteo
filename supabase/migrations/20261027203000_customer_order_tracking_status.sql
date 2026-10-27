CREATE OR REPLACE FUNCTION public.customer_tracking_snapshot(p_entity_type text, p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type text := p_entity_type;
  v_status text;
  v_customer_id uuid;
  v_partner_id uuid;
  v_partner_role text;
  v_pickup_label text;
  v_destination_label text;
  v_pickup_lat double precision;
  v_pickup_lon double precision;
  v_dest_lat double precision;
  v_dest_lon double precision;
  v_partner_lat double precision;
  v_partner_lon double precision;
  v_partner_updated timestamptz;
  v_trip_distance integer;
  v_trip_duration integer;
  v_to_target_distance integer;
  v_eta_seconds integer;
  v_tracking_id uuid;
  v_target_lat double precision;
  v_target_lon double precision;
  v_job_type text;
  v_order_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  if p_entity_id is null or v_type not in ('ride','order','parcel') then
    raise exception 'unsupported tracking request' using errcode = '22023';
  end if;

  if v_type = 'ride' then
    select r.customer_id, r.driver_id, r.status, r.pickup_label, r.destination_label,
           r.pickup_latitude, r.pickup_longitude, r.destination_latitude, r.destination_longitude,
           r.estimated_distance_m, r.estimated_duration_s, r.id
      into v_customer_id, v_partner_id, v_status, v_pickup_label, v_destination_label,
           v_pickup_lat, v_pickup_lon, v_dest_lat, v_dest_lon,
           v_trip_distance, v_trip_duration, v_tracking_id
    from public.rides r where r.id = p_entity_id;
    if not found or v_customer_id <> (select auth.uid()) then
      raise exception 'ride not found for this customer' using errcode = '42501';
    end if;
    v_partner_role := 'driver_partner';

  elsif v_type = 'order' then
    select o.customer_id, o.status into v_customer_id, v_order_status
    from public.orders o where o.id = p_entity_id;
    if not found or v_customer_id <> (select auth.uid()) then
      raise exception 'order not found for this customer' using errcode = '42501';
    end if;

    select j.id, j.customer_id, j.delivery_partner_id, j.status, j.pickup_label, j.destination_label,
           j.pickup_latitude, j.pickup_longitude, j.destination_latitude, j.destination_longitude,
           j.estimated_distance_m, j.estimated_duration_s, j.job_type
      into v_tracking_id, v_customer_id, v_partner_id, v_status, v_pickup_label, v_destination_label,
           v_pickup_lat, v_pickup_lon, v_dest_lat, v_dest_lon,
           v_trip_distance, v_trip_duration, v_job_type
    from public.delivery_jobs j
    where j.order_id = p_entity_id and j.customer_id = (select auth.uid())
    order by j.created_at desc limit 1;

    if v_tracking_id is null then
      return jsonb_build_object(
        'entity_type','order','entity_id',p_entity_id,'status',v_order_status,'order_status',v_order_status,
        'tracking_available',false,'location_available',false,
        'message','Your order is recorded. Live delivery tracking appears after dispatch assigns a delivery partner.'
      );
    end if;
    v_type := 'order';
    v_partner_role := 'delivery_partner';
  else
    select j.id, j.customer_id, j.delivery_partner_id, j.status, j.pickup_label, j.destination_label,
           j.pickup_latitude, j.pickup_longitude, j.destination_latitude, j.destination_longitude,
           j.estimated_distance_m, j.estimated_duration_s, j.job_type
      into v_tracking_id, v_customer_id, v_partner_id, v_status, v_pickup_label, v_destination_label,
           v_pickup_lat, v_pickup_lon, v_dest_lat, v_dest_lon,
           v_trip_distance, v_trip_duration, v_job_type
    from public.delivery_jobs j
    where j.id = p_entity_id and j.customer_id = (select auth.uid()) and j.job_type = 'parcel';
    if not found then
      raise exception 'parcel not found for this customer' using errcode = '42501';
    end if;
    v_partner_role := 'delivery_partner';
  end if;

  select pp.latitude, pp.longitude, pp.updated_at
    into v_partner_lat, v_partner_lon, v_partner_updated
  from public.partner_presence pp
  where pp.user_id = v_partner_id and pp.role = v_partner_role and pp.is_online = true;

  if v_partner_updated is null or v_partner_updated < now() - interval '3 minutes' then
    v_partner_lat := null;
    v_partner_lon := null;
  end if;

  v_trip_distance := coalesce(v_trip_distance,
    public.alteo_distance_m(v_pickup_lat,v_pickup_lon,v_dest_lat,v_dest_lon));
  if v_trip_duration is null and v_trip_distance is not null then
    -- Approximate duration fallback only; the app labels it as an estimate.
    v_trip_duration := ceil(v_trip_distance::numeric / case when v_type = 'ride' then 5.5 else 4.5 end)::integer + 180;
  end if;

  if (v_type = 'ride' and v_status in ('completed','cancelled'))
     or (v_type <> 'ride' and v_status in ('delivered','cancelled','rejected')) then
    v_target_lat := null;
    v_target_lon := null;
  elsif v_type = 'ride' and v_status = 'in_progress' then
    v_target_lat := v_dest_lat; v_target_lon := v_dest_lon;
  elsif v_type <> 'ride' and v_status in ('picked_up','in_transit','out_for_delivery') then
    v_target_lat := v_dest_lat; v_target_lon := v_dest_lon;
  else
    v_target_lat := v_pickup_lat; v_target_lon := v_pickup_lon;
  end if;

  if v_partner_lat is not null and v_target_lat is not null then
    v_to_target_distance := public.alteo_distance_m(v_partner_lat,v_partner_lon,v_target_lat,v_target_lon);
    v_eta_seconds := ceil(v_to_target_distance::numeric / case when v_type = 'ride' then 5.5 else 4.5 end)::integer + 120;
  else
    v_to_target_distance := null;
    v_eta_seconds := null;
  end if;

  return jsonb_build_object(
    'entity_type',v_type,'entity_id',coalesce(v_tracking_id,p_entity_id),'status',v_status,'order_status',v_order_status,
    'pickup_label',v_pickup_label,'destination_label',v_destination_label,
    'pickup_latitude',v_pickup_lat,'pickup_longitude',v_pickup_lon,
    'destination_latitude',v_dest_lat,'destination_longitude',v_dest_lon,
    'partner_latitude',v_partner_lat,'partner_longitude',v_partner_lon,
    'partner_location_updated_at',v_partner_updated,
    'location_available',v_partner_lat is not null and v_partner_lon is not null,
    'tracking_available',v_partner_id is not null,
    'estimated_distance_m',v_trip_distance,
    'estimated_trip_duration_s',v_trip_duration,
    'distance_to_next_stop_m',v_to_target_distance,
    'eta_to_next_stop_s',v_eta_seconds,
    'next_stop',case
      when v_type = 'ride' and v_status = 'in_progress' then 'destination'
      when v_type <> 'ride' and v_status in ('picked_up','in_transit','out_for_delivery') then 'destination'
      else 'pickup'
    end,
    'message',case
      when v_partner_lat is not null then 'Live partner location updated recently.'
      when v_partner_id is not null then 'Waiting for a fresh partner location. Trip duration is approximate.'
      else 'Waiting for dispatch to assign a partner.'
    end
  );
end;
$function$
;
revoke all on function public.customer_tracking_snapshot(text,uuid) from public;
revoke all on function public.customer_tracking_snapshot(text,uuid) from anon;
grant execute on function public.customer_tracking_snapshot(text,uuid) to authenticated;
