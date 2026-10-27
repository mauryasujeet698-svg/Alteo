-- Cash on delivery is the only checkout method enabled in this release.

-- COD remains unpaid until the delivery partner confirms cash collection.

alter table public.orders add column if not exists payment_method text;

alter table public.orders alter column payment_method set default 'cod';

alter table public.orders drop constraint if exists orders_payment_method_check;

alter table public.orders add constraint orders_payment_method_check check (payment_method is null or payment_method in ('cod','upi','card','wallet','netbanking'));

alter table public.orders drop constraint if exists orders_payment_status_check;

alter table public.orders add constraint orders_payment_status_check check (payment_status = any (array['pending','authorized','paid','failed','refund_pending','refunded','cod_pending']));

alter table public.orders drop constraint if exists orders_status_check;

alter table public.orders add constraint orders_status_check check (status = any (array['pending_payment','cod_pending','paid','accepted','preparing','ready_for_pickup','out_for_delivery','completed','cancelled','refund_pending','refunded']));

drop function if exists public.create_customer_order(jsonb,jsonb,text,bigint);

CREATE FUNCTION public.create_customer_order(p_items jsonb, p_delivery_address jsonb, p_idempotency_key text, p_delivery_fee_minor bigint DEFAULT 0, p_payment_method text DEFAULT 'cod')
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
  v_area text := upper(trim(coalesce(p_delivery_address->>'area_code','DEFAULT')));
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

  if not exists (select 1 from public.service_controls sc where sc.service = v_kind and sc.enabled = true and sc.area_code in (v_area,'DEFAULT')) then
    raise exception 'checkout is not enabled for this service area yet' using errcode = 'P0002';
  end if;
  select base_fee_minor, minimum_fee_minor into v_base, v_minimum
    from public.pricing_rules
    where service = v_kind and active = true and city_code in (v_area,'DEFAULT')
    order by case when city_code = v_area then 0 else 1 end limit 1;
  if not found then raise exception 'checkout is not enabled for this service area yet' using errcode = 'P0002'; end if;
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

revoke all on function public.create_customer_order(jsonb,jsonb,text,bigint,text) from public;

revoke all on function public.create_customer_order(jsonb,jsonb,text,bigint,text) from anon;

grant execute on function public.create_customer_order(jsonb,jsonb,text,bigint,text) to authenticated;

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

