-- Admin-managed catalogue items and secure Supabase Storage media uploads.

grant select, insert, update, delete on table public.seller_products to authenticated;
grant select on table public.seller_products to anon;

drop policy if exists "products_admin_manage" on public.seller_products;
create policy "products_admin_manage"
on public.seller_products
for all
to authenticated
using ((select private.has_role('admin'::text)))
with check ((select private.has_role('admin'::text)));

create or replace function public.admin_ensure_platform_seller()
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin uuid;
  v_seller uuid;
begin
  v_admin := auth.uid();
  if v_admin is null or not (select private.has_role('admin'::text)) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;

  select s.id
    into v_seller
    from public.sellers s
   where s.owner_id = v_admin
     and s.display_name = 'Alteo Official Store'
   order by s.created_at asc
   limit 1;

  if v_seller is null then
    insert into public.sellers (owner_id, display_name, status)
    values (v_admin, 'Alteo Official Store', 'approved')
    returning id into v_seller;
  else
    update public.sellers
       set status = 'approved',
           updated_at = now()
     where id = v_seller;
  end if;

  return v_seller;
end;
$function$;

revoke all on function public.admin_ensure_platform_seller() from public, anon;
grant execute on function public.admin_ensure_platform_seller() to authenticated;

drop policy if exists "Authenticated users upload banner media" on storage.objects;
drop policy if exists "Authenticated users update banner media" on storage.objects;
drop policy if exists "Authenticated users delete banner media" on storage.objects;
drop policy if exists "Admins upload catalogue media" on storage.objects;
drop policy if exists "Admins update catalogue media" on storage.objects;
drop policy if exists "Admins delete catalogue media" on storage.objects;

create policy "Admins upload catalogue media"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] in ('banners', 'items')
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'gif')
  and (select private.has_role('admin'::text))
);

create policy "Admins update catalogue media"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] in ('banners', 'items')
  and (select private.has_role('admin'::text))
)
with check (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] in ('banners', 'items')
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'gif')
  and (select private.has_role('admin'::text))
);

create policy "Admins delete catalogue media"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] in ('banners', 'items')
  and (select private.has_role('admin'::text))
);
