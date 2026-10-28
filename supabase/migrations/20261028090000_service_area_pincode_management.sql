-- Serviceability by six-digit Indian PIN code.
-- A code can be entered once, then service and pricing controls are configured per area.
create table if not exists public.service_areas (
  id uuid primary key default gen_random_uuid(),
  pincode text not null unique,
  locality text,
  district text,
  state text,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_areas_pincode_format check (
    char_length(pincode) = 6 and pincode ~ '^[0-9]{6}$'
  )
);

alter table public.service_areas enable row level security;
grant select on public.service_areas to anon, authenticated;
grant insert, update, delete on public.service_areas to authenticated;

drop policy if exists service_areas_read_active_anon on public.service_areas;
create policy service_areas_read_active_anon on public.service_areas
for select to anon using (active = true);

drop policy if exists service_areas_read_authenticated on public.service_areas;
create policy service_areas_read_authenticated on public.service_areas
for select to authenticated
using (active = true or (select private.has_role('admin')));

drop policy if exists service_areas_admin_manage on public.service_areas;
create policy service_areas_admin_manage on public.service_areas
for all to authenticated
using ((select private.has_role('admin')))
with check ((select private.has_role('admin')));

create index if not exists service_areas_active_pincode_idx
on public.service_areas (pincode) where active = true;

create or replace function public.service_areas_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := now();
  new.pincode := trim(new.pincode);
  new.locality := nullif(trim(new.locality), '');
  new.district := nullif(trim(new.district), '');
  new.state := nullif(trim(new.state), '');
  return new;
end;
$function$;

drop trigger if exists service_areas_touch_updated_at on public.service_areas;
create trigger service_areas_touch_updated_at
before insert or update on public.service_areas
for each row execute function public.service_areas_touch_updated_at();

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_areas'
  ) then
    execute 'alter publication supabase_realtime add table public.service_areas';
  end if;
end;
$publication$;
