# Google Sign-In setup checklist

The app uses Supabase Auth's Google OAuth provider. This setup is not complete until configured and tested on physical Android and iOS devices.

## App-side configuration

Supply these build-time values; never place a service-role key in Flutter:

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY
- OAUTH_REDIRECT_URL (defaults to com.alteo.customer://login-callback/)

Example local command (substitute your real project values locally; do not commit secrets):

    cd apps/customer
    flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY

The publishable key is not a substitute for database security. Use correctly configured RLS and server-side authorisation. Never use a service-role or secret key in the app.

## Supabase dashboard steps (not applied by this repository)

1. Open Authentication → Sign In / Providers and enable Google.
2. Configure the Google provider credentials generated for the Supabase OAuth callback.
3. Add the mobile redirect URI com.alteo.customer://login-callback/ to Supabase's allowed redirect URLs.
4. Confirm session and account-deletion policies before production.
5. Test sign-in, cancellation, expired session, sign-out, app restart and redirect handling on Android and iOS.

## Native platform requirements

- Android application ID: com.alteo.customer.
- Add the redirect intent filter to the Android main activity.
- Register com.alteo.customer as a URL scheme in iOS Info.plist.
- Verify Google Cloud OAuth origins and callback configuration, SHA fingerprints if the chosen Google credential flow requires them, and the production signing identity.
- Do not commit google-services.json, GoogleService-Info.plist, OAuth client secrets or signing files.

The repository's CI bootstrap script generates Flutter's native Android/iOS folders and applies the deep-link and target-SDK settings to the generated project. Inspect and verify its output before production release.
