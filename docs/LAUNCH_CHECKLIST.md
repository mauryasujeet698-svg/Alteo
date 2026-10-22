# Alteo launch checklist

## Required configuration before real users can sign in
1. In Supabase Dashboard → Authentication → Sign In / Providers, enable Phone.
2. Configure a supported SMS provider and verify delivery, OTP expiry, rate limits and India sender/template compliance. The app cannot send OTP until this is configured.
3. Keep Row Level Security enabled. The public read policies in `202610220001_public_catalogue_read_policies.sql` intentionally expose only active banners and active products belonging to approved sellers.
4. Assign `user_roles` rows to approved staff accounts for `admin`, `seller`, `driver_partner` and `delivery_partner`. Never allow clients to grant themselves roles.
5. Add live banner rows in `app_banners` with `active=true`, suitable `image_url`, priority and optional start/end dates. No banner is hardcoded in the app.
6. Approve seller records and publish active products with valid `price_minor` (price in minor currency units) and public `image_url` values.

## Required before accepting payments/orders
- Implement and test server-side checkout/order creation with stock validation, idempotency, delivery address snapshot, delivery fee, cancellations/refunds and audit trail. Do not let the mobile app set order totals or payment status.
- Configure a payment gateway and webhook signature verification; COD policy and cash reconciliation need explicit business rules.
- Connect dispatch, delivery assignment, driver availability, live location and customer order tracking to server-side functions and realtime subscriptions.
- Add service-area/availability controls, support escalation, abuse/rate-limit monitoring and operational alerts.
- Publish privacy policy, terms, cancellation/refund policy, contact details and required Indian business/tax/compliance information.
- Restrict the Mapbox public token to the required APIs and allowed Android package/signing fingerprints if using Mapbox tiles. OpenStreetMap is the fallback and is subject to its tile usage policy.

## App and release notes
- The repository now builds separate arm64 APKs for Customer, Admin, Seller, Driver Partner and Delivery Partner.
- CI enforces a 25 MiB maximum APK size per arm64 build. This is an APK download-size target, not a Play Store AAB size guarantee.
- Admin/staff apps currently provide secure sign-in and role checks plus starter dashboards; operational screens still need implementing and testing before production.
- Customer home reads banners and products from Supabase; add-to-cart writes to the cart tables. Checkout remains disabled until server-side order and payment flows are completed.
- Test every role with separate accounts and verify that RLS denies cross-user and cross-role access. Never ship a Supabase service-role key in any mobile app.
