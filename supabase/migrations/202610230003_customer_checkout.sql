-- Create orders securely from the signed-in customer's active cart.
-- Prices and totals are recalculated on the server; the client never supplies trusted totals.

create or replace function public.create_orders_from_cart(delivery_address jsonb, customer_note text default '')
returns setof public.orders
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  active_cart public.carts;
  seller_group record;
  cart_item record;
  created_order public.orders;
  calculated_total bigint;
begin
  if auth.uid() is null then raise exception 'Sign in is required to place an order'; end if;

  select * into active_cart
  from public.carts
  where customer_id = auth.uid() and status = 'active'
  for update;

  if not found then raise exception 'Your cart is empty'; end if;
  if not exists (select 1 from public.cart_items ci where ci.cart_id = active_cart.id) then
    raise exception 'Your cart is empty';
  end if;

  -- Lock all cart products before validating availability and reserving stock.
  perform sp.id
  from public.cart_items ci
  join public.seller_products sp on sp.id = ci.product_id
  where ci.cart_id = active_cart.id
  order by sp.id
  for update of sp;

  if exists (
    select 1
    from public.cart_items ci
    join public.seller_products sp on sp.id = ci.product_id
    join public.sellers s on s.id = sp.seller_id
    where ci.cart_id = active_cart.id
      and (sp.status <> 'active' or s.status <> 'approved' or sp.stock_quantity < ci.quantity)
  ) then
    raise exception 'One or more items are unavailable or out of stock. Refresh your cart and try again.';
  end if;

  for seller_group in
    select sp.seller_id, sum(sp.price_minor * ci.quantity)::bigint as total_minor
    from public.cart_items ci
    join public.seller_products sp on sp.id = ci.product_id
    where ci.cart_id = active_cart.id
    group by sp.seller_id
    order by sp.seller_id
  loop
    calculated_total := seller_group.total_minor;
    insert into public.orders(customer_id, seller_id, status, total_minor, delivery_address, customer_note)
    values (auth.uid(), seller_group.seller_id, 'pending', calculated_total, coalesce(delivery_address, '{}'::jsonb), coalesce(customer_note, ''))
    returning * into created_order;

    for cart_item in
      select ci.product_id, ci.quantity, sp.name, sp.price_minor
      from public.cart_items ci
      join public.seller_products sp on sp.id = ci.product_id
      where ci.cart_id = active_cart.id and sp.seller_id = seller_group.seller_id
      order by sp.id
    loop
      insert into public.order_items(order_id, product_id, product_name_snapshot, quantity, unit_price_minor)
      values (created_order.id, cart_item.product_id, cart_item.name, cart_item.quantity, cart_item.price_minor);

      update public.seller_products
      set stock_quantity = stock_quantity - cart_item.quantity, updated_at = now()
      where id = cart_item.product_id and stock_quantity >= cart_item.quantity;

      if not found then raise exception 'Stock changed while checking out. Please try again.'; end if;
    end loop;

    insert into public.order_status_events(order_id, actor_id, from_status, to_status, note)
    values (created_order.id, auth.uid(), null, 'pending', 'Order placed');
    return next created_order;
  end loop;

  update public.carts set status = 'checked_out', updated_at = now() where id = active_cart.id;
  return;
end;
$$;

revoke all on function public.create_orders_from_cart(jsonb, text) from public;
grant execute on function public.create_orders_from_cart(jsonb, text) to authenticated;
