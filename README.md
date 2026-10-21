# Alteo

Alteo is a multi-service platform with six separate app experiences in one Flutter monorepo.

## Apps
1. Customer — shopping, food, rides, parcels, orders and account management.
2. Admin — operations, approvals, support, reporting and configuration.
3. Driver Partner — ride availability, trips, status and earnings.
4. Delivery Partner — delivery assignments, navigation, status and earnings.
5. Seller — catalogue, pricing, inventory and fulfilment.
6. Dark Store — stock, picking, packing and dispatch.

## Foundation added
- Flutter/Dart monorepo workspace using Melos.
- Customer app starter with Supabase initialization and Mapbox token configuration.
- Cloudinary upload client that requests a signed upload authorization from a Supabase Edge Function.
- Supabase profile migration with Row Level Security policies limiting profile access to the signed-in owner.
- GitHub Actions workflow for Flutter analysis and tests.
- Proprietary inspection-only license; viewing code does not grant permission to reuse it.

## Services and environment
Supabase provides auth, Postgres, RLS and Edge Functions. Mapbox provides maps/location features and must use a platform-restricted public token. Cloudinary handles media delivery and signed uploads; its API secret belongs only in Supabase Edge Function secrets. Use .env.example as a checklist, not as a place for real credentials. Pass client configuration with Flutter --dart-define values.

Before uploads can work, configure CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET as Supabase Edge Function secrets and deploy cloudinary-upload-signature. Configure SUPABASE_URL, SUPABASE_ANON_KEY and MAPBOX_PUBLIC_TOKEN for the app.

## Data isolation and battery
Read docs/SECURITY_AND_PERFORMANCE.md. Every user-owned table must have tested RLS policies; the initial migration covers profiles only. Request location only when needed, avoid continuous polling, debounce search, fetch bounded pages, stop tracking when tasks end, and never reuse private cached data between accounts.

## Build order
Customer app first. The other five apps are separate targets and will be implemented next. Shared packages will be added as common modules stabilize. Each app has its own navigation and release artifact; backend authorization remains authoritative.

## Important status
This is a foundation, not a production-ready six-app platform. Authentication screens, complete database schema, role/permission model, live maps/search UI, payments, dispatch, push notifications, full RLS tests, app signing and final APKs are not complete. The Cloudinary signing function needs upload limits, strict production policy and abuse controls before release.
