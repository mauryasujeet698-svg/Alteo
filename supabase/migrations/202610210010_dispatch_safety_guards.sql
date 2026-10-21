-- Final dispatch safety guards: one active ride per driver and ready-to-pick-up orders only.

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
    where sc.service='ride' and sc.area_code in (v_ride.area_code,'DEFAULT')
    order by case when sc.area_code=v_ride.area_code then 0 else 1 end
    limit 1;
    if not coalesce(v_control_enabled,false) or not coalesce(v_auto,false) then continue; end if;

    v_partner := null;
    select pp.user_id into v_partner
    from public.partner_presence pp
    join public.user_roles ur on ur.user_id=pp.user_id and ur.role='driver_partner'
    where pp.role='driver_partner' and pp.is_online
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
$$;
revoke all on function private.dispatch_pending_rides(text) from public, anon, authenticated;

create or replace function public.admin_assign_delivery_partner(p_delivery_job_id uuid, p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
    if v_payment_status <> 'paid' then raise exception 'order payment is not confirmed' using errcode='22023'; end if;
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
$$;
revoke all on function public.admin_assign_delivery_partner(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_delivery_partner(uuid,uuid) to authenticated;
