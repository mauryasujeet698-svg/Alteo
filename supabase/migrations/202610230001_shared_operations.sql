-- Shared operational foundation for all six Alteo apps.
-- Public catalogues are readable without login; private records remain owner/role scoped.

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('customer','admin','driver_partner','delivery_partner','seller','dark_store')),
  created_at timestamptz not null default now(),
  unique(user_id, role)
);

create or replace function public.has_alteo_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = required_role
  );
$$;
revoke all on function public.has_alteo_role(text) from public;
grant execute on function public.has_alteo_role(text) to authenticated;

alter table public.user_roles enable row level security;
drop policy if exists user_roles_read_self_or_admin on public.user_roles;
create policy user_roles_read_self_or_admin on public.user_roles
for select to authenticated
using (user_id = auth.uid() or public.has_alteo_role('admin'));

-- Seller-owned catalogue management; public reads are defined in the catalogue migration.
drop policy if exists sellers_owner_read on public.sellers;
create policy sellers_owner_read on public.sellers
for select to authenticated
using (owner_id = auth.uid() or public.has_alteo_role('admin'));

drop policy if exists sellers_owner_create on public.sellers;
create policy sellers_owner_create on public.sellers
for insert to authenticated
with check (owner_id = auth.uid() and status = 'pending');

drop policy if exists sellers_admin_update on public.sellers;
create policy sellers_admin_update on public.sellers
for update to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists seller_products_owner_insert on public.seller_products;
create policy seller_products_owner_insert on public.seller_products
for insert to authenticated
with check (
  public.has_alteo_role('seller') and exists (
    select 1 from public.sellers s where s.id = seller_id and s.owner_id = auth.uid() and s.status = 'approved'
  )
);

drop policy if exists seller_products_owner_update on public.seller_products;
create policy seller_products_owner_update on public.seller_products
for update to authenticated
using (
  public.has_alteo_role('seller') and exists (
    select 1 from public.sellers s where s.id = seller_id and s.owner_id = auth.uid() and s.status = 'approved'
  )
)
with check (
  public.has_alteo_role('seller') and exists (
    select 1 from public.sellers s where s.id = seller_id and s.owner_id = auth.uid() and s.status = 'approved'
  )
);

drop policy if exists seller_products_admin_manage on public.seller_products;
create policy seller_products_admin_manage on public.seller_products
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists app_banners_admin_manage on public.app_banners;
create policy app_banners_admin_manage on public.app_banners
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

create table if not exists public.carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','checked_out','abandoned')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists carts_one_active_per_customer
on public.carts(customer_id) where status = 'active';

create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts(id) on delete cascade,
  product_id uuid not null references public.seller_products(id) on delete restrict,
  quantity integer not null default 1 check (quantity > 0 and quantity <= 99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cart_id, product_id)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete restrict,
  seller_id uuid references public.sellers(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','accepted','preparing','ready_for_pickup','assigned','picked_up','in_transit','delivered','cancelled','rejected')),
  total_minor bigint not null default 0 check (total_minor >= 0),
  delivery_address jsonb,
  customer_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.seller_products(id) on delete set null,
  product_name_snapshot text not null,
  quantity integer not null check (quantity > 0 and quantity <= 99),
  unit_price_minor bigint not null check (unit_price_minor >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete restrict,
  service_type text not null check (service_type in ('ride','parcel')),
  status text not null default 'requested'
    check (status in ('requested','assigned','accepted','in_progress','completed','cancelled','rejected')),
  pickup jsonb not null default '{}'::jsonb,
  dropoff jsonb not null default '{}'::jsonb,
  assigned_partner_id uuid references auth.users(id) on delete set null,
  assigned_role text check (assigned_role in ('driver_partner','delivery_partner')),
  quoted_price_minor bigint check (quoted_price_minor is null or quoted_price_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((service_type = 'ride' and (assigned_role is null or assigned_role = 'driver_partner'))
      or (service_type = 'parcel' and (assigned_role is null or assigned_role = 'delivery_partner')))
);

create table if not exists public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('order','ride','parcel','inventory')),
  source_id uuid not null,
  assigned_role text not null check (assigned_role in ('seller','dark_store','driver_partner','delivery_partner')),
  assigned_partner_id uuid not null references auth.users(id) on delete restrict,
  assigned_by uuid references auth.users(id) on delete set null,
  status text not null default 'assigned'
    check (status in ('assigned','accepted','rejected','in_progress','completed','cancelled')),
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists task_assignments_partner_status_idx
on public.task_assignments(assigned_partner_id, status, created_at desc);
create index if not exists orders_customer_created_idx
on public.orders(customer_id, created_at desc);
create index if not exists service_requests_customer_created_idx
on public.service_requests(customer_id, created_at desc);

create table if not exists public.dark_stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  status text not null default 'pending' check (status in ('pending','approved','suspended')),
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  dark_store_id uuid not null references public.dark_stores(id) on delete cascade,
  product_id uuid not null references public.seller_products(id) on delete restrict,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  unique(dark_store_id, product_id)
);

create table if not exists public.order_status_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  from_status text,
  to_status text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);

