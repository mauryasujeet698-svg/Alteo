# Alteo third-party setup checklist

This checklist separates repository code from dashboard credentials and operational choices that the platform owner must configure.

## 1. Google sign-in for all six apps

Google is the only intended authentication option. Public exploration remains available without an account; protected actions require Google sign-in and role approval.

1. In Google Cloud Console, create an OAuth client of type **Web application** and configure the OAuth consent screen.
2. Add this redirect URI to the Google Web OAuth client:
   `https://nkerkoptbrcadlpxffkn.supabase.co/auth/v1/callback`
3. In Supabase → Authentication → Sign In / Providers → Google, enable Google and enter the Web Client ID and Client Secret.
4. In Supabase → Authentication → URL Configuration → Redirect URLs, add:
   - `com.alteo.customer://login-callback/`
   - `com.alteo.admin://login-callback/`
   - `com.alteo.driverpartner://login-callback/`
   - `com.alteo.deliverypartner://login-callback/`
   - `com.alteo.seller://login-callback/`
   - `com.alteo.darkstore://login-callback/`
5. Open Customer → Profile → Google sign-in once. In Supabase → Authentication → Users, copy the trusted owner account UUID.
6. Run the one-time SQL documented in `INITIAL_ADMIN_SETUP.md` to grant only the owner the `admin` role. Use Admin → Partners to grant roles to approved staff/partners afterward.

Never put the Google OAuth Client Secret or Supabase service-role key in an APK, GitHub source, or Flutter `--dart-define`.

## 2. Mapbox for Customer Ride and location search

1. In Mapbox, create a **public access token** with only the scopes the app needs for style tiles and geocoding.
2. Restrict the token to the app/project as supported by Mapbox token settings. Treat it as public client configuration, not as an API secret.
3. In GitHub → Alteo repository → Settings → Secrets and variables → Actions, add repository secret `MAPBOX_PUBLIC_TOKEN`.
4. Start a new workflow build after saving the secret. The workflow passes it as a Dart define into each app.
5. On Android, enable Location and allow the permission prompt. If a user denies it, the app still permits manual pickup and destination entry.

With no token, Ride has a map preview fallback, but Mapbox tiles, readable reverse-geocoded addresses and address search are not fully available.

## 3. Cloudinary for banner/product images

The Admin banner editor and Seller product editor support picking images from the device. The Supabase Edge Function `cloudinary-sign-upload` signs uploads for fixed asset folders after verifying the Google-authenticated user's app role. Delivery proof uploads use Cloudinary's authenticated asset type; the API Secret stays on the server.

1. Create a Cloudinary account and locate the Cloud Name, API Key and API Secret in the Cloudinary console.
2. In Supabase → Project → Edge Functions → Secrets, add:
   - `CLOUDINARY_CLOUD_NAME`
   - `CLOUDINARY_API_KEY`
   - `CLOUDINARY_API_SECRET`
3. Do **not** put the API Secret in Flutter, GitHub Actions, or any app configuration. The deployed function requires a valid Supabase session and verifies the user has the Admin role.
4. Rebuild and install the Admin APK that includes the gallery upload control.
5. Open Admin → Banners → Add/Edit → Choose image and upload to Cloudinary. Save the banner and publish it. The Customer carousel listens for changes and does not require reinstalling.

The Edge Function is deployed with JWT verification enabled. Until the three Cloudinary secrets are added, the image upload button will return a configuration error; the existing HTTPS image URL field remains usable.

For product images, use the signed-upload flow and keep the product's HTTPS URL in `seller_products.image_url`. For delivery proof, the app records the Cloudinary `public_id` through the `partner_record_delivery_proof` RPC; proof images use authenticated Cloudinary assets rather than public upload URLs. Do not put the Cloudinary API Secret or a permanent upload signature inside an app.

## 4. Live banner management

- Admin → Banners: add, edit, delete, publish/unpublish, set priority, add a tap action and enter image URL or upload a new image.
- Customer → Home: active banners are loaded from `public.app_banners`, sorted by priority, and displayed in a swipeable carousel.
- Only Admin-role users can write banners. Anonymous users can read active banners within their schedule window. Keep the existing RLS policies enabled.
- Use wide landscape artwork, ideally around 16:9, and keep headline/subtitle text short so it remains legible on small phones.

## 5. Enable and configure real services

In Admin → Home / operational settings, confirm all of the following before test bookings:
- Ride service enabled for the `DEFAULT` area and an active Ride pricing rule exists.
- A minimum fee, base fee and per-kilometre fee are configured. Test Bike, Auto and Car estimates.
- Delivery/service areas, partner coverage and availability are correct.
- Test both manual and automatic assignment only after roles and pricing are correct.
- Approve sellers, activate draft products and maintain accurate stock.
- Activate dark stores and stock records before expecting dark-store inventory to be usable.

The Ride quote endpoint estimates using the current configured pricing and a distance multiplier; it is not a live traffic-aware road-routing estimate. Use a directions/routing service for production-grade ETA and road distance.

## 6. Payments, messaging and proof-of-delivery

These require a business/provider account and explicit setup before real transactions:
- **Payments:** integrate a payment gateway (such as Razorpay or Cashfree) using server-side order creation, signed webhooks and server-verified payment status. Do not mark orders paid from the app. A COD flow should be a separately designed, audited option.
- **Push notifications:** configure Firebase Cloud Messaging for Android push delivery and store server credentials only in Edge Function secrets. Trigger notifications on accepted assignments, status changes, cancellations and customer updates.
- **Email/SMS/WhatsApp:** choose a provider, templates and consent/opt-out handling; keep provider keys on the server.
- **Delivery proof:** store image/media securely in Cloudinary or Supabase Storage, then save only the relevant public ID/reference and audit metadata against the delivery job. Define who can view proof.
- **Monitoring:** add error logging, alerting, backups, rate limits and an operational support process before public launch.

## 7. Release and update behavior

The CI workflow builds six Android ARM64 APKs, runs Dart analysis and Flutter tests, enforces the 15 MB APK limit and uploads artifacts. A release signing key has not been configured in this repository yet. Before distributing updates broadly, generate a durable release keystore, store it only as protected GitHub secrets, and use the same key and application IDs for every subsequent release. Debug/test builds signed differently may install as separate apps or fail in-place updates.

## Recommended test order

1. Configure Google and grant the owner Admin.
2. Confirm the Admin can sign in and edit a banner.
3. Add Cloudinary secrets, upload a banner image, publish it and verify Customer updates without reinstall.
4. Add the Mapbox token and verify Ride pickup location, destination search and map tiles.
5. Configure default pricing/service area; test a ride with an approved driver.
6. Approve a seller, publish test products and exercise checkout only after a payment/COD method is deliberately configured.
7. Assign a test delivery, verify delivery partner status updates, then test seller inventory and dark-store stock operations.
