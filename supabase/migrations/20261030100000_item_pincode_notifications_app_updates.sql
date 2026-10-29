-- Item PIN coverage, app update metadata, secure notification targeting, and dark-store stock coverage.

alter table public.seller_products
  add column if not exists availability_mode text not null default 'all',
  add column if not exists available_pincodes text[] not null default array[]::text[];
alter table public.dark_store_inventory
  add column if not exists availability_mode text not null default 'all',
  add column if not exists available_pincodes text[] not null default array[]::text[];

alter table public.seller_products drop constraint if exists seller_products_availability_mode_check;
alter table public.seller_products add constraint seller_products_availability_mode_check
  check ((availability_mode = 'all' and cardinality(available_pincodes) = 0)
      or (availability_mode = 'specific' and cardinality(available_pincodes) > 0));
alter table public.dark_store_inventory drop constraint if exists dark_store_inventory_availability_mode_check;
alter table public.dark_store_inventory add constraint dark_store_inventory_availability_mode_check
  check ((availability_mode = 'all' and cardinality(available_pincodes) = 0)
      or (availability_mode = 'specific' and cardinality(available_pincodes) > 0));

create or replace function public.normalize_item_pincode_coverage()
returns trigger language plpgsql set search_path = ''
as $function$
declare
  v_mode text;
  v_pins text[];
  v_pin text;
begin
  v_mode := lower(trim(coalesce(new.availability_mode, 'all')));
  if v_mode not in ('all','specific') then
    raise exception 'Choose all PIN codes or specific PIN codes.' using errcode = '22023';
  end if;
  select coalesce(array_agg(pin order by pin), array[]::text[])
    into v_pins
  from (
    select distinct trim(src.pin) as pin
    from unnest(coalesce(new.available_pincodes, array[]::text[])) as src(pin)
    where nullif(trim(src.pin),'') is not null
  ) x;
  if v_mode = 'all' then
    v_pins := array[]::text[];
  else
    if cardinality(v_pins) = 0 then
      raise exception 'Select at least one serviceable six-digit PIN code.' using errcode = '22023';
    end if;
    foreach v_pin in array v_pins loop
      if v_pin !~ '^[1-9][0-9]{5}$' then
        raise exception 'Every service PIN must be a valid six-digit Indian PIN code.' using errcode = '22023';
      end if;
      if exists (select 1 from public.service_areas)
         and not exists (select 1 from public.service_areas a where a.pincode = v_pin and a.active = true) then
        raise exception 'PIN % is not active in Admin > Service Areas.', v_pin using errcode = '22023';
      end if;
    end loop;
  end if;
  new.availability_mode := v_mode;
  new.available_pincodes := v_pins;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists seller_products_normalize_pin_coverage on public.seller_products;
create trigger seller_products_normalize_pin_coverage
before insert or update of availability_mode, available_pincodes on public.seller_products
for each row execute function public.normalize_item_pincode_coverage();
drop trigger if exists dark_store_inventory_normalize_pin_coverage on public.dark_store_inventory;
create trigger dark_store_inventory_normalize_pin_coverage
before insert or update of availability_mode, available_pincodes on public.dark_store_inventory
for each row execute function public.normalize_item_pincode_coverage();

create table if not exists public.app_update_manifest (
  app_id text primary key check (app_id in ('customer','admin','seller','driver_partner','delivery_partner','dark_store')),
  latest_version text not null default '0.1.0+1',
  minimum_supported_version text,
  download_url text,
  release_notes text,
  force_update boolean not null default false,
  published boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint app_update_manifest_download_url_check
    check (download_url is null or download_url ~* '^https://[^[:space:]]+$')
);
alter table public.app_update_manifest enable row level security;
revoke all on public.app_update_manifest from anon, authenticated;
grant select on public.app_update_manifest to anon, authenticated;
grant insert, update, delete on public.app_update_manifest to authenticated;
drop policy if exists app_update_manifest_public_published on public.app_update_manifest;
create policy app_update_manifest_public_published on public.app_update_manifest
for select to anon, authenticated using (published = true);
drop policy if exists app_update_manifest_admin_manage on public.app_update_manifest;
create policy app_update_manifest_admin_manage on public.app_update_manifest
for all to authenticated using ((select private.has_role('admin')))
with check ((select private.has_role('admin')));

