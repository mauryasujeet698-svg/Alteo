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

-- Seed a first editable public banner so the customer carousel is populated on launch.
insert into public.app_banners (title, subtitle, action_type, action_value, area_code, priority, active)
select 'Everyday, made easier', 'Shop essentials, discover food and book rides with Alteo.',
       'none', null, 'DEFAULT', 1, true
where not exists (select 1 from public.app_banners);
