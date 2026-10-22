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

## Authentication setup

All six apps show **Google sign-in first**. Phone/SMS OTP is available as an optional fallback. OAuth cannot work until the Supabase and Google provider settings are configured; no OAuth secrets should be committed to this repository.

1. In Supabase Authentication, enable the Google provider and add the Google OAuth Web client ID and secret.
2. In Google Cloud Console, add the Supabase callback URL shown in the Supabase Google-provider settings to the OAuth client's authorized redirect URIs.
3. In Supabase Authentication URL configuration, allow the native callback `alteo://login-callback`.
4. Android builds must include the `alteo://login-callback` intent filter. The GitHub Actions build workflow generates Android scaffolding and adds this filter before building.
5. For phone fallback, configure an SMS provider in Supabase Auth. Leave it unused if you do not want SMS login enabled yet.
6. Admin and partner apps additionally require a matching server-managed row in `public.user_roles`; a Google account alone does not grant privileged access. Assign roles only through a trusted administrative process, never from client-side user metadata.

The CI workflow builds APKs with placeholder/empty app configuration unless secrets/variables are provided. A successful compile does not prove OAuth works against your live Supabase project. Before release, test Google sign-in on a real Android device and configure package IDs, app signing, and the production redirect/deep-link policy.

## Data isolation and battery
Read docs/SECURITY_AND_PERFORMANCE.md. Every user-owned table must have tested RLS policies; the initial migration covers profiles only. Request location only when needed, avoid continuous polling, debounce search, fetch bounded pages, stop tracking when tasks end, and never reuse private cached data between accounts.

## Implementation status
The six Flutter app targets and a shared partner-workspace package are present, and GitHub Actions checks/builds each app independently. The current scope is an implementation foundation, not a production-ready marketplace: several workflows are still starter-level and require end-to-end implementation, backend integration, security testing, real-device QA, signing, and release validation.

## Important status
This is a foundation, not a production-ready six-app platform. Authentication screens, complete database schema, role/permission model, live maps/search UI, payments, dispatch, push notifications, full RLS tests, app signing and final APKs are not complete. The Cloudinary signing function needs upload limits, strict production policy and abuse controls before release.
