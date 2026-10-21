# Alteo

Alteo is a planned multi-service platform with six app experiences: Customer, Admin, Delivery Partner, Driver Partner, Seller and Dark Store.

## Repository status

- Customer app source: `apps/customer` (Flutter/Dart).
- Dedicated Supabase project: a separate, clean project named Alteo.
- Go Ride repository and backend are separate and have not been changed.
- Current customer screens use clearly labelled preview catalogue data. Real orders, payments, ride dispatch and live inventory are not yet connected.
- Supabase application schema and authentication settings have not been applied; proposed contracts live under `docs/`.

## Architecture principles

- Cross-platform Flutter codebase for Android and iOS.
- Guest-first browsing; Google sign-in for account-dependent actions.
- Server-side authority for price, inventory, roles, order transitions and payments.
- Reviewed, version-controlled migrations and tested Row Level Security.
- No privileged keys or signing secrets in client code or source control.

## Development

See [apps/customer/README.md](apps/customer/README.md) for setup, [docs/backend-contract.md](docs/backend-contract.md) for the proposed backend contract, and [docs/implementation-status.md](docs/implementation-status.md) for implementation status and limitations.

The CI workflow checks formatting, static analysis, tests and a debug Android APK build. A passing CI build is not proof of production readiness or Play Store approval.
