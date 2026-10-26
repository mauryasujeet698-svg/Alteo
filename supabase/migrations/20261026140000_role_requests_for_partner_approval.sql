-- Authenticated users can request operational roles; only admins can review them.
create table if not exists public.role_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  requested_role text not null check (requested_role in ('driver_partner','delivery_partner','seller','dark_store')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  unique (user_id, requested_role)
);
alter table public.role_requests enable row level security;
grant select, insert, update on public.role_requests to authenticated;
drop policy if exists role_requests_read_own_or_admin on public.role_requests;
create policy role_requests_read_own_or_admin on public.role_requests
for select to authenticated
using (user_id = (select auth.uid()) or (select private.has_role('admin')));
drop policy if exists role_requests_insert_own on public.role_requests;
create policy role_requests_insert_own on public.role_requests
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and requested_role in ('driver_partner','delivery_partner','seller','dark_store')
  and status = 'pending'
  and reviewed_at is null
  and reviewed_by is null
);
drop policy if exists role_requests_update_admin_only on public.role_requests;
create policy role_requests_update_admin_only on public.role_requests
for update to authenticated
using ((select private.has_role('admin')))
with check ((select private.has_role('admin')));
