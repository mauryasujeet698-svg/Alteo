-- Public catalogue data is intentionally readable before customer sign-in.
-- Keep this migration self-contained for fresh database setups.
create table if not exists public.app_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text not null default '',
  image_url text not null default '',
  active boolean not null default false,
  priority integer not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.sellers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.seller_products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.sellers(id) on delete cascade,
  name text not null,
  description text not null default '',
  price_minor bigint not null default 0 check (price_minor >= 0),
  image_url text not null default '',
  kind text not null default 'shopping' check (kind in ('food', 'quick', 'shopping')),
  status text not null default 'draft' check (status in ('draft', 'active', 'archived')),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_banners enable row level security;
alter table public.sellers enable row level security;
alter table public.seller_products enable row level security;

drop policy if exists app_banners_read_live_public on public.app_banners;
create policy app_banners_read_live_public on public.app_banners
for select to anon, authenticated
using (active = true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));

drop policy if exists sellers_read_approved_public on public.sellers;
create policy sellers_read_approved_public on public.sellers
for select to anon, authenticated
using (status = 'approved');

drop policy if exists products_read_catalogue_public on public.seller_products;
create policy products_read_catalogue_public on public.seller_products
for select to anon, authenticated
using (status = 'active' and exists (
  select 1 from public.sellers s
  where s.id = seller_products.seller_id and s.status = 'approved'
));

grant select on public.app_banners, public.sellers, public.seller_products to anon, authenticated;
