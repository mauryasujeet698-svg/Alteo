# Initial Alteo admin bootstrap

The connected Supabase project currently has no user-role grants, sellers, products, service-control rows, pricing rules or transactions. Public app exploration works without any of those records; live operations need an initial administrator.

## 1. Enable one sign-in provider
In Supabase Dashboard, open Authentication → Sign In / Providers. Enable Email (with a working email delivery configuration) or Phone (with an SMS provider). The mobile apps offer both methods, but an app cannot enable a provider on the project's behalf.

## 2. Create the owner's account
Open the Customer app, choose Sign in, and register with the enabled provider. Complete the verification step.

## 3. Grant the first admin role
In Supabase Dashboard → Authentication → Users, copy the new account's UUID. Run this one-time statement in SQL Editor, replacing the UUID with the owner's verified account ID:

```sql
insert into public.user_roles (user_id, role, granted_by)
values ('REPLACE_WITH_OWNER_AUTH_UUID'::uuid, 'admin', 'REPLACE_WITH_OWNER_AUTH_UUID'::uuid)
on conflict (user_id, role) do nothing;
```

Only run this statement for the trusted platform owner. Do not expose a service-role key in a mobile app.

## 4. Configure live services
Sign in to the Admin app. For each service you intend to launch, configure real DEFAULT pricing and then enable the service. Automatic assignment remains off unless you explicitly enable it. Create or approve seller and dark-store accounts and activate products before expecting a populated customer catalogue.

## Payment status
The current secure customer checkout creates orders in pending-payment state. Sellers and delivery assignment intentionally require confirmed payment. Do not mark an order paid manually just to bypass this guard; configure a payment provider or approve a separately designed cash-on-delivery workflow before processing live orders.
