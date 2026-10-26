alter table public.role_requests
  add column if not exists email text,
  add column if not exists display_name text;
