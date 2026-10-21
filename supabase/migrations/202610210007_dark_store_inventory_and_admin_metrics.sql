-- Dark-store stock controls and complete administrator summary metrics.
-- Additive migration. Stock and financial mutations stay behind checked RPCs.

create or replace function public.dark_store_set_inventory(p_store_id uuid, p_product_id uuid, p_stock_on_hand integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_store_status text;
  v_product_status text;
  v_reserved integer := 0;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  if p_stock_on_hand is null or p_stock_on_hand < 0 or p_stock_on_hand > 1000000 then
    raise exception 'stock must be between 0 and 1000000' using errcode='22023';
  end if;
  select owner_user_id, status into v_owner, v_store_status
    from public.dark_stores where id=p_store_id for update;
  if not found or v_owner <> (select auth.uid()) then
    raise exception 'dark store is not assigned to this account' using errcode='42501';
  end if;
  if v_store_status <> 'active' then raise exception 'dark store must be activated by Alteo admin' using errcode='42501'; end if;
  select status into v_product_status from public.seller_products where id=p_product_id;
  if not found or v_product_status <> 'active' then raise exception 'select an active catalogue product' using errcode='22023'; end if;
  select reserved_quantity into v_reserved from public.dark_store_inventory where store_id=p_store_id and product_id=p_product_id for update;
  v_reserved := coalesce(v_reserved,0);
  if p_stock_on_hand < v_reserved then raise exception 'stock cannot be lower than reserved quantity' using errcode='22023'; end if;
  insert into public.dark_store_inventory(store_id,product_id,stock_on_hand,reserved_quantity,updated_at)
  values(p_store_id,p_product_id,p_stock_on_hand,v_reserved,now())
  on conflict(store_id,product_id) do update set stock_on_hand=excluded.stock_on_hand,updated_at=now();
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'dark_store.stock_changed','dark_store',p_store_id,
      jsonb_build_object('product_id',p_product_id,'stock_on_hand',p_stock_on_hand));
end;
$$;
revoke all on function public.dark_store_set_inventory(uuid,uuid,integer) from public, anon;
grant execute on function public.dark_store_set_inventory(uuid,uuid,integer) to authenticated;

create or replace function public.admin_operations_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'orders_total', (select count(*) from public.orders),
    'orders_paid', (select count(*) from public.orders where payment_status='paid'),
    'orders_pending_payment', (select count(*) from public.orders where payment_status='pending'),
    'gross_paid_minor', (select coalesce(sum(total_minor),0) from public.orders where payment_status='paid'),
    'gross_order_value_minor', (select coalesce(sum(total_minor),0) from public.orders where status not in ('cancelled','refunded')),
    'refunds_succeeded_minor', (select coalesce(sum(amount_minor),0) from public.refunds where status='succeeded'),
    'sellers_total', (select count(*) from public.sellers),
    'sellers_approved', (select count(*) from public.sellers where status='approved'),
    'sellers_pending', (select count(*) from public.sellers where status='pending'),
    'dark_stores_total', (select count(*) from public.dark_stores),
    'dark_stores_active', (select count(*) from public.dark_stores where status='active'),
    'delivery_jobs_open', (select count(*) from public.delivery_jobs where status not in ('delivered','cancelled','failed')),
    'rides_open', (select count(*) from public.rides where status not in ('completed','cancelled'))
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.admin_operations_summary() from public, anon;
grant execute on function public.admin_operations_summary() to authenticated;

comment on function public.admin_operations_summary() is 'Admin-only all-row aggregate summary. Paid gross and refunds are reported separately; net revenue and payout liabilities require a configured financial ledger.';
