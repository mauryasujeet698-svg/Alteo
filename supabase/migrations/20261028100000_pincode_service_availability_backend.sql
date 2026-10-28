-- PIN-code serviceability is the canonical service-area key.
-- DEFAULT remains available for global fallback rules, but checkout requires an active PIN.
CREATE OR REPLACE FUNCTION public.create_customer_order(p_items jsonb, p_delivery_address jsonb, p_idempotency_key text, p_delivery_fee_minor bigint DEFAULT 0, p_payment_method text DEFAULT 'cod'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid := auth.uid();
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_product record;
  v_seller_id uuid;
  v_kind text;
  v_subtotal bigint := 0;
  v_delivery_fee bigint;
  v_base bigint;
  v_minimum bigint;
  v_area text := upper(trim(coalesce(nullif(trim(p_delivery_address->>'postal_code'),''), nullif(trim(p_delivery_address->>'area_code'),''), '')));
  v_service_enabled boolean;
  v_order_id uuid;
  v_payment_method text := lower(trim(coalesce(p_payment_method, 'cod')));
begin
  if v_customer_id is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if v_payment_method <> 'cod' then
    raise exception 'Only cash on delivery is available right now.' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'cart must contain 1 to 50 items' using errcode = '22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  if p_delivery_fee_minor is not null and p_delivery_fee_minor < 0 then
    raise exception 'invalid delivery fee parameter' using errcode = '22023';
  end if;
  if jsonb_typeof(p_delivery_address) <> 'object'
     or coalesce(length(trim(p_delivery_address->>'recipient_name')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'phone')),0) < 8
     or coalesce(length(trim(p_delivery_address->>'address_line1')),0) < 3
     or coalesce(length(trim(p_delivery_address->>'city')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'state')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'postal_code')),0) < 5 then
    raise exception 'complete delivery address required' using errcode = '22023';
  end if;

  if (jsonb_typeof(p_delivery_address->'latitude') = 'number')
       is distinct from (jsonb_typeof(p_delivery_address->'longitude') = 'number') then
    raise exception 'both delivery coordinates are required together' using errcode = '22023';
  end if;
  if jsonb_typeof(p_delivery_address->'latitude') = 'number'
     and (p_delivery_address->>'latitude')::double precision not between -90 and 90 then
    raise exception 'invalid delivery latitude' using errcode = '22023';
  end if;
  if jsonb_typeof(p_delivery_address->'longitude') = 'number'
     and (p_delivery_address->>'longitude')::double precision not between -180 and 180 then
    raise exception 'invalid delivery longitude' using errcode = '22023';
  end if;
  if p_delivery_address ? 'latitude'
     and jsonb_typeof(p_delivery_address->'latitude') not in ('number','null') then
    raise exception 'invalid delivery latitude' using errcode = '22023';
  end if;
  if p_delivery_address ? 'longitude'
     and jsonb_typeof(p_delivery_address->'longitude') not in ('number','null') then
    raise exception 'invalid delivery longitude' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.service_areas a
    where a.pincode = v_area and a.active = true
  ) then
    raise exception 'This PIN code is not currently serviceable.' using errcode = 'P0002';
  end if;

  select id into v_order_id from public.orders
    where customer_id = v_customer_id and idempotency_key = p_idempotency_key;
  if v_order_id is not null then return v_order_id; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'invalid cart item' using errcode = '22023'; end if;
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity < 1 or v_quantity > 99 then raise exception 'quantity must be between 1 and 99' using errcode = '22023'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_items) x
      where x.value->>'product_id' = v_product_id::text
      group by x.value->>'product_id' having count(*) > 1
    ) then raise exception 'duplicate products must be combined into one cart line' using errcode = '22023'; end if;
    select p.id, p.seller_id, p.name, p.price_minor, p.kind
      into v_product
      from public.seller_products p join public.sellers s on s.id = p.seller_id
      where p.id = v_product_id and p.status = 'active' and s.status = 'approved'
      for share of p, s;
    if not found then raise exception 'an item is unavailable' using errcode = 'P0002'; end if;
    if v_seller_id is null then v_seller_id := v_product.seller_id;
    elsif v_seller_id <> v_product.seller_id then
      raise exception 'checkout currently supports one seller per order' using errcode = '22023';
    end if;
    if v_kind is null then v_kind := v_product.kind;
    elsif v_kind <> v_product.kind then raise exception 'separate service categories into different orders' using errcode = '22023';
    end if;
    v_subtotal := v_subtotal + (v_product.price_minor * v_quantity);
  end loop;
  if v_subtotal > 1000000000 then raise exception 'cart total exceeds allowed limit' using errcode = '22023'; end if;

  select sc.enabled into v_service_enabled
    from public.service_controls sc
    where sc.service = v_kind and sc.area_code = v_area
    limit 1;
  if not found then
    select sc.enabled into v_service_enabled
      from public.service_controls sc
      where sc.service = v_kind and sc.area_code = 'DEFAULT'
      limit 1;
  end if;
  if not coalesce(v_service_enabled, false) then
    raise exception 'This service is not available for your PIN code yet.' using errcode = 'P0002';
  end if;
  select base_fee_minor, minimum_fee_minor into v_base, v_minimum
    from public.pricing_rules
    where service = v_kind and active = true and city_code = v_area
    limit 1;
  if not found then
    select base_fee_minor, minimum_fee_minor into v_base, v_minimum
      from public.pricing_rules
      where service = v_kind and active = true and city_code = 'DEFAULT'
      limit 1;
  end if;
  if not found then raise exception 'Pricing is not configured for this service yet.' using errcode = 'P0002'; end if;
  v_delivery_fee := greatest(v_base, v_minimum);

  insert into public.orders(customer_id,seller_id,idempotency_key,status,payment_status,payment_method,subtotal_minor,delivery_fee_minor,total_minor,delivery_address_snapshot)
  values (v_customer_id,v_seller_id,p_idempotency_key,'cod_pending','cod_pending',v_payment_method,v_subtotal,v_delivery_fee,v_subtotal+v_delivery_fee,p_delivery_address)
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    select p.id, p.name, p.price_minor into v_product
      from public.seller_products p join public.sellers s on s.id = p.seller_id
      where p.id = v_product_id and p.status = 'active' and s.status = 'approved'
      for share of p, s;
    if not found then raise exception 'an item became unavailable' using errcode = 'P0002'; end if;
    insert into public.order_items(order_id,product_id,product_name_snapshot,quantity,unit_price_minor,line_total_minor)
    values (v_order_id,v_product.id,v_product.name,v_quantity,v_product.price_minor,v_product.price_minor*v_quantity);
  end loop;
  insert into public.order_events(order_id,actor_id,action,detail)
    values (v_order_id,v_customer_id,'order.created',jsonb_build_object('payment_status','cod_pending','payment_method',v_payment_method,'service',v_kind));
  return v_order_id;
