-- Presence-aware automatic dispatch. Assignment is opt-in per area and service.
-- If no eligible partner is online, the request remains in the admin's manual queue.

alter table public.rides add column if not exists area_code text not null default 'DEFAULT';
alter table public.rides add column if not exists auto_assigned_at timestamptz;
alter table public.delivery_jobs add column if not exists area_code text not null default 'DEFAULT';
alter table public.delivery_jobs add column if not exists auto_assigned_at timestamptz;

create table if not exists public.partner_presence (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('driver_partner','delivery_partner')),
  area_code text not null default 'DEFAULT' check (char_length(area_code) between 2 and 40),
  is_online boolean not null default false,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  updated_at timestamptz not null default now(),
  primary key (user_id, role),
  check ((latitude is null) = (longitude is null))
);
create index if not exists partner_presence_dispatch_idx on public.partner_presence(role, area_code, is_online, updated_at);
alter table public.partner_presence enable row level security;
alter table public.partner_presence force row level security;
revoke all on public.partner_presence from anon, authenticated;
grant select on public.partner_presence to authenticated;
drop policy if exists partner_presence_read_own_admin on public.partner_presence;
create policy partner_presence_read_own_admin on public.partner_presence for select to authenticated
  using (user_id = (select auth.uid()) or (select private.has_role('admin')));

