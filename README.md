# Alteo

Alteo is a multi-service platform with six Flutter app targets connected to one Supabase project.

## Apps
1. Customer — Home, Food, Ride and Profile navigation; swipeable admin-managed banners, voice-enabled product search, shopping catalogue, cart and orders under Profile.
2. Admin — operations summary, user role grants, service controls, pricing, order monitoring, driver/delivery assignment, seller/product approvals and dark-store management.
3. Driver Partner — public feature exploration, online/offline availability, assigned rides and trip status.
4. Delivery Partner — public feature exploration, online/offline availability, assigned deliveries and pickup/transit/completion status.
5. Seller — public feature exploration, seller application, catalogue drafts, inventory and order fulfilment.
6. Dark Store — public feature exploration, inventory records and stock updates.

## Public exploration and protected operations
- Each app opens to public feature exploration without a login wall or demo-mode toggle.
- Authentication is requested only for personal or protected actions.
- If Google OAuth is not configured, public exploration remains accessible and protected actions show a setup error; there is no phone-login or OTP flow.
- Private customer records, addresses, orders, earnings, seller inventory and admin operations remain protected by Supabase Row Level Security and server-side role checks.
- A public catalogue can be empty until sellers, products, service controls and prices are configured. Empty states should be understandable rather than treated as an authentication failure.

## Existing Supabase workflows
The connected Supabase project already has the core operational schema and server-side functions. Apps use its existing tables and RPCs rather than a parallel order/task model:
- create_customer_order, create_customer_ride, create_customer_parcel
- admin_grant_user_role, admin_operations_summary, admin_set_service_control
- admin_assign_driver, admin_assign_delivery_partner
- admin_set_seller_status, admin_set_product_status, admin_create_dark_store, admin_set_dark_store_status
- seller_update_order_status, seller_set_stock
- partner_set_availability, driver_update_ride_status, partner_update_delivery_status
- dark_store_set_inventory

Realtime publication is enabled for orders, rides, delivery jobs, assignments, seller/catalogue data, inventory, service controls, pricing and relevant notifications. Row Level Security continues to determine which rows each user can receive.

## Important backend setup
See docs/INITIAL_ADMIN_SETUP.md for enabling Google OAuth, adding the six mobile redirect URLs, securely granting the first admin role, managing banners and configuring live services.

The current Supabase project has no service-control or pricing rows yet. Before live orders, rides or parcels can be created, an authorised admin must configure real DEFAULT pricing and enable the corresponding service in the Admin app. Automatic assignment is off by default; manual assignment remains available. Online payment is not yet integrated, so customer orders created through the current secure checkout remain pending payment and sellers cannot process them until payment is confirmed.

The repository's checked-in SQL history is not a full export of the already-provisioned Supabase project. Do not reset the live database or apply reconstructed schema migrations over it. The checked-in Realtime migration corresponds to the applied project migration 20261024085759.

## App configuration
Use Flutter --dart-define values for SUPABASE_URL, SUPABASE_ANON_KEY and MAPBOX_PUBLIC_TOKEN. Only a platform-restricted public Mapbox token belongs in the app. Keep service-role keys and Cloudinary API secrets server-side.

## Build and release
GitHub Actions builds arm64 release APKs for all six apps, runs Flutter tests and enforces a 15 MB APK size limit. A workflow must finish successfully and each produced APK must be measured before it is considered releasable. The build artifacts are retained by GitHub Actions for 14 days.

## Current implementation status
Public exploration screens are present across all six app targets. Admin, partner, seller and dark-store operational screens are connected to the existing Supabase streams and RPCs. Customer order history listens to order, ride and parcel updates; customer ride/parcel creation uses the existing server-side RPCs and Mapbox geocoding; checkout uses the secure customer-order RPC. Final release remains dependent on a successful CI run, real-device testing, provider configuration, active catalogue/service pricing and a payment integration or explicitly approved COD workflow.
