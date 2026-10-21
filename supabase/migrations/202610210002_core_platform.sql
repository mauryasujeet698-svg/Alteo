-- Alteo core domain schema, authorization baseline and abuse-resistant RPCs.
-- Additive only; no existing application data is dropped.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 120),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','customer','driver_partner','delivery_partner','seller','dark_store')),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
create index if not exists user_roles_user_role_idx on public.user_roles(user_id, role);

-- This narrowly scoped definer helper reads only the caller's server-managed role.
-- user_roles has no client-side mutation grants; user_metadata is never trusted for roles.
create or replace function private.has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = required_role
  );
$$;
revoke all on function private.has_role(text) from public, anon;
grant execute on function private.has_role(text) to authenticated;

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  label text not null default 'Home' check (char_length(label) <= 40),
  recipient_name text not null check (char_length(recipient_name) <= 120),
  phone text not null check (char_length(phone) <= 20),
  address_line1 text not null check (char_length(address_line1) <= 240),
  address_line2 text check (char_length(address_line2) <= 240),
  locality text check (char_length(locality) <= 120),
  city text not null check (char_length(city) <= 120),
  state text not null check (char_length(state) <= 120),
  postal_code text not null check (char_length(postal_code) <= 12),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists addresses_user_created_idx on public.addresses(user_id, created_at desc);
create unique index if not exists addresses_one_default_per_user_idx on public.addresses(user_id) where is_default;

create table if not exists public.sellers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  display_name text not null check (char_length(display_name) between 2 and 120),
  phone text check (char_length(phone) <= 20),
  contact_email text check (char_length(contact_email) <= 254),
  status text not null default 'pending' check (status in ('pending','approved','suspended','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sellers_owner_status_idx on public.sellers(owner_id, status);
create index if not exists sellers_status_created_idx on public.sellers(status, created_at desc);

create table if not exists public.seller_products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.sellers(id) on delete restrict,
  kind text not null check (kind in ('shopping','food','quick')),
  name text not null check (char_length(name) between 1 and 180),
  description text check (char_length(description) <= 4000),
  price_minor bigint not null check (price_minor > 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status text not null default 'draft' check (status in ('draft','active','paused','rejected')),
  image_public_id text,
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists seller_products_catalog_idx on public.seller_products(status, kind, created_at desc);
create index if not exists seller_products_seller_idx on public.seller_products(seller_id, status, created_at desc);

create table if not exists public.seller_inventory (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.sellers(id) on delete restrict,
  product_id uuid not null unique references public.seller_products(id) on delete restrict,
  stock_on_hand integer not null default 0 check (stock_on_hand >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0 and reserved_quantity <= stock_on_hand),
  updated_at timestamptz not null default now()
);
create index if not exists seller_inventory_seller_idx on public.seller_inventory(seller_id, updated_at desc);

create table if not exists public.carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','converted','abandoned')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists carts_one_active_per_customer_idx on public.carts(customer_id) where status = 'active';
create index if not exists carts_customer_idx on public.carts(customer_id, created_at desc);

create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts(id) on delete cascade,
  product_id uuid not null references public.seller_products(id) on delete restrict,
  quantity integer not null check (quantity between 1 and 99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cart_id, product_id)
);
create index if not exists cart_items_cart_idx on public.cart_items(cart_id);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete restrict,
  seller_id uuid not null references public.sellers(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 16 and 128),
  status text not null default 'pending_payment' check (status in ('pending_payment','paid','accepted','preparing','ready_for_pickup','out_for_delivery','completed','cancelled','refund_pending','refunded')),
  payment_status text not null default 'pending' check (payment_status in ('pending','authorized','paid','failed','refund_pending','refunded')),
  subtotal_minor bigint not null check (subtotal_minor >= 0),
  delivery_fee_minor bigint not null default 0 check (delivery_fee_minor >= 0),
  total_minor bigint not null check (total_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  delivery_address_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, idempotency_key)
);
create index if not exists orders_customer_recent_idx on public.orders(customer_id, created_at desc);
create index if not exists orders_seller_recent_idx on public.orders(seller_id, created_at desc);
create index if not exists orders_status_recent_idx on public.orders(status, created_at desc);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id uuid not null references public.seller_products(id) on delete restrict,
  product_name_snapshot text not null,
  quantity integer not null check (quantity between 1 and 99),
  unit_price_minor bigint not null check (unit_price_minor > 0),
  line_total_minor bigint not null check (line_total_minor > 0),
  created_at timestamptz not null default now()
);
create index if not exists order_items_order_idx on public.order_items(order_id);

