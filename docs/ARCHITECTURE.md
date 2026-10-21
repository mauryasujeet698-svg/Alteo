# Alteo monorepo architecture

## Separate app experiences
- apps/customer
- apps/admin
- apps/driver_partner
- apps/delivery_partner
- apps/seller
- apps/dark_store

## Planned shared packages
- packages/design_system
- packages/authentication
- packages/data_access
- packages/maps
- packages/media
- packages/domain_models

Each app has its own navigation, authorization context, environment values and release artifact. Shared packages provide reusable code, not authorization decisions. Supabase RLS and trusted Edge Functions are the security boundary; hiding UI controls is not security.

The customer app is the first implementation target. Database migrations and tests must evolve alongside features.
