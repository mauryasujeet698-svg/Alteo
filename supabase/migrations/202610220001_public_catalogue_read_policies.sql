-- Public catalogue data is intentionally readable before customer sign-in.
drop policy if exists app_banners_read_live_public on public.app_banners;
create policy app_banners_read_live_public on public.app_banners
for select to anon
using (active = true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));

drop policy if exists products_read_catalogue_public on public.seller_products;
create policy products_read_catalogue_public on public.seller_products
for select to anon
using (status = 'active' and exists (
  select 1 from public.sellers s
  where s.id = seller_products.seller_id and s.status = 'approved'
));
