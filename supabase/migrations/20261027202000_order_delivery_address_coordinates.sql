-- Copy customer destination details to the delivery job when an order is created.
-- Coordinates stay nullable: customers can enter addresses manually if maps are unavailable.
create or replace function public.create_delivery_job_for_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_destination_label text;
  v_destination_latitude double precision;
  v_destination_longitude double precision;
  v_pickup_label text;
begin
  v_destination_label := nullif(trim(concat_ws(', ',
    nullif(trim(new.delivery_address_snapshot->>'address_line1'), ''),
    nullif(trim(new.delivery_address_snapshot->>'locality'), ''),
    nullif(trim(new.delivery_address_snapshot->>'city'), ''),
    nullif(trim(new.delivery_address_snapshot->>'state'), ''),
    nullif(trim(new.delivery_address_snapshot->>'postal_code'), '')
  )), '');

  v_destination_latitude := case
    when jsonb_typeof(new.delivery_address_snapshot->'latitude') = 'number'
    then (new.delivery_address_snapshot->>'latitude')::double precision
    else null
  end;
  v_destination_longitude := case
    when jsonb_typeof(new.delivery_address_snapshot->'longitude') = 'number'
    then (new.delivery_address_snapshot->>'longitude')::double precision
    else null
  end;

  select 'Seller pickup · ' || s.display_name
    into v_pickup_label
  from public.sellers s where s.id = new.seller_id;
  v_pickup_label := coalesce(v_pickup_label, 'Seller pickup');

  insert into public.delivery_jobs(
    order_id, customer_id, seller_id, status, job_type, area_code,
    pickup_label, destination_label, destination_latitude, destination_longitude
  )
  values (
    new.id, new.customer_id, new.seller_id, 'pending', 'order',
    coalesce(nullif(upper(trim(new.delivery_address_snapshot->>'area_code')), ''), 'DEFAULT'),
    v_pickup_label, v_destination_label, v_destination_latitude, v_destination_longitude
  )
  on conflict(order_id) do nothing;

  return new;
end;
$function$;
