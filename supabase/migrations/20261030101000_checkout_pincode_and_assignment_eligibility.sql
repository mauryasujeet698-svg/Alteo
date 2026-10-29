-- Validate catalogue PIN coverage during checkout and prevent assigning jobs to busy/stale/off-area partners.

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
  v_area_enabled boolean;
  v_global_enabled boolean;
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

  -- Keep the legacy DEFAULT-area path until the owner registers a first PIN.
  if exists (select 1 from public.service_areas) then
    if v_area !~ '^[1-9][0-9]{5}$' or not exists (
      select 1 from public.service_areas a where a.pincode = v_area and a.active = true
    ) then
      raise exception 'This PIN code is not currently serviceable.' using errcode = 'P0002';
    end if;
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
    select p.id, p.seller_id, p.name, p.price_minor, p.kind, p.availability_mode, p.available_pincodes
      into v_product
      from public.seller_products p join public.sellers s on s.id = p.seller_id
      where p.id = v_product_id and p.status = 'active' and s.status = 'approved'
      for share of p, s;
    if not found then raise exception 'an item is unavailable' using errcode = 'P0002'; end if;
    if v_product.availability_mode = 'specific'
       and not (v_area = any(coalesce(v_product.available_pincodes, array[]::text[]))) then
      raise exception 'An item is not available for the selected delivery PIN code.' using errcode = 'P0002';
    end if;
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

  if exists (select 1 from public.service_areas) then
    select sc.enabled into v_global_enabled
      from public.service_controls sc
      where sc.service = v_kind and sc.area_code = 'DEFAULT'
      limit 1;
    if not coalesce(v_global_enabled, false) then
      raise exception 'This service is temporarily unavailable.' using errcode = 'P0002';
    end if;
    select sc.enabled into v_area_enabled
      from public.service_controls sc
      where sc.service = v_kind and sc.area_code = v_area
      limit 1;
    if found and not coalesce(v_area_enabled, false) then
      raise exception 'This service is not available for your PIN code yet.' using errcode = 'P0002';
    end if;
  else
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



revoke all on function public.create_customer_order(jsonb,jsonb,text,bigint,text) from public, anon;
grant execute on function public.create_customer_order(jsonb,jsonb,text,bigint,text) to authenticated;


CREATE OR REPLACE FUNCTION public.admin_assign_delivery_partner(p_delivery_job_id uuid, p_partner_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.delivery_jobs%rowtype;
  v_payment_status text;
  v_order_status text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode='42501';
  end if;
  if not exists(select 1 from public.user_roles ur where ur.user_id=p_partner_id and ur.role='delivery_partner') then
    raise exception 'user is not an approved delivery partner' using errcode='42501';
  end if;
  select * into v_job from public.delivery_jobs where id=p_delivery_job_id for update;
  if not found then raise exception 'delivery job not found' using errcode='P0002'; end if;
  if v_job.status in ('delivered','cancelled','failed') then raise exception 'cannot assign a closed delivery job' using errcode='22023'; end if;
  if not exists (
    select 1 from public.partner_presence pp
    where pp.user_id = p_partner_id and pp.role = 'delivery_partner'
      and pp.is_online = true and pp.updated_at > now() - interval '10 minutes'
      and pp.area_code in (v_job.area_code, 'DEFAULT')
  ) then
    raise exception 'Delivery partner is offline, has stale location, or is outside this service area.' using errcode='22023';
  end if;
  if exists (
    select 1 from public.delivery_jobs active
    where active.delivery_partner_id = p_partner_id and active.id <> p_delivery_job_id
      and active.status in ('assigned','accepted','picked_up','in_transit')
  ) then
    raise exception 'Delivery partner already has an active delivery.' using errcode='22023';
  end if;
  if v_job.order_id is not null then
    select payment_status,status into v_payment_status,v_order_status from public.orders where id=v_job.order_id;
    if v_payment_status not in ('paid','cod_pending') then raise exception 'order payment method is not available for dispatch' using errcode='22023'; end if;
    if v_order_status <> 'ready_for_pickup' then raise exception 'seller must mark order ready before dispatch' using errcode='22023'; end if;
  end if;
  update public.delivery_assignments set status='revoked',updated_at=now()
    where delivery_job_id=p_delivery_job_id and status in ('offered','accepted');
  update public.delivery_jobs set delivery_partner_id=p_partner_id,status='assigned',updated_at=now()
    where id=p_delivery_job_id;
  insert into public.delivery_assignments(delivery_job_id,partner_id,assigned_by,status)
    values(p_delivery_job_id,p_partner_id,(select auth.uid()),'offered');
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'delivery.partner_assigned','delivery_job',p_delivery_job_id,
      jsonb_build_object('partner_id',p_partner_id,'assigned_manually',true));
