-- Partner onboarding hardening, service-area coverage modes and partner ratings.
-- Additive migration; Customer app source files are not modified.

alter table public.service_areas
  add column if not exists coverage_mode text not null default 'pincode',
  add column if not exists covered_localities text[] not null default array[]::text[];

alter table public.service_areas drop constraint if exists service_areas_coverage_mode_check;
alter table public.service_areas add constraint service_areas_coverage_mode_check
  check (
    (coverage_mode = 'pincode' and cardinality(covered_localities) = 0)
    or
    (coverage_mode = 'selected_areas' and cardinality(covered_localities) > 0)
  );

create or replace function public.service_areas_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $function$
declare
  v_localities text[];
begin
  new.pincode := trim(new.pincode);
  new.locality := nullif(trim(new.locality), '');
  new.district := nullif(trim(new.district), '');
  new.state := nullif(trim(new.state), '');
  new.coverage_mode := lower(trim(coalesce(new.coverage_mode, 'pincode')));
  select coalesce(array_agg(x.locality order by lower(x.locality)), array[]::text[])
    into v_localities
  from (
    select distinct on (lower(trim(src.locality))) trim(src.locality) as locality
    from unnest(coalesce(new.covered_localities, array[]::text[])) as src(locality)
    where nullif(trim(src.locality), '') is not null
    order by lower(trim(src.locality)), trim(src.locality)
  ) as x;
  new.covered_localities := coalesce(v_localities, array[]::text[]);
  if new.coverage_mode = 'pincode' then
    new.covered_localities := array[]::text[];
  elsif new.coverage_mode <> 'selected_areas' then
    raise exception 'Choose either entire PIN code or selected localities.' using errcode = '22023';
  elsif cardinality(new.covered_localities) = 0 then
    raise exception 'Select at least one locality, or choose entire PIN code.' using errcode = '22023';
  end if;
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, (select auth.uid()));
  else
    new.created_by := old.created_by;
  end if;
  new.updated_by := (select auth.uid());
  new.updated_at := now();
  return new;
end;
$function$;

