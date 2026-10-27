-- Support ticket status updates should appear in the customer's Help & Support screen.
do $publication$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'support_tickets'
     ) then
    execute 'alter publication supabase_realtime add table public.support_tickets';
  end if;
end;
$publication$;
