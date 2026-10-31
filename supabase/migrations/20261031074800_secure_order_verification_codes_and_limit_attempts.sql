create or replace function private.generate_order_verification_code()
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_bytes bytea;
  v_value bigint;
begin
  v_bytes := extensions.gen_random_bytes(4);
  v_value :=
    get_byte(v_bytes,0)::bigint * 16777216 +
    get_byte(v_bytes,1)::bigint * 65536 +
    get_byte(v_bytes,2)::bigint * 256 +
    get_byte(v_bytes,3)::bigint;
  return lpad((v_value % 10000)::text,4,'0');
end;
$function$;
revoke all on function private.generate_order_verification_code() from public,anon,authenticated;

create or replace function private.create_order_delivery_verification_codes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into private.order_delivery_verification_codes(order_id,customer_code,pickup_code)
  values (new.id,private.generate_order_verification_code(),private.generate_order_verification_code())
  on conflict (order_id) do nothing;
  return new;
end;
$function$;
revoke all on function private.create_order_delivery_verification_codes() from public,anon,authenticated;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.order_delivery_verification_codes'::regclass
      and conname='order_delivery_verification_attempt_limit'
  ) then
    alter table private.order_delivery_verification_codes
      add constraint order_delivery_verification_attempt_limit
      check (customer_attempts <= 5 and pickup_attempts <= 5);
  end if;
end $$;

create or replace function private.enforce_order_delivery_code_attempt_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.customer_code is distinct from old.customer_code
     or new.pickup_code is distinct from old.pickup_code then
    raise exception 'verification codes cannot be changed' using errcode='42501';
  end if;
  if new.customer_attempts < old.customer_attempts
     or new.pickup_attempts < old.pickup_attempts then
    raise exception 'verification attempt counters cannot be reset' using errcode='42501';
  end if;
  if new.customer_attempts > 5 or new.pickup_attempts > 5 then
    raise exception 'too many verification attempts' using errcode='22023';
  end if;
  if old.customer_verified_at is null and new.customer_verified_at is not null and old.customer_attempts >= 5 then
    raise exception 'too many customer code attempts; contact support' using errcode='22023';
  end if;
  if old.pickup_verified_at is null and new.pickup_verified_at is not null and old.pickup_attempts >= 5 then
    raise exception 'too many pickup code attempts; contact support' using errcode='22023';
  end if;
  if old.customer_verified_at is not null and new.customer_verified_at is distinct from old.customer_verified_at then
    raise exception 'customer verification cannot be reversed' using errcode='42501';
  end if;
  if old.pickup_verified_at is not null and new.pickup_verified_at is distinct from old.pickup_verified_at then
    raise exception 'pickup verification cannot be reversed' using errcode='42501';
  end if;
  return new;
end;
$function$;
revoke all on function private.enforce_order_delivery_code_attempt_limit() from public,anon,authenticated;

drop trigger if exists order_delivery_code_attempt_guard on private.order_delivery_verification_codes;
create trigger order_delivery_code_attempt_guard
before update on private.order_delivery_verification_codes
for each row execute function private.enforce_order_delivery_code_attempt_limit();

create or replace function public.customer_get_delivery_verification_code(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare v_code text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select c.customer_code into v_code
  from private.order_delivery_verification_codes c
  join public.orders o on o.id=c.order_id
  where o.id=p_order_id
    and o.customer_id=(select auth.uid())
    and o.status='out_for_delivery'
    and c.customer_verified_at is null
    and c.customer_attempts < 5;
  if v_code is null then
    raise exception 'delivery code unavailable, already verified or locked after five attempts' using errcode='P0002';
  end if;
  return v_code;
end;
$function$;

create or replace function public.seller_get_pickup_verification_code(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare v_code text;
begin
  if (select auth.uid()) is null then raise exception 'sign-in required' using errcode='42501'; end if;
  select c.pickup_code into v_code
  from private.order_delivery_verification_codes c
  join public.orders o on o.id=c.order_id
  where o.id=p_order_id
    and o.status='ready_for_pickup'
    and c.pickup_verified_at is null
    and c.pickup_attempts < 5
    and (
      exists (
        select 1 from public.sellers s
        where s.id=o.seller_id
          and s.owner_id=(select auth.uid())
          and s.status='approved'
      )
      or exists (
        select 1 from public.dark_store_tasks dst
        join public.dark_stores ds on ds.id=dst.store_id
        where dst.order_id=o.id
          and dst.status='handed_over'
          and ds.owner_user_id=(select auth.uid())
          and ds.status='active'
      )
    );
  if v_code is null then
    raise exception 'pickup code unavailable, already verified or locked after five attempts' using errcode='42501';
  end if;
  return v_code;
end;
$function$;

revoke all on function public.customer_get_delivery_verification_code(uuid) from public,anon;
revoke all on function public.seller_get_pickup_verification_code(uuid) from public,anon;
grant execute on function public.customer_get_delivery_verification_code(uuid) to authenticated;
grant execute on function public.seller_get_pickup_verification_code(uuid) to authenticated;