CREATE OR REPLACE FUNCTION public.admin_assign_order_to_dark_store(p_order_id uuid, p_store_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task_id uuid;
  v_order_status text;
  v_payment_status text;
  v_store_status text;
begin
  if auth.uid() is null or not private.has_role('admin'::text) then
    raise exception 'admin role required' using errcode = '42501';
  end if;

  select status, payment_status into v_order_status, v_payment_status
    from public.orders where id = p_order_id for update;
  if not found then raise exception 'order not found' using errcode = 'P0002'; end if;
  if v_payment_status not in ('paid','cod_pending') or v_order_status not in ('paid','cod_pending') then
    raise exception 'only newly paid orders can be assigned to a dark store' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.order_items oi
    join public.seller_products p on p.id = oi.product_id
    where oi.order_id = p_order_id
      and p.kind = 'quick'
  ) or exists (
    select 1 from public.order_items oi
    join public.seller_products p on p.id = oi.product_id
    where oi.order_id = p_order_id
      and p.kind <> 'quick'
  ) then
    raise exception 'dark stores can only fulfil orders containing quick-commerce items' using errcode = '22023';
  end if;

  select status into v_store_status from public.dark_stores where id = p_store_id;
  if not found or v_store_status <> 'active' then
    raise exception 'choose an active dark store' using errcode = '22023';
  end if;

  if exists (select 1 from public.dark_store_tasks where order_id = p_order_id and status = 'handed_over') then
    raise exception 'this order has already been handed over' using errcode = '22023';
  end if;

  insert into public.dark_store_tasks(order_id, store_id, status, assigned_by, updated_at)
  values(p_order_id, p_store_id, 'assigned', auth.uid(), now())
  on conflict (order_id) do update
    set store_id = excluded.store_id,
        status = 'assigned',
        assigned_by = auth.uid(),
        accepted_at = null,
        picking_started_at = null,
        packed_at = null,
        handed_over_at = null,
        updated_at = now()
  returning id into v_task_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'dark_store.task_assigned', 'dark_store_task', v_task_id,
    jsonb_build_object('order_id', p_order_id, 'store_id', p_store_id, 'fulfilment_kind', 'quick'));
  return v_task_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.dark_store_update_task(p_task_id uuid, p_action text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task public.dark_store_tasks%rowtype;
  v_next text;
  v_payment_status text;
begin
  if auth.uid() is null then raise exception 'sign-in required' using errcode = '42501'; end if;

  select dst.* into v_task
    from public.dark_store_tasks dst
    join public.dark_stores ds on ds.id = dst.store_id
    where dst.id = p_task_id and ds.owner_user_id = auth.uid() and ds.status = 'active'
    for update of dst;
  if not found then raise exception 'task not found for this active dark store' using errcode = '42501'; end if;

  if p_action = 'accept' and v_task.status = 'assigned' then
    v_next := 'accepted';
  elsif p_action = 'start_picking' and v_task.status = 'accepted' then
    v_next := 'picking';
  elsif p_action = 'packed' and v_task.status = 'picking' then
    v_next := 'packed';
  elsif p_action = 'handed_over' and v_task.status = 'packed' then
    v_next := 'handed_over';
    select payment_status into v_payment_status from public.orders where id = v_task.order_id for update;
    if not found or v_payment_status not in ('paid','cod_pending') then
      raise exception 'order payment must be confirmed before handover' using errcode = '22023';
    end if;
  else
    raise exception 'invalid task action for current status' using errcode = '22023';
  end if;

  update public.dark_store_tasks set
    status = v_next,
    accepted_at = case when v_next = 'accepted' then now() else accepted_at end,
    picking_started_at = case when v_next = 'picking' then now() else picking_started_at end,
    packed_at = case when v_next = 'packed' then now() else packed_at end,
    handed_over_at = case when v_next = 'handed_over' then now() else handed_over_at end,
    updated_at = now()
  where id = p_task_id;

  if v_next = 'handed_over' then
    update public.orders
      set status = 'ready_for_pickup', updated_at = now()
      where id = v_task.order_id and payment_status in ('paid','cod_pending')
        and status in ('paid', 'cod_pending', 'ready_for_pickup');
    if not found then
      raise exception 'order is not in a valid state for dark-store handover' using errcode = '22023';
    end if;
    -- The existing order-update trigger dispatches the existing delivery job,
    -- respecting DEFAULT service controls and manual/automatic assignment settings.
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'dark_store.task_' || v_next, 'dark_store_task', p_task_id,
    jsonb_build_object('order_id', v_task.order_id, 'store_id', v_task.store_id));
  return v_next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.seller_update_order_status(p_order_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order public.orders%rowtype;
  v_next_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;

  select o.* into v_order
    from public.orders o
    join public.sellers s on s.id = o.seller_id
    where o.id = p_order_id and s.owner_id = (select auth.uid()) and s.status = 'approved'
    for update of o;
  if not found then
    raise exception 'order not found for this approved seller' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.dark_store_tasks dst
    where dst.order_id = p_order_id and dst.status <> 'cancelled'
  ) then
    raise exception 'this quick-commerce order is assigned to a dark store; seller fulfilment is disabled' using errcode = '22023';
  end if;

  if v_order.payment_status not in ('paid','cod_pending') then
    raise exception 'payment must be confirmed before processing' using errcode = '22023';
  end if;
  if p_action = 'accept' and v_order.status in ('paid','cod_pending') then
    v_next_status := 'accepted';
  elsif p_action = 'prepare' and v_order.status = 'accepted' then
    v_next_status := 'preparing';
  elsif p_action = 'ready' and v_order.status = 'preparing' then
    v_next_status := 'ready_for_pickup';
  else
    raise exception 'order action is not allowed in its current state' using errcode = '22023';
  end if;

  update public.orders set status = v_next_status, updated_at = now() where id = p_order_id;
  insert into public.order_events(order_id, actor_id, action, detail)
    values (p_order_id, (select auth.uid()), 'seller.' || p_action,
      jsonb_build_object('status_before', v_order.status, 'status_after', v_next_status));
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'seller.order_' || p_action, 'order', p_order_id,
      jsonb_build_object('status_before', v_order.status, 'status_after', v_next_status));
end;
$function$;