end;
$function$;



revoke all on function public.admin_assign_delivery_partner(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_delivery_partner(uuid,uuid) to authenticated;


CREATE OR REPLACE FUNCTION public.admin_assign_driver(p_ride_id uuid, p_driver_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_status text;
  v_area text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.user_roles ur where ur.user_id = p_driver_id and ur.role = 'driver_partner') then
    raise exception 'user is not an approved driver' using errcode = '42501';
  end if;
  select status, area_code into v_status, v_area from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride not found' using errcode = 'P0002'; end if;
  if v_status not in ('requested','accepted') then
    raise exception 'ride is no longer assignable' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.partner_presence pp
    where pp.user_id = p_driver_id and pp.role = 'driver_partner'
      and pp.is_online = true and pp.updated_at > now() - interval '10 minutes'
      and pp.area_code in (v_area, 'DEFAULT')
  ) then
    raise exception 'Driver is offline, has stale location, or is outside this service area.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.rides active
    where active.driver_id = p_driver_id and active.id <> p_ride_id
      and active.status in ('requested','accepted','arrived','in_progress')
  ) then
    raise exception 'Driver already has an active ride.' using errcode = '22023';
  end if;
  update public.rides set driver_id = p_driver_id, updated_at = now() where id = p_ride_id;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'ride.driver_assigned', 'ride', p_ride_id,
      jsonb_build_object('driver_id', p_driver_id, 'assigned_manually', true));
end;
$function$;