create table if not exists public.order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists order_events_order_recent_idx on public.order_events(order_id, created_at desc);

-- Payment provider references and reconciliation metadata are server-only.
create table if not exists public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  provider text not null,
  provider_payment_id text,
  provider_order_id text,
  status text not null check (status in ('created','pending','authorized','captured','failed','cancelled','refund_pending','refunded')),
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  idempotency_key text not null,
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, idempotency_key)
);
create index if not exists payment_attempts_order_idx on public.payment_attempts(order_id, created_at desc);

create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  status text not null check (status in ('requested','pending','succeeded','failed','cancelled')),
  amount_minor bigint not null check (amount_minor > 0),
  reason text check (char_length(reason) <= 500),
  provider_refund_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists refunds_order_idx on public.refunds(order_id, created_at desc);

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete restrict,
  driver_id uuid references auth.users(id) on delete restrict,
  status text not null default 'requested' check (status in ('requested','accepted','arrived','in_progress','completed','cancelled')),
  pickup_label text not null check (char_length(pickup_label) <= 240),
  destination_label text not null check (char_length(destination_label) <= 240),
  pickup_latitude double precision not null check (pickup_latitude between -90 and 90),
  pickup_longitude double precision not null check (pickup_longitude between -180 and 180),
  destination_latitude double precision not null check (destination_latitude between -90 and 90),
  destination_longitude double precision not null check (destination_longitude between -180 and 180),
  estimated_distance_m integer check (estimated_distance_m > 0),
  fare_minor bigint not null check (fare_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  idempotency_key text not null check (char_length(idempotency_key) between 16 and 128),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, idempotency_key)
);
create index if not exists rides_customer_recent_idx on public.rides(customer_id, created_at desc);
create index if not exists rides_driver_recent_idx on public.rides(driver_id, status, created_at desc);
create index if not exists rides_dispatch_idx on public.rides(status, created_at) where driver_id is null and status = 'requested';

