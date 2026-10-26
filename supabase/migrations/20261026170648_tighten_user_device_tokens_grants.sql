REVOKE ALL PRIVILEGES ON TABLE public.user_device_tokens FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.user_device_tokens FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.user_device_tokens FROM service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_device_tokens TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_device_tokens TO service_role;