revoke all on function public.admin_assign_driver(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_driver(uuid,uuid) to authenticated;


CREATE OR REPLACE FUNCTION private.dispatch_pending_deliveries(p_area_code text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job record;
  v_area text;
  v_service text;
  v_enabled boolean;
  v_auto boolean;
  v_partner uuid;
  v_count integer := 0;
begin
  for v_job in
    select dj.id, dj.area_code, dj.job_type, dj.order_id, dj.pickup_latitude, dj.pickup_longitude
    from public.delivery_jobs dj
    left join public.orders o on o.id = dj.order_id
    where dj.delivery_partner_id is null and dj.status = 'pending'
      and (p_area_code is null or dj.area_code in (upper(trim(p_area_code)), 'DEFAULT'))
      and (
        (dj.job_type = 'parcel' and dj.order_id is null)
        or (dj.order_id is not null and o.payment_status in ('paid','cod_pending') and o.status = 'ready_for_pickup')
      )
    order by dj.created_at
    limit 100
    for update of dj skip locked
  loop
    v_area := coalesce(nullif(upper(trim(v_job.area_code)), ''), 'DEFAULT');
    if v_job.job_type = 'parcel' then
      v_service := 'parcel';
    else
      select p.kind into v_service
      from public.order_items oi
      join public.seller_products p on p.id = oi.product_id
      where oi.order_id = v_job.order_id
      order by oi.created_at
      limit 1;
      if v_service is null then continue; end if;
    end if;

    select sc.enabled, sc.automatic_assignment into v_enabled, v_auto
    from public.service_controls sc
    where sc.service = v_service and sc.area_code in (v_area, 'DEFAULT')
    order by case when sc.area_code = v_area then 0 else 1 end
    limit 1;
    if not coalesce(v_enabled, false) or not coalesce(v_auto, false) then continue; end if;

    v_partner := null;
    select pp.user_id into v_partner
    from public.partner_presence pp
    join public.user_roles ur on ur.user_id = pp.user_id and ur.role = 'delivery_partner'
    where pp.role = 'delivery_partner' and pp.is_online
      and pp.updated_at > now() - interval '10 minutes'
      and pp.area_code in (v_area, 'DEFAULT')
      and not exists (
        select 1 from public.delivery_jobs active
        where active.delivery_partner_id = pp.user_id and active.status in ('assigned','picked_up','in_transit')
      )
      and not exists (
        select 1 from public.delivery_assignments prev
        where prev.delivery_job_id = v_job.id and prev.partner_id = pp.user_id and prev.status = 'rejected'
      )
    order by
      case when pp.area_code = v_area then 0 else 1 end,
      case when pp.latitude is not null and v_job.pickup_latitude is not null then
        power(pp.latitude - v_job.pickup_latitude, 2) + power(pp.longitude - v_job.pickup_longitude, 2)
      else 999999 end,
      pp.updated_at asc
    limit 1
    for update of pp skip locked;

    if v_partner is not null then
      update public.delivery_jobs set delivery_partner_id = v_partner, status = 'assigned',
        auto_assigned_at = now(), updated_at = now() where id = v_job.id;
      insert into public.delivery_assignments(delivery_job_id, partner_id, assigned_by, status)
        values (v_job.id, v_partner, null, 'offered');
      insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
        values (null, 'delivery.auto_assigned', 'delivery_job', v_job.id,
          jsonb_build_object('partner_id', v_partner, 'service', v_service, 'area_code', v_area));
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;



revoke all on function private.dispatch_pending_deliveries(text) from public, anon, authenticated;


CREATE OR REPLACE FUNCTION private.dispatch_pending_rides(p_area_code text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ride record;
  v_control_enabled boolean;
  v_auto boolean;
  v_partner uuid;
  v_count integer := 0;
begin
  for v_ride in
    select r.id, r.area_code, r.pickup_latitude, r.pickup_longitude
    from public.rides r
    where r.driver_id is null and r.status = 'requested'
      and (p_area_code is null or r.area_code in (upper(trim(p_area_code)), 'DEFAULT'))
    order by r.created_at
    limit 100
    for update of r skip locked
  loop
    select sc.enabled, sc.automatic_assignment into v_control_enabled, v_auto
    from public.service_controls sc
    where sc.service='ride' and sc.area_code in (v_ride.area_code,'DEFAULT')
    order by case when sc.area_code=v_ride.area_code then 0 else 1 end
    limit 1;
    if not coalesce(v_control_enabled,false) or not coalesce(v_auto,false) then continue; end if;

    v_partner := null;
    select pp.user_id into v_partner
    from public.partner_presence pp
    join public.user_roles ur on ur.user_id=pp.user_id and ur.role='driver_partner'
    where pp.role='driver_partner' and pp.is_online
      and pp.updated_at > now() - interval '10 minutes'
      and pp.area_code in (v_ride.area_code,'DEFAULT')
      and not exists (
        select 1 from public.rides active
        where active.driver_id=pp.user_id and active.status in ('requested','accepted','arrived','in_progress')
      )
    order by
      case when pp.area_code=v_ride.area_code then 0 else 1 end,
      case when pp.latitude is not null then
        power(pp.latitude-v_ride.pickup_latitude,2)+power(pp.longitude-v_ride.pickup_longitude,2)
      else 999999 end,
      pp.updated_at asc
    limit 1
    for update of pp skip locked;

    if v_partner is not null then
      update public.rides set driver_id=v_partner,auto_assigned_at=now(),updated_at=now() where id=v_ride.id;
      insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
        values(null,'ride.auto_assigned','ride',v_ride.id,jsonb_build_object('driver_id',v_partner,'area_code',v_ride.area_code));
      v_count:=v_count+1;
    end if;
  end loop;
  return v_count;
end;
$function$;



revoke all on function private.dispatch_pending_rides(text) from public, anon, authenticated;