create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique references public.orders(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  seller_id uuid references public.sellers(id) on delete restrict,
  delivery_partner_id uuid references auth.users(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','assigned','picked_up','in_transit','delivered','cancelled','failed')),
  tracking_code text unique,
  proof_media_public_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_jobs_customer_idx on public.delivery_jobs(customer_id, created_at desc);
create index if not exists delivery_jobs_partner_idx on public.delivery_jobs(delivery_partner_id, status, created_at desc);
create index if not exists delivery_jobs_seller_idx on public.delivery_jobs(seller_id, status, created_at desc);

create table if not exists public.delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  delivery_job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  partner_id uuid not null references auth.users(id) on delete restrict,
  assigned_by uuid references auth.users(id) on delete set null,
  status text not null check (status in ('offered','accepted','rejected','revoked','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_assignments_partner_idx on public.delivery_assignments(partner_id, status, created_at desc);

create table if not exists public.driver_earnings (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete restrict,
  ride_id uuid references public.rides(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status text not null default 'pending' check (status in ('pending','payable','paid','reversed')),
  created_at timestamptz not null default now()
);
create index if not exists driver_earnings_owner_idx on public.driver_earnings(driver_id, created_at desc);

create table if not exists public.delivery_earnings (
  id uuid primary key default gen_random_uuid(),
  delivery_partner_id uuid not null references auth.users(id) on delete restrict,
  delivery_job_id uuid references public.delivery_jobs(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status text not null default 'pending' check (status in ('pending','payable','paid','reversed')),
  created_at timestamptz not null default now()
);
create index if not exists delivery_earnings_owner_idx on public.delivery_earnings(delivery_partner_id, created_at desc);

create table if not exists public.dark_stores (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  name text not null check (char_length(name) between 2 and 120),
  locality text,
  status text not null default 'pending' check (status in ('pending','active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists dark_stores_owner_idx on public.dark_stores(owner_user_id, status);

create table if not exists public.dark_store_inventory (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.dark_stores(id) on delete restrict,
  product_id uuid not null references public.seller_products(id) on delete restrict,
  stock_on_hand integer not null default 0 check (stock_on_hand >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0 and reserved_quantity <= stock_on_hand),
  updated_at timestamptz not null default now(),
  unique(store_id, product_id)
);
create index if not exists dark_store_inventory_store_idx on public.dark_store_inventory(store_id, updated_at desc);

create table if not exists public.location_updates (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid references public.rides(id) on delete cascade,
  delivery_job_id uuid references public.delivery_jobs(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision check (accuracy_m >= 0),
  recorded_at timestamptz not null default now(),
  check ((ride_id is not null)::integer + (delivery_job_id is not null)::integer = 1)
);
create index if not exists location_updates_ride_recent_idx on public.location_updates(ride_id, recorded_at desc);
create index if not exists location_updates_delivery_recent_idx on public.location_updates(delivery_job_id, recorded_at desc);
create index if not exists location_updates_partner_recent_idx on public.location_updates(partner_id, recorded_at desc);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  title text not null check (char_length(title) <= 160),
  body text not null check (char_length(body) <= 1000),
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_recent_idx on public.notifications(user_id, created_at desc);
create index if not exists notifications_unread_idx on public.notifications(user_id, created_at desc) where read_at is null;

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  order_id uuid references public.orders(id) on delete set null,
  subject text not null check (char_length(subject) between 3 and 180),
  message text not null check (char_length(message) between 3 and 5000),
  status text not null default 'open' check (status in ('open','in_progress','waiting_for_customer','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_requester_idx on public.support_tickets(requester_id, created_at desc);
create index if not exists support_tickets_status_idx on public.support_tickets(status, created_at desc);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_events_recent_idx on public.audit_events(created_at desc);
create index if not exists audit_events_entity_idx on public.audit_events(entity_type, entity_id, created_at desc);

create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  seller_id uuid references public.sellers(id) on delete set null,
  provider text not null default 'cloudinary' check (provider = 'cloudinary'),
  public_id text not null unique,
  asset_kind text not null check (asset_kind in ('profile','product','food_listing','partner_document','delivery_proof')),
  visibility text not null default 'private' check (visibility in ('private','public')),
  secure_url text,
  created_at timestamptz not null default now()
);
create index if not exists media_assets_owner_idx on public.media_assets(owner_id, created_at desc);
create index if not exists media_assets_seller_idx on public.media_assets(seller_id, created_at desc);

create table if not exists public.pricing_rules (
  id uuid primary key default gen_random_uuid(),
  service text not null check (service in ('ride','parcel','food','shopping','quick')),
  city_code text not null default 'DEFAULT',
  base_fee_minor bigint not null default 0 check (base_fee_minor >= 0),
  per_km_minor bigint not null default 0 check (per_km_minor >= 0),
  minimum_fee_minor bigint not null default 0 check (minimum_fee_minor >= 0),
  active boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(service, city_code)
);
create index if not exists pricing_rules_active_idx on public.pricing_rules(service, city_code) where active;

-- Private media-upload quota events; no Data API access.
create table if not exists private.media_upload_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists media_upload_events_user_time_idx on private.media_upload_events(user_id, created_at desc);

-- Allows only trusted server-side service-role callers to atomically consume quota.
create or replace function public.consume_media_upload_quota(p_user_id uuid, p_max_hour integer default 20, p_max_day integer default 100)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  role_claim text;
  hourly_count integer;
  daily_count integer;
begin
  role_claim := current_setting('request.jwt.claim.role', true);
  if coalesce(role_claim, '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_user_id is null or p_max_hour < 1 or p_max_day < p_max_hour then
    raise exception 'invalid quota parameters' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select count(*)::integer into hourly_count
    from private.media_upload_events
    where user_id = p_user_id and created_at > now() - interval '1 hour';
  select count(*)::integer into daily_count
    from private.media_upload_events
    where user_id = p_user_id and created_at > now() - interval '24 hours';
  if hourly_count >= p_max_hour or daily_count >= p_max_day then return false; end if;
  insert into private.media_upload_events(user_id) values (p_user_id);
  return true;
end;
$$;
revoke all on function public.consume_media_upload_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_media_upload_quota(uuid, integer, integer) to service_role;

-- Server-managed seller approval. No user can promote their own seller record.
create or replace function public.admin_set_seller_status(p_seller_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('approved','suspended','rejected','pending') then
    raise exception 'invalid seller status' using errcode = '22023';
  end if;
  update public.sellers set status = p_status, updated_at = now() where id = p_seller_id;
  if not found then raise exception 'seller not found' using errcode = 'P0002'; end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'seller.status_changed', 'seller', p_seller_id, jsonb_build_object('status', p_status));
end;
$$;
revoke all on function public.admin_set_seller_status(uuid, text) from public, anon;
grant execute on function public.admin_set_seller_status(uuid, text) to authenticated;

-- Profiles are automatically created for new Auth users. This trigger is not callable as an API.
create or replace function public.handle_new_auth_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name)
    values (new.id, nullif(new.raw_user_meta_data ->> 'name', ''))
    on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_auth_profile() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_alteo_profile on auth.users;
create trigger on_auth_user_created_alteo_profile
after insert on auth.users
for each row execute function public.handle_new_auth_profile();

-- Force RLS on every table in the exposed public schema.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles','user_roles','addresses','sellers','seller_products','seller_inventory',
    'carts','cart_items','orders','order_items','order_events','payment_attempts','refunds',
    'rides','delivery_jobs','delivery_assignments','driver_earnings','delivery_earnings',
    'dark_stores','dark_store_inventory','location_updates','notifications','support_tickets',
    'audit_events','media_assets','pricing_rules'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
  end loop;
end $$;
alter table private.media_upload_events enable row level security;
alter table private.media_upload_events force row level security;

-- Tight grants: UI-level role checks are not the security boundary.
revoke all on public.profiles, public.user_roles, public.addresses, public.sellers, public.seller_products,
  public.seller_inventory, public.carts, public.cart_items, public.orders, public.order_items,
  public.order_events, public.payment_attempts, public.refunds, public.rides, public.delivery_jobs,
  public.delivery_assignments, public.driver_earnings, public.delivery_earnings, public.dark_stores,
  public.dark_store_inventory, public.location_updates, public.notifications, public.support_tickets,
  public.audit_events, public.media_assets, public.pricing_rules from anon, authenticated;

grant select on public.profiles, public.user_roles, public.addresses, public.sellers, public.seller_products,
  public.seller_inventory, public.carts, public.cart_items, public.orders, public.order_items,
  public.order_events, public.delivery_jobs, public.driver_earnings, public.delivery_earnings,
  public.dark_stores, public.dark_store_inventory, public.notifications, public.support_tickets,
  public.media_assets, public.pricing_rules, public.rides to authenticated;

grant insert (id, display_name, avatar_url) on public.profiles to authenticated;
grant update (display_name, avatar_url, updated_at) on public.profiles to authenticated;

grant insert (label, recipient_name, phone, address_line1, address_line2, locality, city, state, postal_code, latitude, longitude, is_default)
  on public.addresses to authenticated;
grant update (label, recipient_name, phone, address_line1, address_line2, locality, city, state, postal_code, latitude, longitude, is_default, updated_at)
  on public.addresses to authenticated;
grant delete on public.addresses to authenticated;

grant insert (display_name, phone, contact_email) on public.sellers to authenticated;
grant update (display_name, phone, contact_email, updated_at) on public.sellers to authenticated;

grant insert (seller_id, kind, name, description, price_minor, currency, image_public_id, image_url)
  on public.seller_products to authenticated;
grant update (kind, name, description, price_minor, currency, image_public_id, image_url, updated_at)
  on public.seller_products to authenticated;
grant delete on public.seller_products to authenticated;

grant insert (customer_id) on public.carts to authenticated;
grant delete on public.carts to authenticated;
grant insert (cart_id, product_id, quantity) on public.cart_items to authenticated;
grant update (quantity) on public.cart_items to authenticated;
grant delete on public.cart_items to authenticated;

grant insert (requester_id, order_id, subject, message) on public.support_tickets to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant insert (owner_id, seller_id, public_id, asset_kind, visibility, secure_url) on public.media_assets to authenticated;

-- Drop named policies first so this migration can be re-applied in a staging environment.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy profiles_admin_select on public.profiles for select to authenticated using ((select private.has_role('admin')));

drop policy if exists user_roles_select_own on public.user_roles;
drop policy if exists user_roles_admin_select on public.user_roles;
create policy user_roles_select_own on public.user_roles for select to authenticated using (user_id = (select auth.uid()));
create policy user_roles_admin_select on public.user_roles for select to authenticated using ((select private.has_role('admin')));

drop policy if exists addresses_own_select on public.addresses;
drop policy if exists addresses_own_insert on public.addresses;
drop policy if exists addresses_own_update on public.addresses;
drop policy if exists addresses_own_delete on public.addresses;
create policy addresses_own_select on public.addresses for select to authenticated using (user_id = (select auth.uid()));
create policy addresses_own_insert on public.addresses for insert to authenticated with check (user_id = (select auth.uid()));
create policy addresses_own_update on public.addresses for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy addresses_own_delete on public.addresses for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists sellers_read_authorized on public.sellers;
drop policy if exists sellers_insert_own_pending on public.sellers;
drop policy if exists sellers_update_own on public.sellers;
create policy sellers_read_authorized on public.sellers for select to authenticated
  using (owner_id = (select auth.uid()) or status = 'approved' or (select private.has_role('admin')));
create policy sellers_insert_own_pending on public.sellers for insert to authenticated
  with check (owner_id = (select auth.uid()) and status = 'pending');
create policy sellers_update_own on public.sellers for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists products_read_catalogue on public.seller_products;
drop policy if exists products_insert_own_seller_draft on public.seller_products;
drop policy if exists products_update_own_seller on public.seller_products;
drop policy if exists products_delete_own_nonactive on public.seller_products;
create policy products_read_catalogue on public.seller_products for select to authenticated
  using (
    (status = 'active' and exists (select 1 from public.sellers s where s.id = seller_id and s.status = 'approved'))
    or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  );
create policy products_insert_own_seller_draft on public.seller_products for insert to authenticated
  with check (status = 'draft' and exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid()) and s.status = 'approved'));
create policy products_update_own_seller on public.seller_products for update to authenticated
  using (exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())));
create policy products_delete_own_nonactive on public.seller_products for delete to authenticated
  using (status in ('draft','paused','rejected') and exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())));

drop policy if exists seller_inventory_read_authorized on public.seller_inventory;
create policy seller_inventory_read_authorized on public.seller_inventory for select to authenticated
  using (exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())) or (select private.has_role('admin')));

drop policy if exists carts_read_own on public.carts;
drop policy if exists carts_insert_own on public.carts;
drop policy if exists carts_delete_own on public.carts;
create policy carts_read_own on public.carts for select to authenticated using (customer_id = (select auth.uid()));
create policy carts_insert_own on public.carts for insert to authenticated with check (customer_id = (select auth.uid()) and status = 'active');
create policy carts_delete_own on public.carts for delete to authenticated using (customer_id = (select auth.uid()) and status = 'active');

drop policy if exists cart_items_read_own on public.cart_items;
drop policy if exists cart_items_insert_own on public.cart_items;
drop policy if exists cart_items_update_own on public.cart_items;
drop policy if exists cart_items_delete_own on public.cart_items;
create policy cart_items_read_own on public.cart_items for select to authenticated
  using (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()) and c.status = 'active'));
create policy cart_items_insert_own on public.cart_items for insert to authenticated
  with check (
    exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()) and c.status = 'active')
    and exists (select 1 from public.seller_products p where p.id = product_id and p.status = 'active')
  );
