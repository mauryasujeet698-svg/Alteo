-- Support customer cancellation of individual COD order lines before dispatch,
-- partner cancellation of an accepted delivery before pickup, and accepted jobs
-- as a first-class delivery state.
alter table public.order_items
  add column if not exists status text not null default 'active',
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.order_items'::regclass
      and conname = 'order_items_status_check'
  ) then
    alter table public.order_items
      add constraint order_items_status_check
      check (status in ('active', 'cancelled')) not valid;
  end if;
end
$$;

alter table public.order_items validate constraint order_items_status_check;

alter table public.delivery_jobs
  drop constraint if exists delivery_jobs_status_check;

alter table public.delivery_jobs
  add constraint delivery_jobs_status_check
  check (status in ('pending', 'assigned', 'accepted', 'picked_up', 'in_transit', 'delivered', 'cancelled', 'failed'))
  not valid;

alter table public.delivery_jobs validate constraint delivery_jobs_status_check;

create or replace function public.customer_cancel_order_item(
  p_order_item_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_item public.order_items%rowtype;
  v_remaining integer;
  v_subtotal bigint;
  v_reason text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;

  select o.* into v_order
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  where oi.id = p_order_item_id
    and o.customer_id = (select auth.uid())
  for update of o;

  if not found then
    raise exception 'order item was not found for this customer' using errcode = '42501';
  end if;

  select oi.* into v_item
  from public.order_items oi
  where oi.id = p_order_item_id
    and oi.order_id = v_order.id
  for update;

  if not found or v_item.status <> 'active' then
    raise exception 'this item is already cancelled or unavailable' using errcode = '22023';
  end if;

  if v_order.status not in ('cod_pending', 'accepted', 'preparing', 'ready_for_pickup') then
    raise exception 'items can only be cancelled before the order is out for delivery' using errcode = '22023';
  end if;

  if v_order.payment_method <> 'cod' or v_order.payment_status <> 'cod_pending' then
    raise exception 'this payment type needs Admin support to arrange a refund' using errcode = '22023';
  end if;

  v_reason := nullif(left(trim(coalesce(p_reason, '')), 500), '');

  update public.order_items
  set status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason = v_reason
  where id = p_order_item_id
    and status = 'active';

  if not found then
    raise exception 'item cancellation could not be completed' using errcode = '22023';
  end if;

  select count(*)::integer, coalesce(sum(oi.line_total_minor), 0)::bigint
  into v_remaining, v_subtotal
  from public.order_items oi
  where oi.order_id = v_order.id
    and oi.status = 'active';

  if v_remaining = 0 then
    update public.orders
    set status = 'cancelled',
        subtotal_minor = 0,
        delivery_fee_minor = 0,
        total_minor = 0,
        updated_at = now()
    where id = v_order.id;

    update public.delivery_assignments
    set status = 'revoked', updated_at = now()
    where delivery_job_id in (
      select dj.id from public.delivery_jobs dj where dj.order_id = v_order.id
    )
      and status in ('offered', 'accepted');

    update public.delivery_jobs
    set status = 'cancelled',
        delivery_partner_id = null,
        updated_at = now()
    where order_id = v_order.id
      and status in ('pending', 'assigned', 'accepted');
  else
    update public.orders
    set subtotal_minor = v_subtotal,
        total_minor = v_subtotal + delivery_fee_minor,
        updated_at = now()
    where id = v_order.id;
  end if;

  insert into public.order_events(order_id, actor_id, action, detail)
  values (
    v_order.id,
    (select auth.uid()),
    'order.item_cancelled',
    jsonb_build_object(
      'order_item_id', p_order_item_id,
      'remaining_items', v_remaining,
      'remaining_subtotal_minor', v_subtotal,
      'reason', v_reason
    )
  );

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    (select auth.uid()),
    'customer.order_item_cancelled',
    'order_item',
    p_order_item_id,
    jsonb_build_object('order_id', v_order.id, 'remaining_items', v_remaining)
  );
end;
$function$;

