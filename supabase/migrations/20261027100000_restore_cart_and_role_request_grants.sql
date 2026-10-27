-- Restore the table privileges required by the customer cart flow.
-- Row Level Security policies continue to restrict each operation to the signed-in customer's own active cart.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.carts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.cart_items TO authenticated;

-- The role-request table is private application data. Anonymous users must never access it.
REVOKE ALL PRIVILEGES ON TABLE public.role_requests FROM anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.role_requests TO authenticated;
