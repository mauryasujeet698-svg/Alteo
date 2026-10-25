create table if not exists public.dark_store_tasks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  store_id uuid not null references public.dark_stores(id) on delete restrict,
  status text not null default 'assigned'
    check (status in ('assigned','accepted','picking','packed','handed_over','cancelled')),
  assigned_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  picking_started_at timestamptz,
  packed_at timestamptz,
  handed_over_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dark_store_tasks_store_status_idx
  on public.dark_store_tasks(store_id, status, created_at desc);

alter table public.dark_store_tasks enable row level security;
revoke all on public.dark_store_tasks from anon, authenticated;
grant select on public.dark_store_tasks to authenticated;

drop policy if exists dark_store_tasks_read_authorized on public.dark_store_tasks;
create policy dark_store_tasks_read_authorized
on public.dark_store_tasks for select to authenticated
using (
  (select private.has_role('admin'::text))
  or exists (
    select 1 from public.dark_stores ds
    where ds.id = dark_store_tasks.store_id
      and ds.owner_user_id = (select auth.uid())
  )
);

drop policy if exists orders_read_authorized on public.orders;
create policy orders_read_authorized
on public.orders for select to authenticated
using (
  customer_id = (select auth.uid())
  or exists (
    select 1 from public.sellers s
    where s.id = orders.seller_id and s.owner_id = (select auth.uid())
  )
  or exists (
    select 1 from public.delivery_jobs dj
    where dj.order_id = orders.id and dj.delivery_partner_id = (select auth.uid())
  )
  or exists (
    select 1 from public.dark_store_tasks dst
    join public.dark_stores ds on ds.id = dst.store_id
    where dst.order_id = orders.id and ds.owner_user_id = (select auth.uid())
  )
  or (select private.has_role('admin'::text))
);

drop policy if exists order_items_read_authorized on public.order_items;
create policy order_items_read_authorized
on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id and (
      o.customer_id = (select auth.uid())
      or exists (
        select 1 from public.sellers s
        where s.id = o.seller_id and s.owner_id = (select auth.uid())
      )
      or exists (
        select 1 from public.delivery_jobs dj
        where dj.order_id = o.id and dj.delivery_partner_id = (select auth.uid())
      )
      or exists (
        select 1 from public.dark_store_tasks dst
        join public.dark_stores ds on ds.id = dst.store_id
        where dst.order_id = o.id and ds.owner_user_id = (select auth.uid())
      )
      or (select private.has_role('admin'::text))
    )
  )
);

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
  if v_payment_status <> 'paid' then
    raise exception 'only paid orders can be assigned to a dark store' using errcode = '22023';
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
    jsonb_build_object('order_id', p_order_id, 'store_id', p_store_id));
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

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'dark_store.task_' || v_next, 'dark_store_task', p_task_id,
    jsonb_build_object('order_id', v_task.order_id, 'store_id', v_task.store_id));
  return v_next;
end;
$function$;

revoke all on function public.admin_assign_order_to_dark_store(uuid, uuid) from public;
grant execute on function public.admin_assign_order_to_dark_store(uuid, uuid) to authenticated;
revoke all on function public.dark_store_update_task(uuid, text) from public;
grant execute on function public.dark_store_update_task(uuid, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dark_store_tasks'
     ) then
    alter publication supabase_realtime add table public.dark_store_tasks;
  end if;
end $$;
