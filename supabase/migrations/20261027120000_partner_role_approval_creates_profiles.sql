create or replace function public.admin_grant_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_application jsonb := '{}'::jsonb;
  v_display_name text;
  v_phone text;
  v_email text;
  v_area text;
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if p_user_id is null or p_role not in ('admin','customer','driver_partner','delivery_partner','seller','dark_store') then
    raise exception 'invalid user or role' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  insert into public.user_roles(user_id, role, granted_by)
  values (p_user_id, p_role, (select auth.uid()))
  on conflict (user_id, role) do nothing;

  select coalesce(rr.application_data, '{}'::jsonb), rr.display_name, rr.phone, rr.email
    into v_application, v_display_name, v_phone, v_email
    from public.role_requests rr
   where rr.user_id = p_user_id and rr.requested_role = p_role
   order by rr.requested_at desc limit 1;

  v_application := coalesce(v_application, '{}'::jsonb);
  v_area := coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), 'DEFAULT');

  if p_role = 'seller' then
    if exists (select 1 from public.sellers s where s.owner_id = p_user_id) then
      update public.sellers
         set display_name = coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), display_name),
             phone = coalesce(nullif(trim(v_phone), ''), phone),
             contact_email = coalesce(nullif(trim(v_email), ''), contact_email),
             status = 'approved', updated_at = now()
       where owner_id = p_user_id;
    else
      insert into public.sellers(owner_id, display_name, phone, contact_email, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'shop_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Seller'),
              nullif(trim(v_phone), ''), nullif(trim(v_email), ''), 'approved');
    end if;
  elsif p_role = 'dark_store' then
    if exists (select 1 from public.dark_stores ds where ds.owner_user_id = p_user_id) then
      update public.dark_stores
         set name = coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), name),
             locality = coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), locality),
             status = 'active', updated_at = now()
       where owner_user_id = p_user_id;
    else
      insert into public.dark_stores(owner_user_id, name, locality, status)
      values (p_user_id, coalesce(nullif(trim(v_application->>'store_name'), ''), nullif(trim(v_display_name), ''), 'Alteo Dark Store'),
              coalesce(nullif(trim(v_application->>'service_area'), ''), nullif(trim(v_application->>'address'), ''), 'Not specified'), 'active');
    end if;
  elsif p_role in ('driver_partner', 'delivery_partner') then
    insert into public.partner_presence(user_id, role, area_code, is_online, updated_at)
    values (p_user_id, p_role, v_area, false, now())
    on conflict (user_id, role) do update
      set area_code = excluded.area_code, updated_at = now();
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'user.role_granted', 'user', p_user_id, jsonb_build_object('role', p_role));
end;
$function$;

grant execute on function public.admin_grant_user_role(uuid, text) to authenticated;
