-- Allow signed-in users to read only their own delivery assignment records.
-- The existing RLS policy delivery_assignments_read_authorized restricts rows to
-- the authenticated partner (or an administrator); this grant makes that policy
-- reachable through the Supabase Data API.
grant select on table public.delivery_assignments to authenticated;