create policy cart_items_update_own on public.cart_items for update to authenticated
  using (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()) and c.status = 'active'))
  with check (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()) and c.status = 'active'));
create policy cart_items_delete_own on public.cart_items for delete to authenticated
  using (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()) and c.status = 'active'));

drop policy if exists orders_read_authorized on public.orders;
create policy orders_read_authorized on public.orders for select to authenticated
  using (customer_id = (select auth.uid()) or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())) or (select private.has_role('admin')));

drop policy if exists order_items_read_authorized on public.order_items;
create policy order_items_read_authorized on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (
    o.customer_id = (select auth.uid())
    or exists (select 1 from public.sellers s where s.id = o.seller_id and s.owner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  )));

drop policy if exists order_events_read_authorized on public.order_events;
create policy order_events_read_authorized on public.order_events for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (
    o.customer_id = (select auth.uid())
    or exists (select 1 from public.sellers s where s.id = o.seller_id and s.owner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  )));

drop policy if exists rides_read_participant on public.rides;
create policy rides_read_participant on public.rides for select to authenticated
  using (customer_id = (select auth.uid()) or driver_id = (select auth.uid()) or (select private.has_role('admin')));

drop policy if exists delivery_jobs_read_authorized on public.delivery_jobs;
create policy delivery_jobs_read_authorized on public.delivery_jobs for select to authenticated
  using (
    customer_id = (select auth.uid())
    or delivery_partner_id = (select auth.uid())
    or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  );

