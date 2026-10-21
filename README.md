# Alteo

Alteo is a multi-service platform planned around six separate app experiences:

1. **Customer** — shopping, food, rides, parcels, orders and account management.
2. **Admin** — platform operations, approvals, support, reporting and configuration.
3. **Delivery Partner** — order delivery assignments, navigation, delivery status and earnings.
4. **Driver Partner** — ride availability, trip assignments, trip status and earnings.
5. **Seller** — catalogue, pricing, inventory and order fulfilment.
6. **Dark Store** — stock management, picking, packing and dispatch.

## Project status

This repository was created as a clean starting point. No application implementation has been started yet.

- **Mobile apps:** Flutter / Dart is the intended app stack.
- **Backend:** A dedicated Supabase project named `Alteo` has been created.
- **Authentication:** Provider and role flows still need to be designed and configured.
- **Database:** Application tables and migrations have not yet been added.
- **Payments, maps, notifications and fulfilment:** To be designed and integrated after requirements are agreed.

## Architecture principles

- Keep the six app experiences logically separated, while sharing one documented backend and common domain rules where appropriate.
- Treat the database and trusted server-side functions as the authority for order status, pricing, stock, permissions and payments.
- Enforce Row Level Security for exposed database tables and test access rules for every role.
- Never commit secrets, service-role keys, signing keys, passwords, or production credentials.
- Store schema changes as reviewed, version-controlled migrations.
- Use mock data only in explicitly labelled development/demo flows; production flows must use real, validated services.

## Repository setup

This repository is currently an empty project scaffold. The app structure, CI, database migrations, environment configuration and automated tests will be added deliberately in subsequent steps.

Before production work, review repository visibility and protect the default branch.