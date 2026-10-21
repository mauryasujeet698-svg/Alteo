-- Alteo operating controls and customer order RPCs (additive, no destructive operations).
create table if not exists public.service_controls (
  id uuid primary key default gen_random_uuid(),
  area_code text not null default 'DEFAULT' check (char_length(area_code) between 2 and 40),
  service text not null check (service in ('ride','parcel','food','shopping','quick')),
  enabled boolean not null default false,
  automatic_assignment boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(area_code, service)
);
create index if not exists service_controls_lookup_idx on public.service_controls(area_code, service) where enabled;

create table if not exists public.app_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 120),
  subtitle text check (char_length(subtitle) <= 240),
  image_url text,
  action_type text not null default 'none' check (action_type in ('none','service','offer','url')),
  action_value text check (char_length(action_value) <= 500),
  area_code text not null default 'DEFAULT',
  priority integer not null default 100,
  active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index if not exists app_banners_live_idx on public.app_banners(area_code, priority, starts_at, ends_at) where active;

create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code = upper(code) and char_length(code) between 3 and 40),
  title text not null check (char_length(title) between 2 and 120),
  description text check (char_length(description) <= 500),
  service text check (service in ('ride','parcel','food','shopping','quick')),
  discount_type text not null check (discount_type in ('flat','percent')),
  discount_value bigint not null check (discount_value > 0),
  minimum_order_minor bigint not null default 0 check (minimum_order_minor >= 0),
  maximum_discount_minor bigint check (maximum_discount_minor is null or maximum_discount_minor > 0),
  usage_limit integer check (usage_limit is null or usage_limit > 0),
  per_user_limit integer not null default 1 check (per_user_limit > 0),
  area_code text not null default 'DEFAULT',
  active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (discount_type <> 'percent' or discount_value <= 100),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index if not exists offers_live_idx on public.offers(area_code, service, starts_at, ends_at) where active;

alter table public.service_controls enable row level security;
alter table public.service_controls force row level security;
alter table public.app_banners enable row level security;
alter table public.app_banners force row level security;
alter table public.offers enable row level security;
alter table public.offers force row level security;
revoke all on public.service_controls, public.app_banners, public.offers from anon, authenticated;
grant select on public.service_controls, public.app_banners, public.offers to authenticated;

drop policy if exists service_controls_read_enabled on public.service_controls;
drop policy if exists service_controls_admin_all on public.service_controls;
create policy service_controls_read_enabled on public.service_controls for select to authenticated using (enabled);
create policy service_controls_admin_all on public.service_controls for all to authenticated
  using ((select private.has_role('admin'))) with check ((select private.has_role('admin')));

