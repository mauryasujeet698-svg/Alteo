-- Seller-owned stock management with audited, validated inventory updates.

create or replace function public.seller_set_stock(p_seller_id uuid, p_product_id uuid, p_stock_on_hand integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seller_status text;
  v_product_seller uuid;
  v_reserved integer := 0;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  if p_stock_on_hand is null or p_stock_on_hand < 0 or p_stock_on_hand > 1000000 then
    raise exception 'stock must be between 0 and 1000000' using errcode='22023';
  end if;
  select status into v_seller_status from public.sellers
    where id=p_seller_id and owner_id=(select auth.uid()) for update;
  if not found or v_seller_status <> 'approved' then
    raise exception 'seller must be approved and belong to this account' using errcode='42501';
  end if;
  select seller_id into v_product_seller from public.seller_products where id=p_product_id for update;
  if not found or v_product_seller <> p_seller_id then raise exception 'product does not belong to this seller' using errcode='42501'; end if;
  select reserved_quantity into v_reserved from public.seller_inventory where product_id=p_product_id for update;
  v_reserved := coalesce(v_reserved,0);
  if p_stock_on_hand < v_reserved then raise exception 'stock cannot be lower than reserved quantity' using errcode='22023'; end if;
  insert into public.seller_inventory(seller_id,product_id,stock_on_hand,reserved_quantity,updated_at)
    values(p_seller_id,p_product_id,p_stock_on_hand,v_reserved,now())
    on conflict(product_id) do update set stock_on_hand=excluded.stock_on_hand,updated_at=now();
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'seller.stock_changed','seller_product',p_product_id,
      jsonb_build_object('seller_id',p_seller_id,'stock_on_hand',p_stock_on_hand));
end;
$$;
revoke all on function public.seller_set_stock(uuid,uuid,integer) from public, anon;
grant execute on function public.seller_set_stock(uuid,uuid,integer) to authenticated;

comment on function public.seller_set_stock(uuid,uuid,integer) is 'Validates seller ownership and keeps reserved stock immutable to seller clients.';
