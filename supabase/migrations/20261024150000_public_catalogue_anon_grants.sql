-- Allow unauthenticated customers to browse public banners and active catalogue items.
-- RLS remains enabled; these grants do not bypass row policies.
grant select on public.app_banners, public.seller_products to anon;

-- The public catalogue policy on seller_products checks approved seller rows.
-- Expose only the two seller columns needed by that policy, not owner identifiers.
grant select (id, status) on public.sellers to anon;
drop policy if exists sellers_read_approved_public on public.sellers;
create policy sellers_read_approved_public
  on public.sellers
  for select
  to anon
  using (status = 'approved');
