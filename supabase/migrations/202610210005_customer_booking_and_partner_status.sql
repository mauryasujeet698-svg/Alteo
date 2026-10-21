-- Customer ride/parcel booking and partner-owned status transitions.
-- This migration is additive and keeps payment-provider secrets off mobile clients.

alter table public.delivery_jobs
  add column if not exists job_type text not null default 'order',
  add column if not exists pickup_label text,
  add column if not exists pickup_latitude double precision,
  add column if not exists pickup_longitude double precision,
  add column if not exists destination_label text,
  add column if not exists destination_latitude double precision,
  add column if not exists destination_longitude double precision,
  add column if not exists item_description text,
  add column if not exists fare_minor bigint,
  add column if not exists idempotency_key text;

do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_job_type_check check (job_type in ('order','parcel'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_pickup_lat_check check (pickup_latitude is null or pickup_latitude between -90 and 90);
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_pickup_lon_check check (pickup_longitude is null or pickup_longitude between -180 and 180);
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_destination_lat_check check (destination_latitude is null or destination_latitude between -90 and 90);
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_destination_lon_check check (destination_longitude is null or destination_longitude between -180 and 180);
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.delivery_jobs add constraint delivery_jobs_fare_minor_check check (fare_minor is null or fare_minor >= 0);
exception when duplicate_object then null;
end $$;
create unique index if not exists delivery_jobs_customer_idempotency_idx
  on public.delivery_jobs(customer_id, idempotency_key) where idempotency_key is not null;
create index if not exists delivery_jobs_type_status_idx on public.delivery_jobs(job_type, status, created_at desc);

-- Every marketplace order gets a delivery job in the same database transaction.
create or replace function public.create_delivery_job_for_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.delivery_jobs(order_id, customer_id, seller_id, status, job_type)
  values (new.id, new.customer_id, new.seller_id, 'pending', 'order')
  on conflict (order_id) do nothing;
  return new;
end;
$$;
revoke all on function public.create_delivery_job_for_order() from public, anon, authenticated;
drop trigger if exists orders_create_delivery_job on public.orders;
create trigger orders_create_delivery_job after insert on public.orders
for each row execute function public.create_delivery_job_for_order();

create or replace function public.create_customer_ride(
  p_pickup_label text,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_destination_label text,
  p_destination_latitude double precision,
  p_destination_longitude double precision,
  p_idempotency_key text,
  p_area_code text default 'DEFAULT'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := auth.uid();
  v_area text := upper(trim(coalesce(p_area_code,'DEFAULT')));
  v_straight_m integer;
  v_estimated_m integer;
  v_base bigint;
  v_per_km bigint;
  v_minimum bigint;
  v_fare bigint;
  v_ride uuid;
begin
  if v_customer is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if coalesce(length(trim(p_pickup_label)),0) < 2 or coalesce(length(trim(p_destination_label)),0) < 2 then
    raise exception 'pickup and destination are required' using errcode = '22023';
  end if;
  if p_pickup_latitude not between -90 and 90 or p_destination_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_destination_longitude not between -180 and 180 then
    raise exception 'invalid pickup or destination coordinates' using errcode = '22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  select id into v_ride from public.rides where customer_id = v_customer and idempotency_key = p_idempotency_key;
  if v_ride is not null then return v_ride; end if;

  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m < 100 or v_straight_m > 500000 then raise exception 'ride distance is outside supported limits' using errcode = '22023'; end if;
  -- Until a routing provider is configured server-side, use a conservative 1.35x straight-line estimate.
  v_estimated_m := ceil(v_straight_m * 1.35)::integer;
  select base_fee_minor, per_km_minor, minimum_fee_minor into v_base, v_per_km, v_minimum
    from public.pricing_rules
    where service = 'ride' and active = true and city_code in (v_area,'DEFAULT')
    order by case when city_code = v_area then 0 else 1 end limit 1;
  if not found then raise exception 'ride service is not enabled for this area' using errcode = 'P0002'; end if;
  v_fare := greatest(v_minimum, v_base + ceil(v_estimated_m / 1000.0)::bigint * v_per_km);
  insert into public.rides(customer_id,status,pickup_label,destination_label,pickup_latitude,pickup_longitude,
    destination_latitude,destination_longitude,estimated_distance_m,fare_minor,idempotency_key)
  values (v_customer,'requested',trim(p_pickup_label),trim(p_destination_label),p_pickup_latitude,p_pickup_longitude,
    p_destination_latitude,p_destination_longitude,v_estimated_m,v_fare,p_idempotency_key)
  returning id into v_ride;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values (v_customer,'ride.requested','ride',v_ride,jsonb_build_object('area_code',v_area,'estimated_distance_m',v_estimated_m));
  return v_ride;
exception when unique_violation then
  select id into v_ride from public.rides where customer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if v_ride is not null then return v_ride; end if;
  raise;
end;
$$;
revoke all on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text) from public, anon;
grant execute on function public.create_customer_ride(text,double precision,double precision,text,double precision,double precision,text,text) to authenticated;

create or replace function public.create_customer_parcel(
  p_pickup_label text,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_destination_label text,
  p_destination_latitude double precision,
  p_destination_longitude double precision,
  p_item_description text,
  p_idempotency_key text,
  p_area_code text default 'DEFAULT'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := auth.uid();
  v_area text := upper(trim(coalesce(p_area_code,'DEFAULT')));
  v_straight_m integer;
  v_estimated_m integer;
  v_base bigint;
  v_per_km bigint;
  v_minimum bigint;
  v_fare bigint;
  v_job uuid;
begin
  if v_customer is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if coalesce(length(trim(p_pickup_label)),0) < 2 or coalesce(length(trim(p_destination_label)),0) < 2 then
    raise exception 'pickup and destination are required' using errcode = '22023';
  end if;
  if coalesce(length(trim(p_item_description)),0) < 2 or char_length(p_item_description) > 300 then
    raise exception 'provide a short item description' using errcode = '22023';
  end if;
  if p_pickup_latitude not between -90 and 90 or p_destination_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_destination_longitude not between -180 and 180 then
    raise exception 'invalid pickup or destination coordinates' using errcode = '22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  select id into v_job from public.delivery_jobs where customer_id = v_customer and idempotency_key = p_idempotency_key;
  if v_job is not null then return v_job; end if;

  v_straight_m := ceil(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_destination_latitude-p_pickup_latitude)/2),2)
    + cos(radians(p_pickup_latitude))*cos(radians(p_destination_latitude))
      * power(sin(radians(p_destination_longitude-p_pickup_longitude)/2),2)
  )))::integer;
  if v_straight_m < 100 or v_straight_m > 300000 then raise exception 'parcel distance is outside supported limits' using errcode = '22023'; end if;
  v_estimated_m := ceil(v_straight_m * 1.5)::integer;
  select base_fee_minor, per_km_minor, minimum_fee_minor into v_base, v_per_km, v_minimum
    from public.pricing_rules
    where service = 'parcel' and active = true and city_code in (v_area,'DEFAULT')
    order by case when city_code = v_area then 0 else 1 end limit 1;
  if not found then raise exception 'parcel service is not enabled for this area' using errcode = 'P0002'; end if;
  v_fare := greatest(v_minimum, v_base + ceil(v_estimated_m / 1000.0)::bigint * v_per_km);
  insert into public.delivery_jobs(customer_id,status,job_type,pickup_label,pickup_latitude,pickup_longitude,
    destination_label,destination_latitude,destination_longitude,item_description,fare_minor,idempotency_key)
  values (v_customer,'pending','parcel',trim(p_pickup_label),p_pickup_latitude,p_pickup_longitude,
    trim(p_destination_label),p_destination_latitude,p_destination_longitude,trim(p_item_description),v_fare,p_idempotency_key)
  returning id into v_job;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values (v_customer,'parcel.requested','delivery_job',v_job,jsonb_build_object('area_code',v_area,'estimated_distance_m',v_estimated_m));
  return v_job;
