-- Sellers can create/edit drafts and pause their own listings, but only Admin
-- can activate a listing. Any content edit is sent back to draft by the Seller UI.
drop policy if exists products_update_own_seller on public.seller_products;
create policy products_update_own_seller
on public.seller_products
for update
to authenticated
using (
  exists (
    select 1
    from public.sellers s
    where s.id = seller_products.seller_id
      and s.owner_id = (select auth.uid())
  )
)
with check (
  status in ('draft', 'paused', 'rejected')
  and exists (
    select 1
    from public.sellers s
    where s.id = seller_products.seller_id
      and s.owner_id = (select auth.uid())
  )
);

-- Defence in depth: reject an authenticated non-admin attempt to publish a product,
-- even if another permissive policy is added in the future. Trusted service-role jobs
-- remain unaffected because they do not act as an authenticated end user.
create or replace function public.prevent_seller_direct_product_activation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if (select auth.uid()) is not null
     and not (select private.has_role('admin'::text))
     and new.status = 'active' then
    raise exception 'Only an Alteo administrator can activate a product listing.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists prevent_seller_direct_product_activation on public.seller_products;
create trigger prevent_seller_direct_product_activation
before insert or update of status on public.seller_products
for each row execute function public.prevent_seller_direct_product_activation();

-- Record seller-submitted content edits so Admin review decisions can be traced.
create or replace function public.audit_seller_product_content_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values (
      (select auth.uid()), 'product.created', 'seller_product', new.id,
      jsonb_build_object(
        'seller_id', new.seller_id,
        'status', new.status,
        'kind', new.kind,
        'name', new.name,
        'price_minor', new.price_minor,
        'image_attached', coalesce(new.image_url, '') <> ''
      )
    );
    return new;
  elsif tg_op = 'UPDATE' then
    if old.name is distinct from new.name
       or old.description is distinct from new.description
       or old.kind is distinct from new.kind
       or old.price_minor is distinct from new.price_minor
       or old.image_url is distinct from new.image_url then
      insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
      values (
        (select auth.uid()), 'product.content_updated', 'seller_product', new.id,
        jsonb_build_object(
          'seller_id', new.seller_id,
          'status_before', old.status,
          'status_after', new.status,
          'name_changed', old.name is distinct from new.name,
          'description_changed', old.description is distinct from new.description,
          'kind_changed', old.kind is distinct from new.kind,
          'price_changed', old.price_minor is distinct from new.price_minor,
          'image_changed', old.image_url is distinct from new.image_url
        )
      );
    end if;
    return new;
  else
    insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values (
      (select auth.uid()), 'product.deleted', 'seller_product', old.id,
      jsonb_build_object('seller_id', old.seller_id, 'status', old.status, 'name', old.name)
    );
    return old;
  end if;
end;
$function$;

drop trigger if exists audit_seller_product_content_changes on public.seller_products;
create trigger audit_seller_product_content_changes
after insert or update or delete on public.seller_products
for each row execute function public.audit_seller_product_content_changes();
