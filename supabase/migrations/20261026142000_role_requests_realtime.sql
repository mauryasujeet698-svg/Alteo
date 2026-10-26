do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'role_requests'
  ) then
    alter publication supabase_realtime add table public.role_requests;
  end if;
end $$;
