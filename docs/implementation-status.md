# Implementation Status

This document tracks actual implementation status. A successful CI build is not proof of production readiness.

| Area | Current status | Notes |
|---|---|---|
| Flutter/Dart source foundation | In progress | Native platform projects are generated in CI until platform setup is committed and verified. |
| Visual design system | Initial implementation | Forest green, warm neutral surfaces, coral accent, light/dark themes. |
| Guest catalogue browsing | Preview only | Uses clearly labelled local sample catalogue; not connected to live inventory. |
| Product details | Preview only | Uses local sample data. |
| Local cart | Implemented in app source | Local-only convenience state; no server price or stock authority. |
| Google Sign-In | Integration boundary present | Supabase Google provider, redirect URL and mobile settings require configuration and real-device testing. |
| Checkout/orders | Not production-enabled | No real orders or payments before backend is reviewed and connected. |
| Rides/parcels/maps | Not yet implemented | Requires map/geocoding/route providers and service backend contracts. |
| Live inventory/food seller operations | Not yet implemented | Requires catalogue and fulfilment backend. |
| Database schema/RLS | Not yet created | Proposed contract is documented in backend-contract.md; live schema unchanged. |
| Android/iOS builds | CI bootstrap planned | Must pass CI before claiming an artifact is verified. |
| Google Play release | Not ready | Requires signed App Bundle, OAuth setup, real-device testing and store policy assets. |

## Release rule

Report features as implemented, tested, preview only, blocked by configuration, or not implemented. Never label a mock flow as a live production service.