insert into public.app_update_manifest(app_id, latest_version, published)
values
 ('customer','0.1.0+1',false),
 ('admin','0.1.0+1',false),
 ('seller','0.1.0+1',false),
 ('driver_partner','0.1.0+1',false),
 ('delivery_partner','0.1.0+1',false),
 ('dark_store','0.1.0+1',false)
on conflict (app_id) do nothing;

create or replace function public.admin_list_notification_recipients(p_app_id text)
returns table(user_id uuid, display_name text, email text)
language plpgsql security definer set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not (select private.has_role('admin')) then
    raise exception 'Administrator role required.' using errcode = '42501';
  end if;
  if p_app_id not in ('customer','delivery_partner') then
    raise exception 'Recipients are supported only for Customer or Delivery Partner apps.' using errcode = '22023';
  end if;
  return query
  select distinct p.id,
    coalesce(nullif(trim(p.display_name),''), nullif(trim(u.email),''), 'User ' || left(p.id::text,8)) as name,
    u.email::text
  from public.profiles p
  join public.user_device_tokens t on t.user_id = p.id and t.app_id = p_app_id
  left join auth.users u on u.id = p.id
  where p_app_id <> 'delivery_partner'
     or exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role = 'delivery_partner')
  order by name;
end;
$function$;
revoke all on function public.admin_list_notification_recipients(text) from public, anon;
grant execute on function public.admin_list_notification_recipients(text) to authenticated;

create or replace function public.dark_store_set_inventory(
  p_store_id uuid, p_product_id uuid, p_stock_on_hand integer,
  p_availability_mode text, p_available_pincodes text[]
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_mode text := lower(trim(coalesce(p_availability_mode,'all')));
  v_pins text[] := coalesce(p_available_pincodes, array[]::text[]);
begin
  if (select auth.uid()) is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_stock_on_hand is null or p_stock_on_hand < 0 then raise exception 'Stock must be non-negative.' using errcode='22023'; end if;
  if v_mode not in ('all','specific') then raise exception 'Choose all PIN codes or specific PIN codes.' using errcode='22023'; end if;
  if v_mode = 'all' then v_pins := array[]::text[];
  elsif cardinality(v_pins) = 0 then raise exception 'Select at least one serviceable PIN code.' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.dark_stores ds where ds.id = p_store_id and ds.owner_user_id = (select auth.uid()) and ds.status = 'active'
  ) and not (select private.has_role('admin')) then
    raise exception 'An active assigned dark store is required.' using errcode='42501';
  end if;
  if not exists (select 1 from public.seller_products p where p.id=p_product_id and p.status='active') then
    raise exception 'Choose an active catalogue item.' using errcode='22023';
  end if;
  if v_mode = 'specific' then
    if exists (
      select 1 from unnest(v_pins) as x(pin)
      where x.pin !~ '^[1-9][0-9]{5}$'
         or (exists(select 1 from public.service_areas) and not exists(select 1 from public.service_areas a where a.pincode=x.pin and a.active=true))
    ) then raise exception 'Choose only valid active six-digit PIN codes.' using errcode='22023'; end if;
  end if;
  insert into public.dark_store_inventory(store_id, product_id, stock_on_hand, availability_mode, available_pincodes, updated_at)
  values(p_store_id, p_product_id, p_stock_on_hand, v_mode, v_pins, now())
  on conflict(store_id, product_id) do update
    set stock_on_hand=excluded.stock_on_hand,
        availability_mode=excluded.availability_mode,
        available_pincodes=excluded.available_pincodes,
        updated_at=now();
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values((select auth.uid()),'dark_store.inventory_updated','dark_store_inventory',null,
    jsonb_build_object('store_id',p_store_id,'product_id',p_product_id,'stock_on_hand',p_stock_on_hand,'availability_mode',v_mode,'available_pincodes',v_pins));
end;
$function$;
revoke all on function public.dark_store_set_inventory(uuid,uuid,integer,text,text[]) from public, anon;
grant execute on function public.dark_store_set_inventory(uuid,uuid,integer,text,text[]) to authenticated;
