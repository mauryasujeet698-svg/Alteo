-- Make dark-store PIN/stock coverage effective in the customer catalogue and checkout.
create or replace function public.get_public_inventory_availability(p_pincode text)
returns table(product_id uuid, inventory_managed boolean, available boolean)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.id,
    exists (
      select 1 from public.dark_store_inventory di
      where di.product_id = p.id
    ) as inventory_managed,
    exists (
      select 1
      from public.dark_store_inventory di
      join public.dark_stores ds on ds.id = di.store_id and ds.status = 'active'
      where di.product_id = p.id
        and di.stock_on_hand > di.reserved_quantity
        and (di.availability_mode = 'all'
          or trim(coalesce(p_pincode,'')) = any(coalesce(di.available_pincodes, array[]::text[])))
    ) as available
  from public.seller_products p
  where p.status = 'active'
    and p.kind = 'quick'
    and trim(coalesce(p_pincode,'')) ~ '^[1-9][0-9]{5}$'
    and (
      not exists (select 1 from public.service_areas)
      or exists (select 1 from public.service_areas a where a.pincode = trim(p_pincode) and a.active = true)
    );
$function$;
revoke all on function public.get_public_inventory_availability(text) from public;
grant execute on function public.get_public_inventory_availability(text) to anon, authenticated;

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
    if v_product.kind = 'quick'
       and exists (select 1 from public.dark_store_inventory di where di.product_id = v_product.id)
       and not exists (
         select 1
         from public.dark_store_inventory di
         join public.dark_stores ds on ds.id = di.store_id and ds.status = 'active'
         where di.product_id = v_product.id
           and di.stock_on_hand > di.reserved_quantity
           and (di.availability_mode = 'all'
             or v_area = any(coalesce(di.available_pincodes, array[]::text[])))
       ) then
      raise exception 'This quick-commerce item is not stocked for the selected PIN code.' using errcode = 'P0002';
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
