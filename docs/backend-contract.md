# Alteo Customer ↔ Backend Contract (Proposal)

Status: proposal only. This document does not mean the tables or policies exist. The connected Supabase project is intentionally unchanged pending review of the schema and security model.

## Principles

- Public browsing uses only fields and records approved for public exposure.
- The client never decides authoritative prices, tax, discount eligibility, stock, payment status, roles or order status.
- Authenticated actions are enforced server-side; hiding controls in the UI is not authorisation.
- Mutations affecting stock, orders, money or dispatch must be transactional and idempotent.
- Private customer records are isolated with Row Level Security and verified with automated tests.
- A payment is considered successful only after a trusted provider webhook or server-side verification confirms it.

## Proposed domain areas

1. Identity: auth user mapping, customer profile, addresses, consent and role assignments.
2. Location and serviceability: service areas, supported services, seller/dark-store coverage and geocoding references.
3. Catalogue: service categories, sellers, restaurants, products, variants, public media, pricing and catalogue visibility.
4. Inventory: stock by seller/dark-store, stock reservations, expiry/availability and inventory adjustment events.
5. Cart and pricing: a client cart is a convenience only; checkout recalculates price and validates inventory on the server.
6. Orders: service-specific orders and immutable item/price snapshots, state transitions, fulfilment events and cancellation rules.
7. Payments: provider references, payment attempts, captured/refunded amounts, signed webhooks and reconciliation.
8. Transport: parcel shipments, ride requests, fare quotes, driver assignment, location updates and trip events.
9. Operations: promotions, support tickets, ratings, notifications, administrative audit events and reporting.

## Initial API/repository contracts to implement

- getServiceAvailability(location, serviceType)
- searchCatalogue(query, filters, cursor, location)
- getProduct(productId) / getRestaurant(restaurantId) / getMenu(restaurantId)
- getServerPriceQuote(cart, address, offerCode)
- placeOrder(quoteId, idempotencyKey, addressId, paymentMethod)
- getCustomerOrders(cursor) / getOrder(orderId) / requestCancellation(orderId, reason)
- createRideQuote(pickup, destination, vehicleClass) / requestRide(quoteId, idempotencyKey)
- createParcelQuote(parcelDetails, pickup, dropoff) / requestParcel(quoteId, idempotencyKey)
- requestAccountDeletion() / getSupportOptions()

These are logical contracts, not confirmed existing Supabase RPC names or Edge Function endpoints.

## Before any migration is applied

1. Review every table, ownership relationship, status transition and index.
2. Define RLS policies for anonymous, customer, seller, driver, delivery partner, dark-store staff, support and administrator access.
3. Test negative cases: cross-user reads/writes, role escalation, forged price, repeated checkout, replayed webhook and expired quote.
4. Confirm backups, environment separation and rollback/recovery process.
5. Apply reviewed version-controlled migrations and run Supabase security/performance advisors.