drop policy if exists app_banners_read_live on public.app_banners;
drop policy if exists app_banners_admin_all on public.app_banners;
create policy app_banners_read_live on public.app_banners for select to authenticated
  using (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
create policy app_banners_admin_all on public.app_banners for all to authenticated
  using ((select private.has_role('admin'))) with check ((select private.has_role('admin')));

drop policy if exists offers_read_live on public.offers;
drop policy if exists offers_admin_all on public.offers;
create policy offers_read_live on public.offers for select to authenticated
  using (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
create policy offers_admin_all on public.offers for all to authenticated
  using ((select private.has_role('admin'))) with check ((select private.has_role('admin')));

-- Delivery partners can read items only for orders assigned to them.
drop policy if exists orders_read_authorized on public.orders;
create policy orders_read_authorized on public.orders for select to authenticated
  using (
    customer_id = (select auth.uid())
    or exists (select 1 from public.sellers s where s.id = seller_id and s.owner_id = (select auth.uid()))
    or exists (select 1 from public.delivery_jobs dj where dj.order_id = orders.id and dj.delivery_partner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  );
drop policy if exists order_items_read_authorized on public.order_items;
create policy order_items_read_authorized on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (
    o.customer_id = (select auth.uid())
    or exists (select 1 from public.sellers s where s.id = o.seller_id and s.owner_id = (select auth.uid()))
    or exists (select 1 from public.delivery_jobs dj where dj.order_id = o.id and dj.delivery_partner_id = (select auth.uid()))
    or (select private.has_role('admin'))
  )));

create or replace function public.create_customer_order(
  p_items jsonb,
  p_delivery_address jsonb,
  p_idempotency_key text,
  p_delivery_fee_minor bigint default 0
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid := auth.uid();
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_product record;
  v_seller_id uuid;
  v_subtotal bigint := 0;
  v_order_id uuid;
begin
  if v_customer_id is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'cart must contain 1 to 50 items' using errcode = '22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  if p_delivery_fee_minor is null or p_delivery_fee_minor < 0 or p_delivery_fee_minor > 1000000 then
    raise exception 'invalid delivery fee' using errcode = '22023';
  end if;
  if jsonb_typeof(p_delivery_address) <> 'object'
     or coalesce(length(trim(p_delivery_address->>'recipient_name')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'phone')),0) < 8
     or coalesce(length(trim(p_delivery_address->>'address_line1')),0) < 3
     or coalesce(length(trim(p_delivery_address->>'city')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'state')),0) < 2
     or coalesce(length(trim(p_delivery_address->>'postal_code')),0) < 5 then
    raise exception 'complete delivery address required' using errcode = '22023';
  end if;

  select id into v_order_id from public.orders
    where customer_id = v_customer_id and idempotency_key = p_idempotency_key;
  if v_order_id is not null then return v_order_id; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'invalid cart item' using errcode = '22023'; end if;
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity < 1 or v_quantity > 99 then raise exception 'quantity must be between 1 and 99' using errcode = '22023'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_items) x
      where x.value->>'product_id' = v_product_id::text
      group by x.value->>'product_id' having count(*) > 1
    ) then raise exception 'duplicate products must be combined into one cart line' using errcode = '22023'; end if;
    select p.id, p.seller_id, p.name, p.price_minor
      into v_product
      from public.seller_products p join public.sellers s on s.id = p.seller_id
      where p.id = v_product_id and p.status = 'active' and s.status = 'approved'
      for share of p, s;
    if not found then raise exception 'an item is unavailable' using errcode = 'P0002'; end if;
    if v_seller_id is null then v_seller_id := v_product.seller_id;
    elsif v_seller_id <> v_product.seller_id then
      raise exception 'checkout currently supports one seller per order' using errcode = '22023';
    end if;
    v_subtotal := v_subtotal + (v_product.price_minor * v_quantity);
  end loop;
  if v_subtotal > 1000000000 then raise exception 'cart total exceeds allowed limit' using errcode = '22023'; end if;

  insert into public.orders(customer_id, seller_id, idempotency_key, status, payment_status, subtotal_minor, delivery_fee_minor, total_minor, delivery_address_snapshot)
  values (v_customer_id, v_seller_id, p_idempotency_key, 'pending_payment', 'pending', v_subtotal, p_delivery_fee_minor, v_subtotal + p_delivery_fee_minor, p_delivery_address)
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    select p.id, p.seller_id, p.name, p.price_minor
      into v_product
      from public.seller_products p join public.sellers s on s.id = p.seller_id
      where p.id = v_product_id and p.status = 'active' and s.status = 'approved'
      for share of p, s;
    if not found then raise exception 'an item became unavailable' using errcode = 'P0002'; end if;
    insert into public.order_items(order_id, product_id, product_name_snapshot, quantity, unit_price_minor, line_total_minor)
    values (v_order_id, v_product.id, v_product.name, v_quantity, v_product.price_minor, v_product.price_minor * v_quantity);
  end loop;

  insert into public.order_events(order_id, actor_id, action, detail)
  values (v_order_id, v_customer_id, 'order.created', jsonb_build_object('payment_status','pending'));
  return v_order_id;
exception when unique_violation then
  select id into v_order_id from public.orders where customer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if v_order_id is not null then return v_order_id; end if;
  raise;
end;
$$;
revoke all on function public.create_customer_order(jsonb, jsonb, text, bigint) from public, anon;
grant execute on function public.create_customer_order(jsonb, jsonb, text, bigint) to authenticated;

create index if not exists audit_events_actor_idx on public.audit_events(actor_id);
create index if not exists cart_items_product_idx on public.cart_items(product_id);
create index if not exists dark_store_inventory_product_idx on public.dark_store_inventory(product_id);
create index if not exists delivery_assignments_job_idx on public.delivery_assignments(delivery_job_id);
create index if not exists delivery_assignments_assigned_by_idx on public.delivery_assignments(assigned_by);
create index if not exists delivery_earnings_job_idx on public.delivery_earnings(delivery_job_id);
create index if not exists driver_earnings_ride_idx on public.driver_earnings(ride_id);
create index if not exists order_events_actor_idx on public.order_events(actor_id);
create index if not exists order_items_product_idx on public.order_items(product_id);
create index if not exists refunds_payment_attempt_idx on public.refunds(payment_attempt_id);
create index if not exists support_tickets_order_idx on public.support_tickets(order_id);
create index if not exists user_roles_granted_by_idx on public.user_roles(granted_by);

comment on table public.payment_attempts is 'Server-only payment provider and reconciliation data; no direct client RLS policy.';
comment on table public.refunds is 'Server-only refund and provider reconciliation data; no direct client RLS policy.';