create or replace function public.is_serviceable_location(p_pincode text, p_location_text text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_pin text := trim(coalesce(p_pincode, ''));
  v_mode text;
  v_localities text[];
  v_location text := lower(trim(coalesce(p_location_text, '')));
begin
  if v_pin !~ '^[1-9][0-9]{5}$' then return false; end if;
  select a.coverage_mode, a.covered_localities into v_mode, v_localities
  from public.service_areas a where a.pincode = v_pin and a.active = true limit 1;
  if not found then return false; end if;
  if v_mode = 'pincode' then return true; end if;
  if v_location = '' then return false; end if;
  return exists (
    select 1 from unnest(coalesce(v_localities, array[]::text[])) as locality(name)
    where lower(trim(locality.name)) = v_location
       or (char_length(trim(locality.name)) >= 3
           and strpos(v_location, lower(trim(locality.name))) > 0)
  );
end;
$function$;

revoke all on function public.is_serviceable_location(text, text) from public;
grant execute on function public.is_serviceable_location(text, text) to anon, authenticated;

-- Validate serviceability at insert/update boundaries too, not only in the client.
create or replace function public.enforce_order_area_coverage()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_pin text := upper(trim(coalesce(
    nullif(new.delivery_address_snapshot->>'postal_code', ''),
    nullif(new.delivery_address_snapshot->>'area_code', ''), ''
  )));
  v_location text := concat_ws(' ',
    new.delivery_address_snapshot->>'locality',
    new.delivery_address_snapshot->>'address_line1',
    new.delivery_address_snapshot->>'address_line2',
    new.delivery_address_snapshot->>'city',
    new.delivery_address_snapshot->>'district'
  );
begin
  if exists (select 1 from public.service_areas)
     and not public.is_serviceable_location(v_pin, v_location) then
    raise exception 'This address is outside the selected serviceable localities for PIN code %.', v_pin
      using errcode = 'P0002';
  end if;
  return new;
end;
$function$;
drop trigger if exists orders_enforce_area_coverage on public.orders;
create trigger orders_enforce_area_coverage
before insert or update of delivery_address_snapshot on public.orders
for each row execute function public.enforce_order_area_coverage();

create or replace function public.enforce_ride_area_coverage()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_pin text := upper(trim(coalesce(new.area_code, '')));
begin
  if exists (select 1 from public.service_areas)
     and not public.is_serviceable_location(v_pin, new.pickup_label) then
    raise exception 'This ride pickup is outside the selected serviceable localities for PIN code %.', v_pin
      using errcode = 'P0002';
  end if;
  return new;
end;
$function$;
drop trigger if exists rides_enforce_area_coverage on public.rides;
create trigger rides_enforce_area_coverage
before insert or update of area_code, pickup_label on public.rides
for each row execute function public.enforce_ride_area_coverage();

create or replace function public.partner_set_availability(
  p_role text, p_area_code text, p_is_online boolean,
  p_latitude double precision default null, p_longitude double precision default null
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_area text := upper(trim(coalesce(p_area_code, 'DEFAULT')));
begin
  if (select auth.uid()) is null then raise exception 'Sign in before changing availability.' using errcode = '42501'; end if;
  if p_role not in ('driver_partner', 'delivery_partner') then raise exception 'Invalid partner role.' using errcode = '22023'; end if;
  if not exists (select 1 from public.user_roles ur where ur.user_id = (select auth.uid()) and ur.role = p_role) then
    raise exception 'Your account is not approved for this partner role.' using errcode = '42501';
  end if;
  if v_area = '' or char_length(v_area) > 40 then raise exception 'Choose a valid service area.' using errcode = '22023'; end if;
  if exists (select 1 from public.service_areas) and (
    v_area !~ '^[1-9][0-9]{5}$'
    or not exists (select 1 from public.service_areas a where a.pincode = v_area and a.active = true)
  ) then
    raise exception 'Choose an active 6-digit service PIN code before changing availability.' using errcode = '22023';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
     or (p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180)) then
    raise exception 'Invalid coordinates.' using errcode = '22023';
  end if;
  insert into public.partner_presence(user_id, role, area_code, is_online, latitude, longitude, updated_at)
  values ((select auth.uid()), p_role, v_area, coalesce(p_is_online, false), p_latitude, p_longitude, now())
  on conflict (user_id, role) do update
    set area_code = excluded.area_code, is_online = excluded.is_online,
        latitude = excluded.latitude, longitude = excluded.longitude, updated_at = now();
  insert into public.audit_events(actor_id, action, entity_type, metadata)
  values ((select auth.uid()), case when p_is_online then 'partner.online' else 'partner.offline' end,
    'partner_presence', jsonb_build_object('role', p_role, 'area_code', v_area));
  if p_is_online then
    perform private.dispatch_pending_rides(v_area);
    perform private.dispatch_pending_deliveries(v_area);
  end if;
end;
$function$;
revoke all on function public.partner_set_availability(text, text, boolean, double precision, double precision) from public, anon;
grant execute on function public.partner_set_availability(text, text, boolean, double precision, double precision) to authenticated;

alter table public.role_requests
  add column if not exists needs_correction boolean not null default false,
  add column if not exists correction_reason text;

drop policy if exists role_requests_resubmit_correction_own on public.role_requests;
create policy role_requests_resubmit_correction_own on public.role_requests
for update to authenticated
using (user_id = (select auth.uid()) and status = 'pending' and needs_correction = true)
with check (user_id = (select auth.uid()) and status = 'pending' and needs_correction = false
  and reviewed_at is null and reviewed_by is null);

create or replace function public.guard_role_request_applicant_update()
returns trigger language plpgsql set search_path = ''
as $function$
begin
  if old.user_id = (select auth.uid()) and not coalesce((select private.has_role('admin')), false) then
    if not ((old.status = 'rejected') or (old.status = 'pending' and old.needs_correction = true)) then
      raise exception 'This application is locked while Admin reviews it.' using errcode = '42501';
    end if;
    if new.user_id is distinct from old.user_id or new.requested_role is distinct from old.requested_role
       or new.status <> 'pending' or new.needs_correction
       or new.reviewed_at is not null or new.reviewed_by is not null then
      raise exception 'Only the application details may be corrected.' using errcode = '42501';
    end if;
    new.correction_reason := null;
    new.rejection_reason := null;
  end if;
  return new;
end;
$function$;
drop trigger if exists role_requests_guard_applicant_update on public.role_requests;
create trigger role_requests_guard_applicant_update before update on public.role_requests
for each row execute function public.guard_role_request_applicant_update();

create or replace function public.admin_review_role_request(
  p_request_id uuid, p_approve boolean, p_rejection_reason text default null
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.role_requests%rowtype;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'Administrator role required.' using errcode = '42501';
  end if;
  select * into v_request from public.role_requests where id = p_request_id for update;
  if not found then raise exception 'Application not found.' using errcode = 'P0002'; end if;
  if v_request.status <> 'pending' then raise exception 'Only pending applications can be reviewed.' using errcode = '22023'; end if;
  if p_approve then
    perform public.admin_grant_user_role(v_request.user_id, v_request.requested_role);
    update public.role_requests set status = 'approved', reviewed_at = now(), reviewed_by = (select auth.uid()),
      needs_correction = false, correction_reason = null, rejection_reason = null, updated_at = now()
    where id = p_request_id;
  else
    update public.role_requests set status = 'rejected', reviewed_at = now(), reviewed_by = (select auth.uid()),
      needs_correction = false, correction_reason = null,
      rejection_reason = coalesce(nullif(trim(p_rejection_reason), ''),
        'Please review your details and contact Alteo support if you need help.'), updated_at = now()
    where id = p_request_id;
  end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), case when p_approve then 'role_request.approved' else 'role_request.rejected' end,
    'role_request', p_request_id, jsonb_build_object('user_id', v_request.user_id, 'role', v_request.requested_role));
