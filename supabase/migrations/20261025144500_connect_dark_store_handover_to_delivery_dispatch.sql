create or replace function public.admin_assign_order_to_dark_store(
  p_order_id uuid,
  p_store_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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
  if v_payment_status <> 'paid' or v_order_status <> 'paid' then
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

create or replace function public.dark_store_update_task(
  p_task_id uuid,
  p_action text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
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
    if not found or v_payment_status <> 'paid' then
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
      where id = v_task.order_id and payment_status = 'paid'
        and status in ('paid', 'ready_for_pickup');
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

create or replace function public.seller_update_order_status(
  p_order_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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

  if v_order.payment_status <> 'paid' then
    raise exception 'payment must be confirmed before processing' using errcode = '22023';
  end if;
  if p_action = 'accept' and v_order.status = 'paid' then
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

revoke all on function public.admin_assign_order_to_dark_store(uuid, uuid) from public;
grant execute on function public.admin_assign_order_to_dark_store(uuid, uuid) to authenticated;
revoke all on function public.dark_store_update_task(uuid, text) from public;
grant execute on function public.dark_store_update_task(uuid, text) to authenticated;
revoke all on function public.seller_update_order_status(uuid, text) from public;
grant execute on function public.seller_update_order_status(uuid, text) to authenticated;