revoke all on function public.customer_cancel_order_item(uuid, text) from public, anon;
grant execute on function public.customer_cancel_order_item(uuid, text) to authenticated;

create or replace function public.partner_update_delivery_status(
  p_delivery_job_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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
    if not found then
      raise exception 'no pending offer found' using errcode = '22023';
    end if;

    update public.delivery_jobs
    set status = 'accepted', updated_at = now()
    where id = p_delivery_job_id and status = 'assigned';
    if not found then
      raise exception 'delivery is not in the assigned state' using errcode = '22023';
    end if;

  elsif p_action = 'reject' then
    if v_job.status <> 'assigned' then
      raise exception 'only a new delivery offer can be declined' using errcode = '22023';
    end if;

    update public.delivery_assignments
    set status = 'rejected', updated_at = now()
    where delivery_job_id = p_delivery_job_id
      and partner_id = (select auth.uid())
      and status = 'offered';
    if not found then
      raise exception 'no pending offer found' using errcode = '22023';
    end if;

    update public.delivery_jobs
    set delivery_partner_id = null, status = 'pending', updated_at = now()
    where id = p_delivery_job_id;

  elsif p_action = 'cancel' then
    if v_job.status <> 'accepted' then
      raise exception 'a delivery can only be cancelled before pickup' using errcode = '22023';
    end if;

    update public.delivery_assignments
    set status = 'rejected', updated_at = now()
    where delivery_job_id = p_delivery_job_id
      and partner_id = (select auth.uid())
      and status = 'accepted';
    if not found then
      raise exception 'accepted delivery assignment was not found' using errcode = '22023';
    end if;

    update public.delivery_jobs
    set delivery_partner_id = null, status = 'pending', updated_at = now()
    where id = p_delivery_job_id and status = 'accepted';

  elsif p_action = 'picked_up' then
    if not exists (
      select 1 from public.delivery_assignments
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'accepted'
    ) then
      raise exception 'accept the assignment first' using errcode = '22023';
    end if;

    if v_job.status <> 'accepted' then
      raise exception 'delivery must be accepted before pickup' using errcode = '22023';
    end if;

    if v_job.order_id is not null then
      select payment_status, payment_method
      into v_order_payment, v_order_method
      from public.orders
      where id = v_job.order_id
      for update;

      if v_order_payment not in ('paid', 'cod_pending') then
        raise exception 'order payment is not confirmed' using errcode = '22023';
      end if;
    end if;

    update public.delivery_jobs
    set status = 'picked_up', updated_at = now()
    where id = p_delivery_job_id;

    if v_job.order_id is not null then
      update public.orders
      set status = 'out_for_delivery', updated_at = now()
      where id = v_job.order_id;
    end if;

  elsif p_action = 'in_transit' then
    if v_job.status <> 'picked_up' then
      raise exception 'item must be picked up first' using errcode = '22023';
    end if;

    update public.delivery_jobs
    set status = 'in_transit', updated_at = now()
    where id = p_delivery_job_id;

  elsif p_action in ('delivered', 'delivered_cod_collected') then
    if v_job.status <> 'in_transit' then
      raise exception 'delivery must be in transit first' using errcode = '22023';
    end if;

    if v_job.order_id is not null then
      select payment_status, payment_method
      into v_order_payment, v_order_method
      from public.orders
      where id = v_job.order_id
      for update;

      if v_order_method = 'cod' and v_order_payment = 'cod_pending' then
        if p_action <> 'delivered_cod_collected' then
          raise exception 'Confirm cash collection before completing this COD delivery.' using errcode = '22023';
        end if;

        update public.orders
        set status = 'completed', payment_status = 'paid', updated_at = now()
        where id = v_job.order_id
          and payment_status = 'cod_pending'
          and payment_method = 'cod';

        if not found then
          raise exception 'COD payment could not be confirmed.' using errcode = '22023';
        end if;
      elsif v_order_payment = 'paid' then
        update public.orders
        set status = 'completed', updated_at = now()
        where id = v_job.order_id and payment_status = 'paid';
      else
        raise exception 'Payment must be confirmed before completing this order.' using errcode = '22023';
      end if;
    end if;

    update public.delivery_jobs
    set status = 'delivered', updated_at = now()
    where id = p_delivery_job_id;

    update public.delivery_assignments
    set status = 'completed', updated_at = now()
    where delivery_job_id = p_delivery_job_id
      and partner_id = (select auth.uid())
      and status = 'accepted';

  else
    raise exception 'invalid delivery action' using errcode = '22023';
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    (select auth.uid()),
    'delivery.' || p_action,
    'delivery_job',
    p_delivery_job_id,
    jsonb_build_object('status_before', v_job.status, 'action', p_action)
  );
