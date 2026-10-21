-- Seller order workflow, product approval and dark-store administration.
-- Additive; all privileged state transitions are server-side and audited.

create or replace function public.admin_set_seller_status(p_seller_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('approved','suspended','rejected','pending') then
    raise exception 'invalid seller status' using errcode = '22023';
  end if;
  select owner_id into v_owner from public.sellers where id = p_seller_id for update;
  if not found then raise exception 'seller not found' using errcode = 'P0002'; end if;
  update public.sellers set status = p_status, updated_at = now() where id = p_seller_id;
  if p_status = 'approved' then
    insert into public.user_roles(user_id, role, granted_by)
      values (v_owner, 'seller', (select auth.uid()))
      on conflict (user_id, role) do nothing;
  elsif p_status in ('suspended','rejected') then
    delete from public.user_roles where user_id = v_owner and role = 'seller';
  end if;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'seller.status_changed', 'seller', p_seller_id,
      jsonb_build_object('status', p_status, 'owner_id', v_owner));
end;
$$;
revoke all on function public.admin_set_seller_status(uuid,text) from public, anon;
grant execute on function public.admin_set_seller_status(uuid,text) to authenticated;

create or replace function public.admin_set_product_status(p_product_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seller uuid;
  v_seller_status text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('draft','active','paused','rejected') then
    raise exception 'invalid product status' using errcode = '22023';
  end if;
  select seller_id into v_seller from public.seller_products where id = p_product_id for update;
  if not found then raise exception 'product not found' using errcode = 'P0002'; end if;
  select status into v_seller_status from public.sellers where id = v_seller;
  if p_status = 'active' and v_seller_status <> 'approved' then
    raise exception 'seller must be approved before activating products' using errcode = '22023';
  end if;
  update public.seller_products set status = p_status, updated_at = now() where id = p_product_id;
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'product.status_changed', 'seller_product', p_product_id,
      jsonb_build_object('status', p_status, 'seller_id', v_seller));
end;
$$;
revoke all on function public.admin_set_product_status(uuid,text) from public, anon;
grant execute on function public.admin_set_product_status(uuid,text) to authenticated;

create or replace function public.seller_update_order_status(p_order_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_next_status text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  select o.* into v_order
    from public.orders o
    join public.sellers s on s.id = o.seller_id
    where o.id = p_order_id and s.owner_id = (select auth.uid()) and s.status = 'approved'
    for update of o;
  if not found then raise exception 'order not found for this approved seller' using errcode = '42501'; end if;
  if v_order.payment_status <> 'paid' then raise exception 'payment must be confirmed before processing' using errcode = '22023'; end if;
  if p_action = 'accept' and v_order.status = 'paid' then
    v_next_status := 'accepted';
  elsif p_action = 'prepare' and v_order.status = 'accepted' then
    v_next_status := 'preparing';
  elsif p_action = 'ready' and v_order.status = 'preparing' then
    v_next_status := 'ready_for_pickup';
  else
    raise exception 'order action is not allowed in its current state' using errcode = '22023';
  end if;
  update public.orders set status = v_next_status, updated_at = now() where id = p_order_id;
  insert into public.order_events(order_id, actor_id, action, detail)
    values (p_order_id, (select auth.uid()), 'seller.' || p_action,
      jsonb_build_object('status_before', v_order.status, 'status_after', v_next_status));
  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values ((select auth.uid()), 'seller.order_' || p_action, 'order', p_order_id,
      jsonb_build_object('status_before', v_order.status, 'status_after', v_next_status));
end;
$$;
revoke all on function public.seller_update_order_status(uuid,text) from public, anon;
grant execute on function public.seller_update_order_status(uuid,text) to authenticated;

create or replace function public.admin_create_dark_store(p_owner_user_id uuid, p_name text, p_locality text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store_id uuid;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_owner_user_id is null or coalesce(length(trim(p_name)),0) < 2 or char_length(p_name) > 120 then
    raise exception 'valid operator and store name required' using errcode = '22023';
  end if;
  if not exists(select 1 from auth.users where id = p_owner_user_id) then
    raise exception 'operator account not found' using errcode = 'P0002';
  end if;
  insert into public.dark_stores(owner_user_id,name,locality,status)
    values(p_owner_user_id,trim(p_name),nullif(trim(p_locality),''),'pending')
    returning id into v_store_id;
  insert into public.user_roles(user_id,role,granted_by)
    values(p_owner_user_id,'dark_store',(select auth.uid()))
    on conflict(user_id,role) do nothing;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'dark_store.created','dark_store',v_store_id,
      jsonb_build_object('owner_user_id',p_owner_user_id,'status','pending'));
  return v_store_id;
end;
$$;
revoke all on function public.admin_create_dark_store(uuid,text,text) from public, anon;
grant execute on function public.admin_create_dark_store(uuid,text,text) to authenticated;

create or replace function public.admin_set_dark_store_status(p_store_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('pending','active','suspended') then
    raise exception 'invalid dark store status' using errcode = '22023';
  end if;
  update public.dark_stores set status = p_status, updated_at = now() where id = p_store_id;
  if not found then raise exception 'dark store not found' using errcode = 'P0002'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values((select auth.uid()),'dark_store.status_changed','dark_store',p_store_id,jsonb_build_object('status',p_status));
end;
$$;
revoke all on function public.admin_set_dark_store_status(uuid,text) from public, anon;
grant execute on function public.admin_set_dark_store_status(uuid,text) to authenticated;

comment on function public.seller_update_order_status(uuid,text) is 'Seller-owned order state transitions; cannot process until payment is marked paid.';
