# Alteo Customer (Flutter)

Flutter/Dart customer app for Android and iOS. Development begins with guest-first browsing and Google sign-in through Supabase Auth.

## Current scope

- Premium forest-green and warm-neutral design system with light and dark themes.
- Home, Explore, Orders and Profile bottom navigation.
- Clearly labelled preview catalogue, product details and local preview cart.
- Supabase configuration boundary for Google OAuth; live auth requires dashboard provider and redirect setup.
- Checkout is intentionally disabled until database, order API, payment verification and RLS rules are implemented and tested.

## Local setup

Install Flutter stable with a Dart SDK compatible with the package constraints, then run:

    cd apps/customer
    flutter pub get
    flutter analyze
    flutter test
    flutter run

To connect an already configured Supabase environment:

    flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY

The publishable key is not a substitute for database security. RLS policies and server-side authorisation must be in place before private data or real ordering is enabled.

The current native Android/iOS folders are generated in CI using Flutter's platform bootstrap. The CI build output must pass before any artifact is described as verified.
