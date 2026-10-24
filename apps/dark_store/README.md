# Alteo Dark Store

Flutter app target for public feature exploration of stock management, picking, packing and dispatch. No sign-in is required to inspect the available app sections. Real inventory and fulfilment actions must be protected by Supabase authentication and role-based permissions.

The shared backend schema is defined in `../../supabase/migrations`. Live inventory workflows require those migrations and role assignments to be configured in Supabase.
