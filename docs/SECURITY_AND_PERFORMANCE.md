# Security and performance baseline

## User data isolation
- Enable RLS on every user-scoped table and test SELECT, INSERT, UPDATE and DELETE.
- Use auth.uid() for ownership; never trust a client-supplied user ID.
- Deny cross-user access by default. Staff access requires explicit roles and audited server-side authorization.
- Keep private Storage buckets private and use short-lived signed URLs where appropriate.
- Never ship Supabase service-role keys, Cloudinary API secrets, or Mapbox secret tokens.
- Minimize collection and retention of addresses, orders, payment metadata and precise location.

## Cloudinary
- Upload signatures are issued only to authenticated users by an Edge Function.
- The function scopes uploads to alteo/users/{auth.uid()}/...; the API secret stays in server secrets.
- Before production, enforce size/type limits, strict allowed folders, rate limits and abuse controls.
- The initial function is a foundation and needs server-side upload policy hardening before release.

## Mapbox and battery
- Use a platform-restricted public token; never ship a secret token.
- Request location only when needed and explain the purpose. Always allow manual address entry.
- Do not poll GPS continuously for browsing/search. Use a one-shot fix with timeout and balanced accuracy.
- High-frequency tracking is only for an active trip/delivery, with clear permission and visible state.
- Stop tracking on completion, cancellation, sign-out and screen disposal.
- Debounce searches, cancel stale requests, paginate records, and fetch only needed columns.
- Subscribe only to relevant realtime records and unsubscribe on disposal; avoid tight polling loops.
- Never reuse private cached data between signed-in accounts.

## Release gate
Add RLS tests for every role/table, session tests, upload abuse tests, privacy review, real-device battery profiling, dependency/license review and signed release builds.