drop policy if exists delivery_assignments_read_authorized on public.delivery_assignments;
create policy delivery_assignments_read_authorized on public.delivery_assignments for select to authenticated
  using (partner_id = (select auth.uid()) or (select private.has_role('admin')));

drop policy if exists driver_earnings_read_own on public.driver_earnings;
create policy driver_earnings_read_own on public.driver_earnings for select to authenticated
  using (driver_id = (select auth.uid()) or (select private.has_role('admin')));

drop policy if exists delivery_earnings_read_own on public.delivery_earnings;
create policy delivery_earnings_read_own on public.delivery_earnings for select to authenticated
  using (delivery_partner_id = (select auth.uid()) or (select private.has_role('admin')));

drop policy if exists dark_stores_read_authorized on public.dark_stores;
create policy dark_stores_read_authorized on public.dark_stores for select to authenticated
  using (owner_user_id = (select auth.uid()) or (select private.has_role('admin')));

drop policy if exists dark_store_inventory_read_authorized on public.dark_store_inventory;
create policy dark_store_inventory_read_authorized on public.dark_store_inventory for select to authenticated
  using (exists (select 1 from public.dark_stores ds where ds.id = store_id and ds.owner_user_id = (select auth.uid())) or (select private.has_role('admin')));

drop policy if exists location_updates_read_active_participant on public.location_updates;
create policy location_updates_read_active_participant on public.location_updates for select to authenticated
  using (
    exists (select 1 from public.rides r where r.id = ride_id and r.status in ('accepted','arrived','in_progress') and (r.customer_id = (select auth.uid()) or r.driver_id = (select auth.uid())))
    or exists (select 1 from public.delivery_jobs dj where dj.id = delivery_job_id and dj.status in ('assigned','picked_up','in_transit') and (dj.customer_id = (select auth.uid()) or dj.delivery_partner_id = (select auth.uid())))
    or (select private.has_role('admin'))
  );