CREATE OR REPLACE FUNCTION public.partner_update_delivery_status(p_delivery_job_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.delivery_jobs%rowtype;
  v_order_payment text;
  v_order_method text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;

  select * into v_job
    from public.delivery_jobs
    where id = p_delivery_job_id
    for update;
  if not found or v_job.delivery_partner_id <> (select auth.uid()) then
    raise exception 'this delivery is not assigned to you' using errcode = '42501';
  end if;

  if p_action = 'accept' then
    update public.delivery_assignments
      set status = 'accepted', updated_at = now()
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'offered';
    if not found then raise exception 'no pending offer found' using errcode = '22023'; end if;

    update public.delivery_jobs
      set status = 'accepted', updated_at = now()
      where id = p_delivery_job_id and status = 'assigned';
    if not found then raise exception 'delivery is not in the assigned state' using errcode = '22023'; end if;

  elsif p_action = 'reject' then
    update public.delivery_assignments
      set status = 'rejected', updated_at = now()
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status in ('offered', 'accepted');
    update public.delivery_jobs
      set delivery_partner_id = null, status = 'pending', updated_at = now()
      where id = p_delivery_job_id;

  elsif p_action = 'picked_up' then
    if not exists (
      select 1 from public.delivery_assignments
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'accepted'
    ) then
      raise exception 'accept the assignment first' using errcode = '22023';
    end if;
    if v_job.status not in ('accepted', 'assigned') then
      raise exception 'delivery must be accepted before pickup' using errcode = '22023';
    end if;
    if v_job.order_id is not null then
      select payment_status, payment_method into v_order_payment, v_order_method from public.orders where id = v_job.order_id;
      if v_order_payment not in ('paid','cod_pending') then
        raise exception 'order payment is not confirmed' using errcode = '22023';
      end if;
    end if;
    update public.delivery_jobs set status = 'picked_up', updated_at = now() where id = p_delivery_job_id;
    if v_job.order_id is not null then
      update public.orders set status = 'out_for_delivery', updated_at = now() where id = v_job.order_id;
    end if;

  elsif p_action = 'in_transit' then
    if v_job.status <> 'picked_up' then
      raise exception 'item must be picked up first' using errcode = '22023';
    end if;
    update public.delivery_jobs set status = 'in_transit', updated_at = now() where id = p_delivery_job_id;

  elsif p_action in ('delivered', 'delivered_cod_collected') then
    if v_job.status <> 'in_transit' then
      raise exception 'delivery must be in transit first' using errcode = '22023';
    end if;

    if v_job.order_id is not null then
      select payment_status, payment_method into v_order_payment, v_order_method
      from public.orders where id = v_job.order_id for update;

      if v_order_method = 'cod' and v_order_payment = 'cod_pending' then
        if p_action <> 'delivered_cod_collected' then
          raise exception 'Confirm cash collection before completing this COD delivery.' using errcode = '22023';
        end if;
        update public.orders set status = 'completed', payment_status = 'paid', updated_at = now()
        where id = v_job.order_id and payment_status = 'cod_pending' and payment_method = 'cod';
        if not found then raise exception 'COD payment could not be confirmed.' using errcode = '22023'; end if;
      elsif v_order_payment = 'paid' then
        update public.orders set status = 'completed', updated_at = now()
        where id = v_job.order_id and payment_status = 'paid';
      else
        raise exception 'Payment must be confirmed before completing this order.' using errcode = '22023';
      end if;
    end if;

    update public.delivery_jobs set status = 'delivered', updated_at = now() where id = p_delivery_job_id;
    update public.delivery_assignments set status = 'completed', updated_at = now()
    where delivery_job_id = p_delivery_job_id and partner_id = (select auth.uid()) and status = 'accepted';
  else
    raise exception 'invalid delivery action' using errcode = '22023';
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'delivery.' || p_action, 'delivery_job', p_delivery_job_id,
    jsonb_build_object('status_before', v_job.status, 'action', p_action));
end;
$function$;

create or replace function public.admin_set_support_ticket_status(p_ticket_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $function$ begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then raise exception 'administrator role required' using errcode = '42501'; end if;
  if p_status not in ('open','in_progress','resolved','closed') then raise exception 'invalid support ticket status' using errcode = '22023'; end if;
  update public.support_tickets set status = p_status, updated_at = now() where id = p_ticket_id;
  if not found then raise exception 'support ticket not found' using errcode = 'P0002'; end if;
end; $function$;
revoke all on function public.admin_set_support_ticket_status(uuid,text) from public;
revoke all on function public.admin_set_support_ticket_status(uuid,text) from anon;
grant execute on function public.admin_set_support_ticket_status(uuid,text) to authenticated;
