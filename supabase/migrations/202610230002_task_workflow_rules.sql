-- Validate cross-app task assignments and propagate partner actions to source records.

create or replace function public.validate_alteo_task_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is not null and not public.has_alteo_role('admin') then
    raise exception 'Only authorised admin users can create or change task assignments';
  end if;

  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = new.assigned_partner_id and ur.role = new.assigned_role
  ) then
    raise exception 'The assigned account does not have the required partner role';
  end if;

  if new.source_type = 'ride' and new.assigned_role <> 'driver_partner' then
    raise exception 'Ride tasks must be assigned to a driver partner';
  elsif new.source_type = 'parcel' and new.assigned_role <> 'delivery_partner' then
    raise exception 'Parcel tasks must be assigned to a delivery partner';
  elsif new.source_type = 'inventory' and new.assigned_role <> 'dark_store' then
    raise exception 'Inventory tasks must be assigned to a dark store';
  elsif new.source_type = 'order' and new.assigned_role not in ('seller','dark_store','delivery_partner') then
    raise exception 'Order tasks require seller, dark store or delivery partner role';
  end if;

  if new.source_type = 'order' and not exists (select 1 from public.orders o where o.id = new.source_id) then
    raise exception 'Order task source was not found';
  elsif new.source_type in ('ride','parcel') and not exists (
    select 1 from public.service_requests sr where sr.id = new.source_id and sr.service_type = new.source_type
  ) then
    raise exception 'Ride or parcel request source was not found';
  elsif new.source_type = 'inventory' and not exists (
    select 1 from public.inventory_items ii where ii.id = new.source_id
  ) then
    raise exception 'Inventory task source was not found';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_alteo_task_assignment on public.task_assignments;
create trigger validate_alteo_task_assignment
before insert or update on public.task_assignments
for each row execute function public.validate_alteo_task_assignment();

create or replace function public.respond_to_task(task_id uuid, action text)
returns public.task_assignments
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  task public.task_assignments;
  next_status text;
  previous_order_status text;
  next_order_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into task from public.task_assignments where id = task_id for update;
  if not found then raise exception 'Task not found'; end if;
  if task.assigned_partner_id <> auth.uid() then raise exception 'Task is not assigned to this account'; end if;
  if not public.has_alteo_role(task.assigned_role) then raise exception 'Required partner role missing'; end if;

  next_status := case action
    when 'accept' then 'accepted'
    when 'reject' then 'rejected'
    when 'start' then 'in_progress'
    when 'complete' then 'completed'
    else null
  end;
  if next_status is null then raise exception 'Unsupported task action'; end if;

  if action in ('accept','reject') and task.status <> 'assigned' then raise exception 'Task is no longer awaiting a response'; end if;
  if action = 'start' and task.status <> 'accepted' then raise exception 'Only accepted tasks can start'; end if;
  if action = 'complete' and task.status <> 'in_progress' then raise exception 'Only active tasks can be completed'; end if;

  update public.task_assignments set status = next_status, updated_at = now()
  where id = task.id returning * into task;

  if task.source_type = 'order' then
    select status into previous_order_status from public.orders where id = task.source_id for update;
    next_order_status := case
      when action = 'reject' then 'pending'
      when action = 'accept' and task.assigned_role = 'seller' then 'accepted'
      when action = 'accept' and task.assigned_role = 'dark_store' then 'accepted'
      when action = 'start' and task.assigned_role in ('seller','dark_store') then 'preparing'
      when action = 'start' and task.assigned_role = 'delivery_partner' then 'in_transit'
      when action = 'complete' and task.assigned_role in ('seller','dark_store') then 'ready_for_pickup'
      when action = 'complete' and task.assigned_role = 'delivery_partner' then 'delivered'
      else previous_order_status
    end;
    if next_order_status is distinct from previous_order_status then
      update public.orders set status = next_order_status, updated_at = now() where id = task.source_id;
      insert into public.order_status_events(order_id, actor_id, from_status, to_status, note)
      values (task.source_id, auth.uid(), previous_order_status, next_order_status, 'Task action: ' || action);
    end if;
  elsif task.source_type in ('ride','parcel') then
    update public.service_requests
    set status = case
          when action = 'accept' then 'accepted'
          when action = 'reject' then 'requested'
          when action = 'start' then 'in_progress'
          when action = 'complete' then 'completed'
          else status
        end,
        assigned_partner_id = case when action = 'reject' then null else assigned_partner_id end,
        assigned_role = case when action = 'reject' then null else assigned_role end,
        updated_at = now()
    where id = task.source_id;
  end if;

  return task;
end;
$$;
revoke all on function public.respond_to_task(uuid, text) from public;
grant execute on function public.respond_to_task(uuid, text) to authenticated;
