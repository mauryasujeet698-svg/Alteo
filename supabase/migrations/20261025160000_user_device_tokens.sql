-- Device-scoped FCM token registration for Alteo's six Android apps.
-- Tokens are private to the signed-in user; service credentials are never stored here.
create table if not exists public.user_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id text not null check (app_id in (
    'customer', 'admin', 'seller', 'driver_partner', 'delivery_partner', 'dark_store'
  )),
  token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_device_tokens_app_token_key unique (app_id, token)
);

create index if not exists user_device_tokens_user_app_idx
  on public.user_device_tokens (user_id, app_id);

alter table public.user_device_tokens enable row level security;

drop policy if exists "Users can view their own device tokens" on public.user_device_tokens;
create policy "Users can view their own device tokens"
  on public.user_device_tokens for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can register their own device tokens" on public.user_device_tokens;
create policy "Users can register their own device tokens"
  on public.user_device_tokens for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own device tokens" on public.user_device_tokens;
create policy "Users can update their own device tokens"
  on public.user_device_tokens for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can remove their own device tokens" on public.user_device_tokens;
create policy "Users can remove their own device tokens"
  on public.user_device_tokens for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.user_device_tokens to authenticated;
