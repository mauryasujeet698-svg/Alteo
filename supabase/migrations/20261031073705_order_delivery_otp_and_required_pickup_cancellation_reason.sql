-- Four-digit seller handover and customer delivery verification, plus required
-- cancellation reasons for accepted delivery assignments.
create table if not exists private.order_delivery_verification_codes (
  order_id uuid primary key references public.orders(id) on delete cascade,
  customer_code text not null check (customer_code ~ '^[0-9]{4}$'),
  pickup_code text not null check (pickup_code ~ '^[0-9]{4}$'),
  customer_attempts integer not null default 0 check (customer_attempts >= 0),
  pickup_attempts integer not null default 0 check (pickup_attempts >= 0),
  customer_verified_at timestamptz,
  pickup_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.order_delivery_verification_codes enable row level security;
revoke all on private.order_delivery_verification_codes from public, anon, authenticated;

alter table public.delivery_assignments add column if not exists cancellation_reason text;

create or replace function private.create_order_delivery_verification_codes()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  insert into private.order_delivery_verification_codes(order_id,customer_code,pickup_code)
  values (new.id,
    lpad(floor(random()*10000)::integer::text,4,'0'),
    lpad(floor(random()*10000)::integer::text,4,'0'))
  on conflict (order_id) do nothing;
  return new;
end;
$function$;
revoke all on function private.create_order_delivery_verification_codes() from public,anon,authenticated;

drop trigger if exists orders_create_delivery_verification_codes on public.orders;
create trigger orders_create_delivery_verification_codes
after insert on public.orders
for each row execute function private.create_order_delivery_verification_codes();

insert into private.order_delivery_verification_codes(order_id,customer_code,pickup_code)
select o.id,lpad(floor(random()*10000)::integer::text,4,'0'),
       lpad(floor(random()*10000)::integer::text,4,'0')
from public.orders o
on conflict (order_id) do nothing;

create or replace function public.customer_get_delivery_verification_code(p_order_id uuid)
returns text language plpgsql security definer set search_path = ''
as $function$
declare v_code text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select c.customer_code into v_code
  from private.order_delivery_verification_codes c
  join public.orders o on o.id=c.order_id
  where o.id=p_order_id and o.customer_id=(select auth.uid())
    and o.status='out_for_delivery' and c.customer_verified_at is null;
  if v_code is null then raise exception 'delivery verification code is available only for an active delivery' using errcode='P0002'; end if;
  return v_code;
end;
$function$;

create or replace function public.seller_get_pickup_verification_code(p_order_id uuid)
returns text language plpgsql security definer set search_path = ''
as $function$
declare v_code text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select c.pickup_code into v_code
  from private.order_delivery_verification_codes c
  join public.orders o on o.id=c.order_id
  where o.id=p_order_id and o.status='ready_for_pickup' and c.pickup_verified_at is null
    and (
      exists (select 1 from public.sellers s
        where s.id=o.seller_id and s.owner_id=(select auth.uid()) and s.status='approved')
      or exists (select 1 from public.dark_store_tasks dst
        join public.dark_stores ds on ds.id=dst.store_id
        where dst.order_id=o.id and dst.status='handed_over'
          and ds.owner_user_id=(select auth.uid()) and ds.status='active')
    );
  if v_code is null then raise exception 'pickup code is available to the assigned seller or dark store when the order is ready' using errcode='42501'; end if;
  return v_code;
end;
$function$;

revoke all on function public.customer_get_delivery_verification_code(uuid) from public,anon;
revoke all on function public.seller_get_pickup_verification_code(uuid) from public,anon;
grant execute on function public.customer_get_delivery_verification_code(uuid) to authenticated;
grant execute on function public.seller_get_pickup_verification_code(uuid) to authenticated;

drop function if exists public.partner_update_delivery_status(uuid,text);
create function public.partner_update_delivery_status(
  p_delivery_job_id uuid,
  p_action text,
  p_verification_code text default null,
  p_cancellation_reason text default null
)
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare
  v_job public.delivery_jobs%rowtype;
  v_order_payment text;
  v_order_method text;
  v_customer_code text;
  v_pickup_code text;
  v_reason text := trim(coalesce(p_cancellation_reason,''));
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select * into v_job from public.delivery_jobs where id=p_delivery_job_id for update;
  if not found or v_job.delivery_partner_id <> (select auth.uid()) then
    raise exception 'this delivery is not assigned to you' using errcode='42501';
  end if;

  if p_action='accept' then
    update public.delivery_assignments set status='accepted',updated_at=now()
    where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='offered';
    if not found then raise exception 'no pending offer found' using errcode='22023'; end if;
    update public.delivery_jobs set status='accepted',updated_at=now()
    where id=p_delivery_job_id and status='assigned';
    if not found then raise exception 'delivery is not in the assigned state' using errcode='22023'; end if;

  elsif p_action='reject' then
    if v_job.status<>'assigned' then raise exception 'only a new delivery offer can be declined' using errcode='22023'; end if;
    update public.delivery_assignments set status='rejected',updated_at=now()
    where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='offered';
    if not found then raise exception 'no pending offer found' using errcode='22023'; end if;
    update public.delivery_jobs set delivery_partner_id=null,status='pending',updated_at=now()
    where id=p_delivery_job_id;

  elsif p_action='cancel' then
    if v_job.status<>'accepted' then raise exception 'an accepted delivery can only be cancelled before pickup' using errcode='22023'; end if;
    if char_length(v_reason)<5 then raise exception 'select a cancellation reason before releasing this delivery' using errcode='22023'; end if;
    update public.delivery_assignments
    set status='rejected',cancellation_reason=left(v_reason,500),updated_at=now()
    where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='accepted';
    if not found then raise exception 'accepted delivery assignment was not found' using errcode='22023'; end if;
    update public.delivery_jobs set delivery_partner_id=null,status='pending',updated_at=now()
    where id=p_delivery_job_id and status='accepted';
    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values ((select auth.uid()),'delivery.partner_cancelled','delivery_job',p_delivery_job_id,
      jsonb_build_object('reason',left(v_reason,500),'status_before',v_job.status));

  elsif p_action='picked_up' then
    if not exists (select 1 from public.delivery_assignments
      where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='accepted') then
      raise exception 'accept the assignment first' using errcode='22023';
    end if;
    if v_job.status<>'accepted' then raise exception 'delivery must be accepted before pickup' using errcode='22023'; end if;
    if v_job.order_id is not null then
      select payment_status,payment_method into v_order_payment,v_order_method
      from public.orders where id=v_job.order_id for update;
      if v_order_payment not in ('paid','cod_pending') then raise exception 'order payment is not confirmed' using errcode='22023'; end if;
      select pickup_code into v_pickup_code from private.order_delivery_verification_codes
      where order_id=v_job.order_id and pickup_verified_at is null for update;
      if v_pickup_code is null or p_verification_code !~ '^[0-9]{4}$'
          or p_verification_code is distinct from v_pickup_code then
        update private.order_delivery_verification_codes set pickup_attempts=pickup_attempts+1,updated_at=now()
        where order_id=v_job.order_id;
        return false;
      end if;
      update private.order_delivery_verification_codes set pickup_verified_at=now(),updated_at=now()
      where order_id=v_job.order_id and pickup_verified_at is null;
      if not found then raise exception 'pickup code has already been used' using errcode='22023'; end if;
    end if;
    update public.delivery_jobs set status='picked_up',updated_at=now() where id=p_delivery_job_id;
    if v_job.order_id is not null then
      update public.orders set status='out_for_delivery',updated_at=now() where id=v_job.order_id;
    end if;

  elsif p_action='in_transit' then
    if v_job.status<>'picked_up' then raise exception 'item must be picked up first' using errcode='22023'; end if;
    update public.delivery_jobs set status='in_transit',updated_at=now() where id=p_delivery_job_id;

  elsif p_action in ('delivered','delivered_cod_collected') then
    if v_job.status<>'in_transit' then raise exception 'delivery must be in transit first' using errcode='22023'; end if;
    if v_job.order_id is not null then
      select payment_status,payment_method into v_order_payment,v_order_method
      from public.orders where id=v_job.order_id for update;
      select customer_code into v_customer_code from private.order_delivery_verification_codes
      where order_id=v_job.order_id and customer_verified_at is null for update;
      if v_customer_code is null or p_verification_code !~ '^[0-9]{4}$'
          or p_verification_code is distinct from v_customer_code then
        update private.order_delivery_verification_codes set customer_attempts=customer_attempts+1,updated_at=now()
        where order_id=v_job.order_id;
        return false;
      end if;
      update private.order_delivery_verification_codes set customer_verified_at=now(),updated_at=now()
      where order_id=v_job.order_id and customer_verified_at is null;
      if not found then raise exception 'delivery code has already been used' using errcode='22023'; end if;
      if v_order_method='cod' and v_order_payment='cod_pending' then
        if p_action<>'delivered_cod_collected' then raise exception 'confirm cash collection before completing this COD delivery' using errcode='22023'; end if;
        update public.orders set status='completed',payment_status='paid',updated_at=now()
        where id=v_job.order_id and payment_status='cod_pending' and payment_method='cod';
        if not found then raise exception 'COD payment could not be confirmed' using errcode='22023'; end if;
      elsif v_order_payment='paid' then
        update public.orders set status='completed',updated_at=now() where id=v_job.order_id and payment_status='paid';
      else
        raise exception 'payment must be confirmed before completing this order' using errcode='22023';
      end if;
    end if;
    update public.delivery_jobs set status='delivered',updated_at=now() where id=p_delivery_job_id;
    update public.delivery_assignments set status='completed',updated_at=now()
    where delivery_job_id=p_delivery_job_id and partner_id=(select auth.uid()) and status='accepted';
  else
    raise exception 'invalid delivery action' using errcode='22023';
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values ((select auth.uid()),'delivery.'||p_action,'delivery_job',p_delivery_job_id,
    jsonb_build_object('status_before',v_job.status,'action',p_action));
  return true;
end;
$function$;
revoke all on function public.partner_update_delivery_status(uuid,text,text,text) from public,anon;
grant execute on function public.partner_update_delivery_status(uuid,text,text,text) to authenticated;

create or replace function public.admin_update_dark_store_product_submission(p_submission_id uuid,p_updates jsonb)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_row public.dark_store_product_submissions%rowtype;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin'::text)) then raise exception 'administrator role required' using errcode='42501'; end if;
  select * into v_row from public.dark_store_product_submissions where id=p_submission_id for update;
  if not found then raise exception 'product submission not found' using errcode='P0002'; end if;
  if v_row.status<>'pending_review' then raise exception 'only pending submissions can be edited here' using errcode='22023'; end if;
  update public.dark_store_product_submissions set
    sku=coalesce(nullif(trim(p_updates->>'sku'),''),sku),
    name=coalesce(nullif(trim(p_updates->>'name'),''),name),
    category=coalesce(nullif(trim(p_updates->>'category'),''),category),
    subcategory=case when p_updates ? 'subcategory' then nullif(trim(p_updates->>'subcategory'),'') else subcategory end,
    brand=case when p_updates ? 'brand' then nullif(trim(p_updates->>'brand'),'') else brand end,
    description=coalesce(nullif(trim(p_updates->>'description'),''),description),
    price_minor=case when p_updates ? 'price_minor' then (p_updates->>'price_minor')::bigint else price_minor end,
    mrp_minor=case when p_updates ? 'mrp_minor' then (p_updates->>'mrp_minor')::bigint else mrp_minor end,
    unit_label=coalesce(nullif(trim(p_updates->>'unit_label'),''),unit_label),
    image_url=coalesce(nullif(trim(p_updates->>'image_url'),''),image_url),
    proposed_stock=case when p_updates ? 'proposed_stock' then (p_updates->>'proposed_stock')::integer else proposed_stock end,
    availability_mode=coalesce(p_updates->>'availability_mode',availability_mode),
    available_pincodes=case when p_updates ? 'available_pincodes' then array(select jsonb_array_elements_text(p_updates->'available_pincodes')) else available_pincodes end,
    updated_at=now()
  where id=p_submission_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values ((select auth.uid()),'catalogue.dark_store_product_edited','dark_store_product_submission',p_submission_id,jsonb_build_object('sku',v_row.sku));
end;
$function$;
revoke all on function public.admin_update_dark_store_product_submission(uuid,jsonb) from public,anon;
grant execute on function public.admin_update_dark_store_product_submission(uuid,jsonb) to authenticated;

create or replace function public.admin_archive_catalogue_product(p_product_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin'::text)) then raise exception 'administrator role required' using errcode='42501'; end if;
  update public.seller_products set archived_at=coalesce(archived_at,now()),status='paused',updated_at=now() where id=p_product_id;
  if not found then raise exception 'catalogue product not found' using errcode='P0002'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values ((select auth.uid()),'catalogue.product_archived','seller_product',p_product_id,'{}'::jsonb);
end;
$function$;
revoke all on function public.admin_archive_catalogue_product(uuid) from public,anon;
grant execute on function public.admin_archive_catalogue_product(uuid) to authenticated;