end;
$function$;

create or replace function public.admin_request_role_correction(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_user_id uuid; v_role text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then raise exception 'Administrator role required.' using errcode = '42501'; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Please provide a correction reason of at least 5 characters.' using errcode = '22023'; end if;
  update public.role_requests set needs_correction = true, correction_reason = trim(p_reason), updated_at = now()
    where id = p_request_id and status = 'pending'
    returning user_id, requested_role into v_user_id, v_role;
  if not found then raise exception 'Only pending applications can be returned for correction.' using errcode = '22023'; end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'role_request.correction_requested', 'role_request', p_request_id,
    jsonb_build_object('user_id', v_user_id, 'role', v_role, 'reason', trim(p_reason)));
end;
$function$;
revoke all on function public.admin_review_role_request(uuid, boolean, text) from public, anon;
revoke all on function public.admin_request_role_correction(uuid, text) from public, anon;
grant execute on function public.admin_review_role_request(uuid, boolean, text) to authenticated;
grant execute on function public.admin_request_role_correction(uuid, text) to authenticated;

create table if not exists public.service_ratings (
  id uuid primary key default gen_random_uuid(),
  transaction_type text not null check (transaction_type in ('ride', 'delivery', 'order', 'dark_store_task')),
  transaction_id uuid not null,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  reviewer_role text not null check (reviewer_role in ('customer', 'driver_partner', 'delivery_partner', 'seller', 'dark_store')),
  subject_role text not null check (subject_role in ('customer', 'driver_partner', 'delivery_partner', 'seller', 'dark_store')),
  subject_id uuid not null,
  score smallint not null check (score between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500),
  status text not null default 'published' check (status in ('published', 'reported', 'hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (transaction_type, transaction_id, reviewer_id, subject_role, subject_id)
);
create index if not exists service_ratings_subject_idx on public.service_ratings(subject_role, subject_id, status, created_at desc);
create index if not exists service_ratings_reviewer_idx on public.service_ratings(reviewer_id, created_at desc);
alter table public.service_ratings enable row level security;
revoke all on public.service_ratings from anon, authenticated;
grant select on public.service_ratings to authenticated;

drop policy if exists service_ratings_read_participants_or_admin on public.service_ratings;
create policy service_ratings_read_participants_or_admin on public.service_ratings
for select to authenticated
using (
  reviewer_id = (select auth.uid())
  or (select private.has_role('admin'))
  or (subject_role in ('customer', 'driver_partner', 'delivery_partner') and subject_id = (select auth.uid()))
  or (subject_role = 'seller' and exists (
    select 1 from public.sellers s where s.id = service_ratings.subject_id and s.owner_id = (select auth.uid())
  ))
  or (subject_role = 'dark_store' and exists (
    select 1 from public.dark_stores ds where ds.id = service_ratings.subject_id and ds.owner_user_id = (select auth.uid())
  ))
);

create or replace function public.submit_service_rating(
  p_transaction_type text, p_transaction_id uuid, p_reviewer_role text,
  p_score integer, p_comment text default null
)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_customer uuid; v_partner uuid; v_seller uuid; v_store uuid; v_store_owner uuid;
  v_order uuid; v_status text; v_order_status text; v_task_status text;
  v_subject_role text; v_subject_id uuid; v_rating_id uuid;
  v_comment text := nullif(trim(coalesce(p_comment, '')), '');
begin
  if v_actor is null then raise exception 'Sign in before submitting a rating.' using errcode = '42501'; end if;
  if p_reviewer_role is null or p_reviewer_role not in ('customer', 'driver_partner', 'delivery_partner', 'seller', 'dark_store')
     or not exists (select 1 from public.user_roles ur where ur.user_id = v_actor and ur.role = p_reviewer_role) then
    raise exception 'Your account does not have this reviewer role.' using errcode = '42501';
  end if;
  if p_score is null or p_score not between 1 and 5 then raise exception 'Choose a rating from 1 to 5 stars.' using errcode = '22023'; end if;
  if char_length(coalesce(v_comment, '')) > 500 then raise exception 'Feedback must be 500 characters or fewer.' using errcode = '22023'; end if;

  if p_transaction_type = 'ride' then
    select r.customer_id, r.driver_id, r.status into v_customer, v_partner, v_status from public.rides r where r.id = p_transaction_id;
    if not found or v_status <> 'completed' then raise exception 'Only completed rides can be rated.' using errcode = '22023'; end if;
    if p_reviewer_role = 'customer' and v_customer = v_actor and v_partner is not null then
      v_subject_role := 'driver_partner'; v_subject_id := v_partner;
    elsif p_reviewer_role = 'driver_partner' and v_partner = v_actor then
      v_subject_role := 'customer'; v_subject_id := v_customer;
    else raise exception 'You are not eligible to rate this ride.' using errcode = '42501'; end if;

  elsif p_transaction_type = 'delivery' then
    select d.customer_id, d.delivery_partner_id, d.status into v_customer, v_partner, v_status from public.delivery_jobs d where d.id = p_transaction_id;
    if not found or v_status <> 'delivered' then raise exception 'Only completed deliveries can be rated.' using errcode = '22023'; end if;
    if p_reviewer_role = 'customer' and v_customer = v_actor and v_partner is not null then
      v_subject_role := 'delivery_partner'; v_subject_id := v_partner;
    elsif p_reviewer_role = 'delivery_partner' and v_partner = v_actor then
      v_subject_role := 'customer'; v_subject_id := v_customer;
    else raise exception 'You are not eligible to rate this delivery.' using errcode = '42501'; end if;

  elsif p_transaction_type = 'order' then
    select o.customer_id, o.seller_id, o.status into v_customer, v_seller, v_status from public.orders o where o.id = p_transaction_id;
    if not found or v_status not in ('delivered', 'completed') then raise exception 'Only completed orders can be rated.' using errcode = '22023'; end if;
    if p_reviewer_role = 'customer' and v_customer = v_actor then
      v_subject_role := 'seller'; v_subject_id := v_seller;
    elsif p_reviewer_role = 'seller' and exists (
      select 1 from public.sellers s where s.id = v_seller and s.owner_id = v_actor and s.status = 'approved'
    ) then
      v_subject_role := 'customer'; v_subject_id := v_customer;
    else raise exception 'You are not eligible to rate this order.' using errcode = '42501'; end if;

  elsif p_transaction_type = 'dark_store_task' then
    select dt.order_id, dt.store_id, ds.owner_user_id, dt.status, o.customer_id, o.status
      into v_order, v_store, v_store_owner, v_task_status, v_customer, v_order_status
    from public.dark_store_tasks dt
    join public.dark_stores ds on ds.id = dt.store_id
    join public.orders o on o.id = dt.order_id
    where dt.id = p_transaction_id;
    if not found or v_task_status <> 'handed_over' then raise exception 'Only handed-over fulfilment tasks can be rated.' using errcode = '22023'; end if;
    if p_reviewer_role = 'dark_store' and v_store_owner = v_actor then
      v_subject_role := 'customer'; v_subject_id := v_customer;
    elsif p_reviewer_role = 'customer' and v_customer = v_actor and v_order_status in ('delivered', 'completed') then
      v_subject_role := 'dark_store'; v_subject_id := v_store;
    else raise exception 'You are not eligible to rate this fulfilment.' using errcode = '42501'; end if;
  else
    raise exception 'Unsupported transaction type.' using errcode = '22023';
  end if;

  insert into public.service_ratings(transaction_type, transaction_id, reviewer_id, reviewer_role, subject_role, subject_id, score, comment, status, updated_at)
  values (p_transaction_type, p_transaction_id, v_actor, p_reviewer_role, v_subject_role, v_subject_id, p_score, v_comment, 'published', now())
  returning id into v_rating_id;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (v_actor, 'service_rating.submitted', 'service_rating', v_rating_id,
    jsonb_build_object('transaction_type', p_transaction_type, 'transaction_id', p_transaction_id,
      'reviewer_role', p_reviewer_role, 'subject_role', v_subject_role, 'score', p_score));
  return v_rating_id;
exception when unique_violation then
  raise exception 'You have already rated this completed work item.' using errcode = '23505';
end;
$function$;

create or replace function public.admin_moderate_service_rating(p_rating_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then raise exception 'Administrator role required.' using errcode = '42501'; end if;
  if p_status not in ('published', 'reported', 'hidden') then raise exception 'Invalid rating moderation status.' using errcode = '22023'; end if;
  update public.service_ratings set status = p_status, updated_at = now() where id = p_rating_id;
  if not found then raise exception 'Rating not found.' using errcode = 'P0002'; end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'service_rating.moderated', 'service_rating', p_rating_id, jsonb_build_object('status', p_status));
end;
$function$;

revoke all on function public.submit_service_rating(text, uuid, text, integer, text) from public, anon;
revoke all on function public.admin_moderate_service_rating(uuid, text) from public, anon;
grant execute on function public.submit_service_rating(text, uuid, text, integer, text) to authenticated;
grant execute on function public.admin_moderate_service_rating(uuid, text) to authenticated;

create or replace function public.admin_grant_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_application jsonb := '{}'::jsonb;
  v_display_name text;
  v_phone text;
  v_email text;
  v_area text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_user_id is null or p_role not in ('admin','customer','driver_partner','delivery_partner','seller','dark_store') then
    raise exception 'invalid user or role' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  insert into public.user_roles(user_id, role, granted_by)
  values (p_user_id, p_role, (select auth.uid()))
  on conflict (user_id, role) do nothing;

  select coalesce(rr.application_data, '{}'::jsonb), rr.display_name, rr.phone, rr.email
    into v_application, v_display_name, v_phone, v_email
    from public.role_requests rr
   where rr.user_id = p_user_id and rr.requested_role = p_role
   order by rr.requested_at desc limit 1;

  v_application := coalesce(v_application, '{}'::jsonb);
  v_area := coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), 'DEFAULT');

  -- Driver and delivery approvals must use an active six-digit service PIN.
  if p_role in ('driver_partner', 'delivery_partner') then
    v_area := coalesce(nullif(trim(v_application->>'service_area'), ''),
                       nullif(trim(v_application->>'service_area_pincode'), ''), '');
    if v_area !~ '^[1-9][0-9]{5}

  if p_role = 'seller' then
    if exists (select 1 from public.sellers s where s.owner_id = p_user_id) then
      update public.sellers
         set display_name = coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), display_name),
             phone = coalesce(nullif(trim(v_phone), ''), phone),
             contact_email = coalesce(nullif(trim(v_email), ''), contact_email),
             status = 'approved', updated_at = now()
       where owner_id = p_user_id;
    else
      insert into public.sellers(owner_id, display_name, phone, contact_email, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Seller'),
              nullif(trim(v_phone), ''), nullif(trim(v_email), ''), 'approved');
    end if;
  elsif p_role = 'dark_store' then
    if exists (select 1 from public.dark_stores ds where ds.owner_user_id = p_user_id) then
      update public.dark_stores
         set name = coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), name),
             locality = coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), locality),
             status = 'active', updated_at = now()
       where owner_user_id = p_user_id;
    else
      insert into public.dark_stores(owner_user_id, name, locality, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Dark Store'),
              coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), 'Not specified'), 'active');
    end if;
  elsif p_role in ('driver_partner', 'delivery_partner') then
    insert into public.partner_presence(user_id, role, area_code, is_online, updated_at)
    values (p_user_id, p_role, v_area, false, now())
    on conflict (user_id, role) do update
      set area_code = excluded.area_code, updated_at = now();
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'user.role_granted', 'user', p_user_id, jsonb_build_object('role', p_role));
end;
$function$;
 then
      raise exception 'Select a valid 6-digit service PIN code in the applicant onboarding form before approving.' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.service_areas a where a.pincode = v_area and a.active = true
    ) then
      raise exception 'The applicant selected a PIN code that is not active in Admin > Service Areas.' using errcode = '22023';
    end if;
  end if;

  if p_role = 'seller' then
    if exists (select 1 from public.sellers s where s.owner_id = p_user_id) then
      update public.sellers
         set display_name = coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), display_name),
             phone = coalesce(nullif(trim(v_phone), ''), phone),
             contact_email = coalesce(nullif(trim(v_email), ''), contact_email),
             status = 'approved', updated_at = now()
       where owner_id = p_user_id;
    else
      insert into public.sellers(owner_id, display_name, phone, contact_email, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Seller'),
              nullif(trim(v_phone), ''), nullif(trim(v_email), ''), 'approved');
    end if;
  elsif p_role = 'dark_store' then
    if exists (select 1 from public.dark_stores ds where ds.owner_user_id = p_user_id) then
      update public.dark_stores
         set name = coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), name),
             locality = coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), locality),
             status = 'active', updated_at = now()
       where owner_user_id = p_user_id;
    else
      insert into public.dark_stores(owner_user_id, name, locality, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Dark Store'),
              coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), 'Not specified'), 'active');
    end if;
  elsif p_role in ('driver_partner', 'delivery_partner') then
    insert into public.partner_presence(user_id, role, area_code, is_online, updated_at)
    values (p_user_id, p_role, v_area, false, now())
    on conflict (user_id, role) do update
      set area_code = excluded.area_code, updated_at = now();
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'user.role_granted', 'user', p_user_id, jsonb_build_object('role', p_role));
end;
$function$;


revoke all on function public.admin_grant_user_role(uuid, text) from public, anon;
grant execute on function public.admin_grant_user_role(uuid, text) to authenticated;