-- All personal and operational tables are private by default.
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.service_requests enable row level security;
alter table public.task_assignments enable row level security;
alter table public.dark_stores enable row level security;
alter table public.inventory_items enable row level security;
alter table public.order_status_events enable row level security;

drop policy if exists carts_owner_access on public.carts;
create policy carts_owner_access on public.carts
for all to authenticated
using (customer_id = auth.uid())
with check (customer_id = auth.uid());

drop policy if exists cart_items_owner_access on public.cart_items;
create policy cart_items_owner_access on public.cart_items
for all to authenticated
using (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = auth.uid()))
with check (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = auth.uid()));

drop policy if exists orders_customer_read on public.orders;
create policy orders_customer_read on public.orders
for select to authenticated
using (customer_id = auth.uid() or public.has_alteo_role('admin'));

drop policy if exists orders_customer_create on public.orders;
create policy orders_customer_create on public.orders
for insert to authenticated
with check (customer_id = auth.uid() and status = 'pending');

drop policy if exists orders_admin_manage on public.orders;
create policy orders_admin_manage on public.orders
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists order_items_customer_read on public.order_items;
create policy order_items_customer_read on public.order_items
for select to authenticated
using (exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or public.has_alteo_role('admin'))));

drop policy if exists order_items_customer_create on public.order_items;
create policy order_items_customer_create on public.order_items
for insert to authenticated
with check (exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid() and o.status = 'pending'));

drop policy if exists order_items_admin_manage on public.order_items;
create policy order_items_admin_manage on public.order_items
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists service_requests_customer_read on public.service_requests;
create policy service_requests_customer_read on public.service_requests
for select to authenticated
using (customer_id = auth.uid() or assigned_partner_id = auth.uid() or public.has_alteo_role('admin'));

drop policy if exists service_requests_customer_create on public.service_requests;
create policy service_requests_customer_create on public.service_requests
for insert to authenticated
with check (customer_id = auth.uid() and status = 'requested' and assigned_partner_id is null);

drop policy if exists service_requests_admin_manage on public.service_requests;
create policy service_requests_admin_manage on public.service_requests
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists task_assignments_read_own_or_admin on public.task_assignments;
create policy task_assignments_read_own_or_admin on public.task_assignments
for select to authenticated
using (assigned_partner_id = auth.uid() or public.has_alteo_role('admin'));

drop policy if exists task_assignments_admin_manage on public.task_assignments;
create policy task_assignments_admin_manage on public.task_assignments
for all to authenticated
using (public.has_alteo_role('admin'))
with check (public.has_alteo_role('admin'));

drop policy if exists dark_stores_owner_read on public.dark_stores;
create policy dark_stores_owner_read on public.dark_stores
for select to authenticated
using (owner_id = auth.uid() or public.has_alteo_role('admin'));

drop policy if exists inventory_store_owner_read on public.inventory_items;
create policy inventory_store_owner_read on public.inventory_items
for select to authenticated
using (public.has_alteo_role('admin') or exists (
  select 1 from public.dark_stores ds where ds.id = dark_store_id and ds.owner_id = auth.uid()
));

drop policy if exists inventory_store_owner_write on public.inventory_items;
create policy inventory_store_owner_write on public.inventory_items
for all to authenticated
using (public.has_alteo_role('admin') or (public.has_alteo_role('dark_store') and exists (
  select 1 from public.dark_stores ds where ds.id = dark_store_id and ds.owner_id = auth.uid() and ds.status = 'approved'
)))
with check (public.has_alteo_role('admin') or (public.has_alteo_role('dark_store') and exists (
  select 1 from public.dark_stores ds where ds.id = dark_store_id and ds.owner_id = auth.uid() and ds.status = 'approved'
)));

drop policy if exists order_status_events_read_own_or_admin on public.order_status_events;
create policy order_status_events_read_own_or_admin on public.order_status_events
for select to authenticated
using (public.has_alteo_role('admin') or exists (
  select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()
));

grant select on public.user_roles to authenticated;
grant select, insert, update, delete on public.carts, public.cart_items to authenticated;
grant select, insert, update, delete on public.orders, public.order_items, public.service_requests, public.task_assignments to authenticated;
grant select, insert, update, delete on public.dark_stores, public.inventory_items, public.order_status_events to authenticated;

-- Clients update assignment state through server-side functions, not arbitrary row updates.
create or replace function public.respond_to_task(task_id uuid, action text)
returns public.task_assignments
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  task public.task_assignments;
  next_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into task from public.task_assignments where id = task_id for update;
  if not found then raise exception 'Task not found'; end if;
  if not public.has_alteo_role(task.assigned_role) then raise exception 'Required partner role missing'; end if;
  if task.assigned_partner_id <> auth.uid() then raise exception 'Task is not assigned to this account'; end if;

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
  return task;
end;
$$;
revoke all on function public.respond_to_task(uuid, text) from public;
grant execute on function public.respond_to_task(uuid, text) to authenticated;

-- Enable relevant Realtime feeds for cross-app status updates.
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.service_requests;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.task_assignments;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.order_status_events;
exception when duplicate_object then null;
end $$;
