-- Cross-app feeds. RLS continues to decide which rows each authenticated client can receive.
alter publication supabase_realtime add table
  public.orders,
  public.order_items,
  public.order_events,
  public.rides,
  public.delivery_jobs,
  public.delivery_assignments,
  public.sellers,
  public.seller_products,
  public.seller_inventory,
  public.dark_stores,
  public.dark_store_inventory,
  public.app_banners,
  public.offers,
  public.partner_presence,
  public.service_controls,
  public.pricing_rules,
  public.notifications;
