# Alteo

Alteo is a multi-service platform with six separate Flutter app targets backed by one shared Supabase project.

## Apps
1. Customer — public service discovery, shopping, food, rides, parcels, orders and account management.
2. Admin — order operations, partner assignments, approvals, support and reporting.
3. Driver Partner — ride offers, trips, status and earnings.
4. Delivery Partner — delivery assignments, pickup/drop status and earnings.
5. Seller — catalogue, pricing, inventory and fulfilment.
6. Dark Store — stock, picking, packing and dispatch.

## Public exploration and protected operations
- All apps should open to public feature exploration without requiring a login.
- Authentication is only needed for protected actions and private account/business records.
- A disabled Supabase sign-in provider must never prevent the public app interface from opening.
- Public browsing does not expose private orders, addresses, earnings, inventory controls or administrative actions.
- Public screens explain which live operations require backend setup or authorised access.

## Shared backend
Supabase provides authentication, PostgreSQL, Row Level Security, Realtime and server-side functions. The migration set includes:
- Owner-scoped profiles.
- Public reads for active banners and active products from approved sellers.
- Shared role records, carts, orders, order items, ride/parcel service requests, task assignments, dark-store inventory and order status events.
- Row Level Security policies and a server-side task response function.
- Realtime publication for orders, service requests, task assignments and order status events.

Apply the SQL migrations in `supabase/migrations` to the Supabase project before expecting live operations to work. Existing deployments should review migration history and apply pending migrations in order. Never expose a service-role key in a mobile app.

## Services and environment
Configure `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `MAPBOX_PUBLIC_TOKEN` through Flutter `--dart-define` values. Mapbox tokens must be public, platform-restricted tokens. Cloudinary uploads use a Supabase Edge Function; keep the Cloudinary API secret only in server-side function secrets and harden upload limits and abuse controls before production.

## Build and release
The GitHub Actions workflow builds arm64 release APKs for all six apps, runs Flutter tests and enforces a 15 MiB APK size limit. A workflow run must finish successfully before an APK is considered deliverable. The release artifacts are uploaded by GitHub Actions and retained for 14 days.

## Current implementation status
Public exploration entry screens are now present in all six app targets. The shared operational database foundation is added, but end-to-end production workflows still require connecting the admin order/assignment UI, customer checkout and live order tracking, partner task queues and status actions, seller catalogue management, dark-store inventory operations, and verifying RLS against the actual Supabase project. The workflow must pass and the resulting APK sizes must be measured before release claims are made.