exception when unique_violation then
  select id into v_order_id from public.orders where customer_id=auth.uid() and idempotency_key=p_idempotency_key;
  if v_order_id is not null then return v_order_id; end if;
  raise;
end;
$function$;
 
CREATE OR REPLACE FUNCTION public.quote_customer_ride(p_pickup_latitude double precision, p_pickup_longitude double precision, p_destination_latitude double precision, p_destination_longitude double precision, p_area_code text, p_vehicle_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_area text := upper(trim(coalesce(nullif(trim(p_area_code),''),'DEFAULT')));
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

  if v_area <> 'DEFAULT' and not exists (
    select 1 from public.service_areas a where a.pincode = v_area and a.active = true
  ) then
    return jsonb_build_object('enabled',false,'message','This pickup PIN code is not currently serviceable.');
  end if;
  select sc.enabled into v_enabled
    from public.service_controls sc
    where sc.service='ride' and sc.area_code = v_area
    limit 1;
  if not found then
    select sc.enabled into v_enabled
      from public.service_controls sc
      where sc.service='ride' and sc.area_code = 'DEFAULT'
      limit 1;
  end if;
  if not coalesce(v_enabled,false) then
    return jsonb_build_object('enabled',false,'message','Rides are not enabled for this PIN code yet.');
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
    where service='ride' and active=true and city_code = v_area
    limit 1;
  if not found then
    select base_fee_minor,per_km_minor,minimum_fee_minor into v_base,v_per_km,v_minimum
      from public.pricing_rules
      where service='ride' and active=true and city_code = 'DEFAULT'
      limit 1;
  end if;
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
 
CREATE OR REPLACE FUNCTION public.admin_set_service_control(p_area_code text, p_service text, p_enabled boolean, p_automatic_assignment boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
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
  insert into public.service_controls(area_code,service,enabled,automatic_assignment,updated_by,updated_at)
  values(v_area,p_service,coalesce(p_enabled,false),coalesce(p_automatic_assignment,false),(select auth.uid()),now())
  on conflict(area_code,service) do update set enabled=excluded.enabled,
    automatic_assignment=excluded.automatic_assignment,updated_by=excluded.updated_by,updated_at=now();
  insert into public.audit_events(actor_id,action,entity_type,metadata)
    values((select auth.uid()),'service.control_changed','service_control',
      jsonb_build_object('area_code',v_area,'service',p_service,'enabled',p_enabled,'automatic_assignment',p_automatic_assignment));
  if coalesce(p_enabled,false) and coalesce(p_automatic_assignment,false) then
    if p_service = 'ride' then perform private.dispatch_pending_rides(v_area); end if;
    perform private.dispatch_pending_deliveries(v_area);
  end if;
end;
$function$;
