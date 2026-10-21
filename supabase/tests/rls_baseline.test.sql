begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth, pg_temp;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
 ('00000000-0000-4000-8000-000000000101','authenticated','authenticated','rls-user-a@alteo.test','',now(),'{}','{"name":"RLS User A"}',now(),now()),
 ('00000000-0000-4000-8000-000000000102','authenticated','authenticated','rls-user-b@alteo.test','',now(),'{}','{"name":"RLS User B"}',now(),now())
on conflict (id) do nothing;

select is(
  (select count(*)::integer from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','p')
      and c.relname = any(array[
        'profiles','user_roles','addresses','sellers','seller_products','seller_inventory',
        'carts','cart_items','orders','order_items','order_events','payment_attempts','refunds',
        'rides','delivery_jobs','delivery_assignments','driver_earnings','delivery_earnings',
        'dark_stores','dark_store_inventory','location_updates','notifications','support_tickets',
        'audit_events','media_assets','pricing_rules'
      ])
      and c.relrowsecurity),
  26,
  'RLS is enabled on every Alteo public domain table'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000101';
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000101","role":"authenticated"}';

select is((select count(*)::integer from public.profiles), 1, 'user A can read their own profile');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-4000-8000-000000000102'), 0, 'user A cannot read user B profile');
select throws_ok(
  $$insert into public.profiles(id, display_name) values ('00000000-0000-4000-8000-000000000102', 'stolen')$$,
  '42501', null, 'user A cannot insert a profile for user B'
);
update public.profiles set display_name = 'attempted overwrite' where id = '00000000-0000-4000-8000-000000000102';
select throws_ok(
  $$delete from public.profiles where id = '00000000-0000-4000-8000-000000000102'$$,
  '42501', null, 'profile deletion is not granted to clients'
);

reset role;
select is((select display_name from public.profiles where id = '00000000-0000-4000-8000-000000000102'), 'RLS User B', 'cross-user UPDATE does not change user B data');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000102';
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000102","role":"authenticated"}';
select is((select count(*)::integer from public.user_roles where user_id = '00000000-0000-4000-8000-000000000102'), 0, 'new account has no privileged role by default');
select is((select count(*)::integer from public.profiles), 1, 'user B can read their own profile');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-4000-8000-000000000101'), 0, 'user B cannot read user A profile');
select throws_ok(
  $$insert into public.user_roles(user_id, role) values ('00000000-0000-4000-8000-000000000102', 'admin')$$,
  '42501', null, 'users cannot self-assign privileged roles'
);

select * from finish();
rollback;