drop policy if exists notifications_read_own on public.notifications;
drop policy if exists notifications_mark_read_own on public.notifications;
create policy notifications_read_own on public.notifications for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_mark_read_own on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists support_tickets_read_own_admin on public.support_tickets;
drop policy if exists support_tickets_insert_own on public.support_tickets;
create policy support_tickets_read_own_admin on public.support_tickets for select to authenticated
  using (requester_id = (select auth.uid()) or (select private.has_role('admin')));
create policy support_tickets_insert_own on public.support_tickets for insert to authenticated with check (requester_id = (select auth.uid()));

drop policy if exists audit_events_admin_read on public.audit_events;
create policy audit_events_admin_read on public.audit_events for select to authenticated using ((select private.has_role('admin')));

drop policy if exists media_assets_read_owner_or_authorized_seller on public.media_assets;
drop policy if exists media_assets_insert_own on public.media_assets;
create policy media_assets_read_owner_or_authorized_seller on public.media_assets for select to authenticated
  using (owner_id = (select auth.uid()) or (select private.has_role('admin')) or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid())));
create policy media_assets_insert_own on public.media_assets for insert to authenticated
  with check (owner_id = (select auth.uid()) and (seller_id is null or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid()))));

drop policy if exists pricing_rules_read_active on public.pricing_rules;
create policy pricing_rules_read_active on public.pricing_rules for select to authenticated using (active = true);

-- Tight column-level mutation grants stop client-managed role/status/payment fields.
-- Server functions with verified identity own all financial and assignment state transitions.
