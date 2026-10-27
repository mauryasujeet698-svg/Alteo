create or replace function public.ensure_current_partner_profile(p_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_application jsonb := '{}'::jsonb;
  v_display_name text;
  v_phone text;
  v_email text;
  v_area text := 'DEFAULT';
  v_profile_id uuid;
begin
  if v_user_id is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  if p_role not in ('seller', 'dark_store', 'driver_partner', 'delivery_partner') then
    raise exception 'unsupported partner role' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_user_id and ur.role = p_role
  ) then
    raise exception 'approved partner role required' using errcode = '42501';
  end if;

  select coalesce(rr.application_data, '{}'::jsonb), rr.display_name, rr.phone, rr.email
    into v_application, v_display_name, v_phone, v_email
  from public.role_requests rr
  where rr.user_id = v_user_id and rr.requested_role = p_role and rr.status = 'approved'
  order by rr.requested_at desc limit 1;

  v_application := coalesce(v_application, '{}'::jsonb);
  v_area := coalesce(nullif(trim(v_application->>'service_area'), ''),
                     nullif(trim(v_application->>'address'), ''), 'DEFAULT');

  if p_role = 'seller' then
    select s.id into v_profile_id from public.sellers s
    where s.owner_id = v_user_id order by s.created_at asc limit 1;

    if v_profile_id is null then
      insert into public.sellers(owner_id, display_name, phone, contact_email, status)
      values (v_user_id,
        coalesce(nullif(trim(v_application->>'shop_name'), ''),
                 nullif(trim(v_display_name), ''), 'Alteo Seller'),
        nullif(trim(v_phone), ''), nullif(trim(v_email), ''), 'approved')
      returning id into v_profile_id;
    else
      update public.sellers
      set display_name = coalesce(nullif(trim(v_application->>'shop_name'), ''),
                                  nullif(trim(v_display_name), ''), display_name),
          phone = coalesce(nullif(trim(v_phone), ''), phone),
          contact_email = coalesce(nullif(trim(v_email), ''), contact_email),
          status = 'approved', updated_at = now()
      where id = v_profile_id;
    end if;
  elsif p_role = 'dark_store' then
    select ds.id into v_profile_id from public.dark_stores ds
    where ds.owner_user_id = v_user_id order by ds.created_at asc limit 1;

    if v_profile_id is null then
      insert into public.dark_stores(owner_user_id, name, locality, status)
      values (v_user_id,
        coalesce(nullif(trim(v_application->>'store_name'), ''),
                 nullif(trim(v_display_name), ''), 'Alteo Dark Store'),
        coalesce(nullif(trim(v_application->>'service_area'), ''),
                 nullif(trim(v_application->>'address'), ''), 'Not specified'),
        'active')
      returning id into v_profile_id;
    else
      update public.dark_stores
      set name = coalesce(nullif(trim(v_application->>'store_name'), ''),
                          nullif(trim(v_display_name), ''), name),
          locality = coalesce(nullif(trim(v_application->>'service_area'), ''),
                              nullif(trim(v_application->>'address'), ''), locality),
          status = 'active', updated_at = now()
      where id = v_profile_id;
    end if;
  else
    insert into public.partner_presence(user_id, role, area_code, is_online, updated_at)
    values (v_user_id, p_role, v_area, false, now())
    on conflict (user_id, role) do update
      set area_code = excluded.area_code, updated_at = now();
  end if;

  return jsonb_build_object('role', p_role, 'profile_id', v_profile_id, 'ready', true);
end;
$function$;

revoke all on function public.ensure_current_partner_profile(text) from public;
revoke all on function public.ensure_current_partner_profile(text) from anon;
grant execute on function public.ensure_current_partner_profile(text) to authenticated;

-- Repair approved partner accounts created before approval also provisioned
-- their seller/store/presence profile.
do $backfill$
declare
  r record;
  v_profile_id uuid;
  v_area text;
begin
  for r in
    select rr.user_id, rr.requested_role, rr.application_data, rr.display_name, rr.phone, rr.email
    from public.role_requests rr
    where rr.status = 'approved'
      and exists (select 1 from public.user_roles ur
                  where ur.user_id = rr.user_id and ur.role = rr.requested_role)
    order by rr.requested_at
  loop
    v_area := coalesce(nullif(trim(r.application_data->>'service_area'), ''),
                       nullif(trim(r.application_data->>'address'), ''), 'DEFAULT');

    if r.requested_role = 'seller' then
      select s.id into v_profile_id from public.sellers s
      where s.owner_id = r.user_id order by s.created_at asc limit 1;
      if v_profile_id is null then
        insert into public.sellers(owner_id, display_name, phone, contact_email, status)
        values (r.user_id,
          coalesce(nullif(trim(r.application_data->>'shop_name'), ''),
                   nullif(trim(r.display_name), ''), 'Alteo Seller'),
          nullif(trim(r.phone), ''), nullif(trim(r.email), ''), 'approved');
      else
        update public.sellers set status = 'approved', updated_at = now() where id = v_profile_id;
      end if;
    elsif r.requested_role = 'dark_store' then
      select ds.id into v_profile_id from public.dark_stores ds
      where ds.owner_user_id = r.user_id order by ds.created_at asc limit 1;
      if v_profile_id is null then
        insert into public.dark_stores(owner_user_id, name, locality, status)
        values (r.user_id,
          coalesce(nullif(trim(r.application_data->>'store_name'), ''),
                   nullif(trim(r.display_name), ''), 'Alteo Dark Store'),
          coalesce(nullif(trim(r.application_data->>'service_area'), ''),
                   nullif(trim(r.application_data->>'address'), ''), 'Not specified'), 'active');
      else
        update public.dark_stores set status = 'active', updated_at = now() where id = v_profile_id;
      end if;
    elsif r.requested_role in ('driver_partner', 'delivery_partner') then
      insert into public.partner_presence(user_id, role, area_code, is_online, updated_at)
      values (r.user_id, r.requested_role, v_area, false, now())
      on conflict (user_id, role) do update set area_code = excluded.area_code, updated_at = now();
    end if;
  end loop;
end;
$backfill$;