exception when unique_violation then
  select id into v_job from public.delivery_jobs where customer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if v_job is not null then return v_job; end if;
  raise;
end;
$$;
revoke all on function public.create_customer_parcel(text,double precision,double precision,text,double precision,double precision,text,text,text) from public, anon;
grant execute on function public.create_customer_parcel(text,double precision,double precision,text,double precision,double precision,text,text,text) to authenticated;

create or replace function public.partner_update_delivery_status(p_delivery_job_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.delivery_jobs%rowtype;
  v_order_payment text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  select * into v_job from public.delivery_jobs where id = p_delivery_job_id for update;
  if not found or v_job.delivery_partner_id <> (select auth.uid()) then
    raise exception 'this delivery is not assigned to you' using errcode = '42501';
  end if;
  if p_action = 'accept' then
    update public.delivery_assignments set status='accepted',updated_at=now()
      where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='offered';
    if not found then raise exception 'no pending offer found' using errcode = '22023'; end if;
  elsif p_action = 'reject' then
    update public.delivery_assignments set status='rejected',updated_at=now()
      where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status in ('offered','accepted');
    update public.delivery_jobs set delivery_partner_id=null,status='pending',updated_at=now() where id=p_delivery_job_id;
  elsif p_action = 'picked_up' then
    if not exists(select 1 from public.delivery_assignments where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='accepted') then
      raise exception 'accept the assignment first' using errcode='22023';
    end if;
    if v_job.status <> 'assigned' then raise exception 'delivery is not ready for pickup' using errcode='22023'; end if;
    if v_job.order_id is not null then
      select payment_status into v_order_payment from public.orders where id=v_job.order_id;
      if v_order_payment <> 'paid' then raise exception 'order payment is not confirmed' using errcode='22023'; end if;
    end if;
    update public.delivery_jobs set status='picked_up',updated_at=now() where id=p_delivery_job_id;
    if v_job.order_id is not null then update public.orders set status='out_for_delivery',updated_at=now() where id=v_job.order_id; end if;
  elsif p_action = 'in_transit' then
    if v_job.status <> 'picked_up' then raise exception 'item must be picked up first' using errcode='22023'; end if;
    update public.delivery_jobs set status='in_transit',updated_at=now() where id=p_delivery_job_id;
  elsif p_action = 'delivered' then
    if v_job.status <> 'in_transit' then raise exception 'delivery must be in transit first' using errcode='22023'; end if;
    update public.delivery_jobs set status='delivered',updated_at=now() where id=p_delivery_job_id;
    update public.delivery_assignments set status='completed',updated_at=now()
      where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='accepted';
    if v_job.order_id is not null then update public.orders set status='completed',updated_at=now() where id=v_job.order_id and payment_status='paid'; end if;
  else
    raise exception 'invalid delivery action' using errcode='22023';
  end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values ((select auth.uid()),'delivery.'||p_action,'delivery_job',p_delivery_job_id,jsonb_build_object('status_before',v_job.status,'action',p_action));
end;
$$;
revoke all on function public.partner_update_delivery_status(uuid,text) from public, anon;
grant execute on function public.partner_update_delivery_status(uuid,text) to authenticated;

create or replace function public.driver_update_ride_status(p_ride_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ride public.rides%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select * into v_ride from public.rides where id=p_ride_id for update;
  if not found or v_ride.driver_id <> (select auth.uid()) then
    raise exception 'this ride is not assigned to you' using errcode='42501';
  end if;
  if p_action='accept' and v_ride.status='requested' then
    update public.rides set status='accepted',updated_at=now() where id=p_ride_id;
  elsif p_action='arrived' and v_ride.status='accepted' then
    update public.rides set status='arrived',updated_at=now() where id=p_ride_id;
  elsif p_action='start' and v_ride.status='arrived' then
    update public.rides set status='in_progress',updated_at=now() where id=p_ride_id;
  elsif p_action='complete' and v_ride.status='in_progress' then
    update public.rides set status='completed',updated_at=now() where id=p_ride_id;
  elsif p_action='cancel' and v_ride.status in ('requested','accepted','arrived') then
    update public.rides set status='cancelled',updated_at=now() where id=p_ride_id;
  else
    raise exception 'ride action is not allowed in its current state' using errcode='22023';
  end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values ((select auth.uid()),'ride.'||p_action,'ride',p_ride_id,jsonb_build_object('status_before',v_ride.status,'action',p_action));
end;
$$;
revoke all on function public.driver_update_ride_status(uuid,text) from public, anon;
grant execute on function public.driver_update_ride_status(uuid,text) to authenticated;

comment on table public.delivery_jobs is 'Delivery and parcel jobs. Partner sees only assigned jobs; item details inherit the assigned order access policy.';
