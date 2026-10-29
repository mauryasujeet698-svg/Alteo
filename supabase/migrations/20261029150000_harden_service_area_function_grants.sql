-- Internal service-area helpers and trigger functions are not client RPC endpoints.
-- Trigger execution does not require clients to have EXECUTE privileges on these functions.
revoke all on function public.enforce_order_area_coverage() from public, anon, authenticated;
revoke all on function public.enforce_ride_area_coverage() from public, anon, authenticated;
revoke all on function public.service_areas_touch_updated_at() from public, anon, authenticated;
revoke all on function public.service_areas_audit_changes() from public, anon, authenticated;
revoke all on function public.is_serviceable_location(text, text) from public, anon, authenticated;