create or replace function private.dispatch_pending_rides(p_area_code text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
    where sc.service = 'ride' and sc.area_code in (v_ride.area_code, 'DEFAULT')
    order by case when sc.area_code = v_ride.area_code then 0 else 1 end
    limit 1;
    if not coalesce(v_control_enabled, false) or not coalesce(v_auto, false) then continue; end if;

    v_partner := null;
    select pp.user_id into v_partner
    from public.partner_presence pp
    join public.user_roles ur on ur.user_id = pp.user_id and ur.role = 'driver_partner'
    where pp.role = 'driver_partner' and pp.is_online
      and pp.area_code in (v_ride.area_code, 'DEFAULT')
      and not exists (
        select 1 from public.rides active
        where active.driver_id = pp.user_id and active.status in ('accepted','arrived','in_progress')
      )
    order by
      case when pp.area_code = v_ride.area_code then 0 else 1 end,
      case when pp.latitude is not null then
        power(pp.latitude - v_ride.pickup_latitude, 2) + power(pp.longitude - v_ride.pickup_longitude, 2)
      else 999999 end,
      pp.updated_at asc
    limit 1
    for update of pp skip locked;

    if v_partner is not null then
      update public.rides set driver_id = v_partner, auto_assigned_at = now(), updated_at = now() where id = v_ride.id;
      insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
        values (null, 'ride.auto_assigned', 'ride', v_ride.id,
          jsonb_build_object('driver_id', v_partner, 'area_code', v_ride.area_code));
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.dispatch_pending_rides(text) from public, anon, authenticated;

create or replace function private.dispatch_pending_deliveries(p_area_code text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
        or (dj.order_id is not null and o.payment_status = 'paid' and o.status = 'ready_for_pickup')
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
$$;
revoke all on function private.dispatch_pending_deliveries(text) from public, anon, authenticated;

create or replace function public.partner_set_availability(
  p_role text, p_area_code text, p_is_online boolean,
  p_latitude double precision default null, p_longitude double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  if p_role not in ('driver_partner','delivery_partner') then raise exception 'invalid partner role' using errcode='22023'; end if;
  if not exists(select 1 from public.user_roles ur where ur.user_id=(select auth.uid()) and ur.role=p_role) then
    raise exception 'partner role not approved for this account' using errcode='42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 then raise exception 'invalid service area code' using errcode='22023'; end if;
  if (p_latitude is null) <> (p_longitude is null)
     or p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    raise exception 'invalid coordinates' using errcode='22023';
  end if;
  insert into public.partner_presence(user_id,role,area_code,is_online,latitude,longitude,updated_at)
  values ((select auth.uid()),p_role,v_area,coalesce(p_is_online,false),p_latitude,p_longitude,now())
  on conflict(user_id,role) do update set area_code=excluded.area_code,is_online=excluded.is_online,
    latitude=excluded.latitude,longitude=excluded.longitude,updated_at=now();
  insert into public.audit_events(actor_id,action,entity_type,metadata)
    values ((select auth.uid()),case when p_is_online then 'partner.online' else 'partner.offline' end,'partner_presence',
      jsonb_build_object('role',p_role,'area_code',v_area));
  if p_is_online then
    perform private.dispatch_pending_rides(v_area);
    perform private.dispatch_pending_deliveries(v_area);
  end if;
end;
$$;
revoke all on function public.partner_set_availability(text,text,boolean,double precision,double precision) from public, anon;
grant execute on function public.partner_set_availability(text,text,boolean,double precision,double precision) to authenticated;

-- Area-specific controls override DEFAULT controls; requests are queued if the winning rule is disabled/manual.
create or replace function public.admin_set_service_control(
  p_area_code text, p_service text, p_enabled boolean, p_automatic_assignment boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 or p_service not in ('ride','parcel','food','shopping','quick') then
    raise exception 'invalid service control' using errcode = '22023';
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
$$;
revoke all on function public.admin_set_service_control(text,text,boolean,boolean) from public, anon;
grant execute on function public.admin_set_service_control(text,text,boolean,boolean) to authenticated;

-- Enforce service controls in the transaction even if a client tries to bypass the UI.
create or replace function private.enforce_order_item_service_control()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area text;
  v_kind text;
  v_enabled boolean;
begin
  select coalesce(nullif(upper(trim(o.delivery_address_snapshot->>'area_code')), ''), 'DEFAULT')
    into v_area from public.orders o where o.id = new.order_id;
  select p.kind into v_kind from public.seller_products p where p.id = new.product_id;
  select sc.enabled into v_enabled from public.service_controls sc
    where sc.service = v_kind and sc.area_code in (v_area,'DEFAULT')
    order by case when sc.area_code = v_area then 0 else 1 end limit 1;
  if not coalesce(v_enabled,false) then raise exception 'service is not enabled for this area' using errcode='22023'; end if;
  return new;
end;
$$;
revoke all on function private.enforce_order_item_service_control() from public, anon, authenticated;
drop trigger if exists order_item_enforce_service_control on public.order_items;
create trigger order_item_enforce_service_control before insert on public.order_items
for each row execute function private.enforce_order_item_service_control();

-- Keep the dispatch job's service area from the customer's chosen address.
create or replace function public.create_delivery_job_for_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.delivery_jobs(order_id,customer_id,seller_id,status,job_type,area_code)
  values(new.id,new.customer_id,new.seller_id,'pending','order',
    coalesce(nullif(upper(trim(new.delivery_address_snapshot->>'area_code')),''),'DEFAULT'))
  on conflict(order_id) do nothing;
  return new;
end;
$$;
revoke all on function public.create_delivery_job_for_order() from public, anon, authenticated;
drop trigger if exists orders_create_delivery_job on public.orders;
create trigger orders_create_delivery_job after insert on public.orders
for each row execute function public.create_delivery_job_for_order();

create or replace function public.dispatch_after_order_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.payment_status is distinct from old.payment_status or new.status is distinct from old.status then
    perform private.dispatch_pending_deliveries(null);
  end if;
  return new;
end;
$$;
revoke all on function public.dispatch_after_order_update() from public, anon, authenticated;
drop trigger if exists orders_dispatch_ready_delivery on public.orders;
create trigger orders_dispatch_ready_delivery after update of payment_status,status on public.orders
for each row execute function public.dispatch_after_order_update();

create or replace function public.dispatch_after_ride_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.dispatch_pending_rides(new.area_code);
  return new;
end;
$$;
revoke all on function public.dispatch_after_ride_insert() from public, anon, authenticated;
drop trigger if exists rides_auto_dispatch on public.rides;
create trigger rides_auto_dispatch after insert on public.rides
for each row execute function public.dispatch_after_ride_insert();

create or replace function public.dispatch_after_delivery_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.dispatch_pending_deliveries(new.area_code);
  return new;
end;
$$;
revoke all on function public.dispatch_after_delivery_insert() from public, anon, authenticated;
drop trigger if exists delivery_jobs_auto_dispatch on public.delivery_jobs;
create trigger delivery_jobs_auto_dispatch after insert on public.delivery_jobs
for each row execute function public.dispatch_after_delivery_insert();

-- Replace the ride RPC so the requested area is persisted for dispatch.
create or replace function public.create_customer_ride(
  p_pickup_label text, p_pickup_latitude double precision, p_pickup_longitude double precision,
  p_destination_label text, p_destination_latitude double precision, p_destination_longitude double precision,
  p_idempotency_key text, p_area_code text default 'DEFAULT'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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
  v_ride uuid;
begin
  if v_customer is null then raise exception 'sign-in required' using errcode='42501'; end if;
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
  select id into v_ride from public.rides where customer_id=v_customer and idempotency_key=p_idempotency_key;
  if v_ride is not null then return v_ride; end if;
  select sc.enabled into v_enabled from public.service_controls sc where sc.service='ride' and sc.area_code in (v_area,'DEFAULT')
    order by case when sc.area_code=v_area then 0 else 1 end limit 1;
  if not coalesce(v_enabled,false) then raise exception 'ride service is not enabled for this area' using errcode='P0002'; end if;
  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m<100 or v_straight_m>500000 then raise exception 'ride distance is outside supported limits' using errcode='22023'; end if;
  v_estimated_m:=ceil(v_straight_m*1.35)::integer;
  select base_fee_minor,per_km_minor,minimum_fee_minor into v_base,v_per_km,v_minimum from public.pricing_rules
    where service='ride' and active=true and city_code in (v_area,'DEFAULT')
    order by case when city_code=v_area then 0 else 1 end limit 1;
  if not found then raise exception 'ride pricing is not configured for this area' using errcode='P0002'; end if;
  v_fare:=greatest(v_minimum,v_base+ceil(v_estimated_m/1000.0)::bigint*v_per_km);
  insert into public.rides(customer_id,status,pickup_label,destination_label,pickup_latitude,pickup_longitude,
    destination_latitude,destination_longitude,estimated_distance_m,fare_minor,idempotency_key,area_code)
  values(v_customer,'requested',trim(p_pickup_label),trim(p_destination_label),p_pickup_latitude,p_pickup_longitude,
    p_destination_latitude,p_destination_longitude,v_estimated_m,v_fare,p_idempotency_key,v_area)
  returning id into v_ride;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(v_customer,'ride.requested','ride',v_ride,jsonb_build_object('area_code',v_area,'estimated_distance_m',v_estimated_m));
  return v_ride;
exception when unique_violation then
  select id into v_ride from public.rides where customer_id=auth.uid() and idempotency_key=p_idempotency_key;
  if v_ride is not null then return v_ride; end if;
  raise;
end;
$$;
revoke all on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text) from public, anon;
grant execute on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text) to authenticated;

-- Replace the parcel RPC so the requested area is persisted and dispatcher-ready.
create or replace function public.create_customer_parcel(
  p_pickup_label text, p_pickup_latitude double precision, p_pickup_longitude double precision,
  p_destination_label text, p_destination_latitude double precision, p_destination_longitude double precision,
  p_item_description text, p_idempotency_key text, p_area_code text default 'DEFAULT'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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
  v_job uuid;
begin
  if v_customer is null then raise exception 'sign-in required' using errcode='42501'; end if;
  if coalesce(length(trim(p_pickup_label)),0)<2 or coalesce(length(trim(p_destination_label)),0)<2 then
    raise exception 'pickup and destination are required' using errcode='22023';
  end if;
  if coalesce(length(trim(p_item_description)),0)<2 or char_length(p_item_description)>300 then
    raise exception 'provide a short item description' using errcode='22023';
  end if;
  if p_pickup_latitude not between -90 and 90 or p_destination_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_destination_longitude not between -180 and 180 then
    raise exception 'invalid pickup or destination coordinates' using errcode='22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key)<16 or char_length(p_idempotency_key)>128 then
    raise exception 'invalid idempotency key' using errcode='22023';
  end if;
  select id into v_job from public.delivery_jobs where customer_id=v_customer and idempotency_key=p_idempotency_key;
  if v_job is not null then return v_job; end if;
  select sc.enabled into v_enabled from public.service_controls sc where sc.service='parcel' and sc.area_code in (v_area,'DEFAULT')
    order by case when sc.area_code=v_area then 0 else 1 end limit 1;
  if not coalesce(v_enabled,false) then raise exception 'parcel service is not enabled for this area' using errcode='P0002'; end if;
  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m<100 or v_straight_m>300000 then raise exception 'parcel distance is outside supported limits' using errcode='22023'; end if;
  v_estimated_m:=ceil(v_straight_m*1.5)::integer;
  select base_fee_minor,per_km_minor,minimum_fee_minor into v_base,v_per_km,v_minimum from public.pricing_rules
    where service='parcel' and active=true and city_code in (v_area,'DEFAULT')
    order by case when city_code=v_area then 0 else 1 end limit 1;
  if not found then raise exception 'parcel pricing is not configured for this area' using errcode='P0002'; end if;
  v_fare:=greatest(v_minimum,v_base+ceil(v_estimated_m/1000.0)::bigint*v_per_km);
  insert into public.delivery_jobs(customer_id,status,job_type,pickup_label,pickup_latitude,pickup_longitude,
    destination_label,destination_latitude,destination_longitude,item_description,fare_minor,idempotency_key,area_code)
  values(v_customer,'pending','parcel',trim(p_pickup_label),p_pickup_latitude,p_pickup_longitude,
    trim(p_destination_label),p_destination_latitude,p_destination_longitude,trim(p_item_description),v_fare,p_idempotency_key,v_area)
  returning id into v_job;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(v_customer,'parcel.requested','delivery_job',v_job,jsonb_build_object('area_code',v_area,'estimated_distance_m',v_estimated_m));
  return v_job;
exception when unique_violation then
  select id into v_job from public.delivery_jobs where customer_id=auth.uid() and idempotency_key=p_idempotency_key;
  if v_job is not null then return v_job; end if;
  raise;
end;
$$;
revoke all on function public.create_customer_parcel(text,double precision,double precision,text,double precision,double precision,text,text,text) from public, anon;
grant execute on function public.create_customer_parcel(text,double precision,double precision,text,double precision,double precision,text,text,text) to authenticated;
