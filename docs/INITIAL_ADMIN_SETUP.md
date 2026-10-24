# Initial Alteo admin bootstrap

The live Supabase project already contains the operational schema, the public-read/admin-write app_banners table, and role-based row security. At the time of this check, no admin role grant exists yet. The first trusted administrator must be bootstrapped once before the Admin app can change banners, pricing, service controls, or assignments.

## 1. Configure Google OAuth in Supabase

1. Open Google Cloud Console and create/select a project.
2. Configure the OAuth consent screen and create an OAuth Client ID of type Web application.
3. Add this exact authorised redirect URI to the Google Web OAuth client:

   https://nkerkoptbrcadlpxffkn.supabase.co/auth/v1/callback

4. In Supabase Dashboard → Authentication → Sign In / Providers → Google, enable Google and paste the Web Client ID and Client Secret. Save.
5. In Supabase Dashboard → Authentication → URL Configuration → Redirect URLs, add all six callback URLs below:

   - com.alteo.customer://login-callback/
   - com.alteo.admin://login-callback/
   - com.alteo.driverpartner://login-callback/
   - com.alteo.deliverypartner://login-callback/
   - com.alteo.seller://login-callback/
   - com.alteo.darkstore://login-callback/

The Android build workflow inserts the matching deep-link intent filter for each APK. Do not put the Google Client Secret, a Supabase service-role key, or any other server secret in an APK.

## 2. Create the owner account

Install/open the Customer app, choose Profile → Sign in / Sign up with Google, and complete the Google flow. If Android returns to a browser instead of Alteo, confirm the callback URLs above and install a build produced after the deep-link workflow change.

## 3. Grant the first admin role

In Supabase Dashboard → Authentication → Users, copy the new owner's user UUID. Run this one-time statement in SQL Editor, replacing the UUID with the owner's verified account ID:

    insert into public.user_roles (user_id, role, granted_by)
    values ('REPLACE_WITH_OWNER_AUTH_UUID'::uuid, 'admin', 'REPLACE_WITH_OWNER_AUTH_UUID'::uuid)
    on conflict (user_id, role) do nothing;

Only run this statement for the trusted platform owner. The Admin app checks user_roles after Google sign-in. Once the first admin is granted, use the Admin app to grant roles to approved driver partners, delivery partners, sellers, and dark-store staff. A Google account by itself does not grant operational access.

## 4. Manage customer banners

Open Admin → Home → Homepage banners. Add or edit a headline, subtitle, HTTPS image URL, tap action, priority and publish status. Active banners are read by the customer app from public.app_banners; the carousel is swipeable and updates from Supabase Realtime. Unpublish or delete a banner to remove it from the customer carousel.

The table's existing RLS policies allow public users to read active banners only and allow write access only to users with the admin role. Keep those policies enabled.

## 5. Configure live services

In the Admin app, set real DEFAULT pricing and enable each service before launch. Automatic assignment remains off unless explicitly enabled. Create/approve seller and dark-store accounts and activate products before expecting a populated customer catalogue.

## Payment status

The current secure customer checkout creates orders in pending-payment state. Sellers and delivery assignment intentionally require confirmed payment. Online payment is not yet integrated; configure a payment provider or approve a separately designed cash-on-delivery workflow before processing live orders.

## Voice search

The Customer APK uses Android's speech-recognition service through the device. Microphone permission is requested by Android as needed. Text search remains available when speech recognition is unavailable.