end;
$function$;

revoke all on function public.partner_update_delivery_status(uuid, text) from public, anon;
grant execute on function public.partner_update_delivery_status(uuid, text) to authenticated;

create or replace function private.dispatch_pending_deliveries(
  p_area_code text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
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
    select dj.id, dj.area_code, dj.job_type, dj.order_id,
           dj.pickup_latitude, dj.pickup_longitude
    from public.delivery_jobs dj
    left join public.orders o on o.id = dj.order_id
    where dj.delivery_partner_id is null
      and dj.status = 'pending'
      and (p_area_code is null or dj.area_code in (upper(trim(p_area_code)), 'DEFAULT'))
      and (
        (dj.job_type = 'parcel' and dj.order_id is null)
        or (
          dj.order_id is not null
          and o.payment_status in ('paid', 'cod_pending')
          and o.status = 'ready_for_pickup'
        )
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
        and oi.status = 'active'
      order by oi.created_at
      limit 1;

      if v_service is null then
        continue;
      end if;
    end if;

    select sc.enabled, sc.automatic_assignment
    into v_enabled, v_auto
    from public.service_controls sc
    where sc.service = v_service
      and sc.area_code in (v_area, 'DEFAULT')
    order by case when sc.area_code = v_area then 0 else 1 end
    limit 1;

    if not coalesce(v_enabled, false) or not coalesce(v_auto, false) then
      continue;
    end if;

    v_partner := null;

    select pp.user_id into v_partner
    from public.partner_presence pp
    join public.user_roles ur
      on ur.user_id = pp.user_id
     and ur.role = 'delivery_partner'
    where pp.role = 'delivery_partner'
      and pp.is_online
      and pp.updated_at > now() - interval '10 minutes'
      and pp.area_code in (v_area, 'DEFAULT')
      and not exists (
        select 1
        from public.delivery_jobs active
        where active.delivery_partner_id = pp.user_id
          and active.status in ('assigned', 'accepted', 'picked_up', 'in_transit')
      )
      and not exists (
        select 1
        from public.delivery_assignments prev
        where prev.delivery_job_id = v_job.id
          and prev.partner_id = pp.user_id
          and prev.status = 'rejected'
      )
    order by
      case when pp.area_code = v_area then 0 else 1 end,
      case
        when pp.latitude is not null and v_job.pickup_latitude is not null
          then power(pp.latitude - v_job.pickup_latitude, 2)
             + power(pp.longitude - v_job.pickup_longitude, 2)
        else 999999
      end,
      pp.updated_at asc
    limit 1
    for update of pp skip locked;

    if v_partner is not null then
      update public.delivery_jobs
      set delivery_partner_id = v_partner,
          status = 'assigned',
          auto_assigned_at = now(),
          updated_at = now()
      where id = v_job.id;

      insert into public.delivery_assignments(delivery_job_id, partner_id, assigned_by, status)
      values (v_job.id, v_partner, null, 'offered');

      insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
      values (
        null,
        'delivery.auto_assigned',
        'delivery_job',
        v_job.id,
        jsonb_build_object('partner_id', v_partner, 'service', v_service, 'area_code', v_area)
      );

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$function$;

revoke all on function private.dispatch_pending_deliveries(text) from public, anon, authenticated;
