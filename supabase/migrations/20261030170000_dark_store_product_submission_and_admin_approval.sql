-- Dark-store product submissions are reviewed by Admin before publication.
alter table public.seller_products
  add column if not exists category text,
  add column if not exists subcategory text,
  add column if not exists brand text,
  add column if not exists sku text,
  add column if not exists barcode text,
  add column if not exists mrp_minor bigint,
  add column if not exists unit_label text,
  add column if not exists gst_rate numeric(5,2);

alter table public.seller_products drop constraint if exists seller_products_mrp_check;
alter table public.seller_products add constraint seller_products_mrp_check
  check (mrp_minor is null or mrp_minor >= price_minor);
alter table public.seller_products drop constraint if exists seller_products_gst_rate_check;
alter table public.seller_products add constraint seller_products_gst_rate_check
  check (gst_rate is null or (gst_rate >= 0 and gst_rate <= 100));
create unique index if not exists seller_products_sku_unique
  on public.seller_products (sku) where sku is not null and sku <> '';

create table if not exists public.dark_store_product_submissions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.dark_stores(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  sku text not null,
  barcode text,
  name text not null,
  category text not null,
  subcategory text,
  brand text,
  description text not null,
  kind text not null default 'quick' check (kind = 'quick'),
  price_minor bigint not null check (price_minor > 0),
  mrp_minor bigint not null check (mrp_minor >= price_minor),
  unit_label text not null,
  gst_rate numeric(5,2) check (gst_rate is null or (gst_rate >= 0 and gst_rate <= 100)),
  image_url text not null check (image_url ~* '^https://[^[:space:]]+$'),
  proposed_stock integer not null default 0 check (proposed_stock >= 0),
  availability_mode text not null default 'specific' check (availability_mode in ('all','specific')),
  available_pincodes text[] not null default array[]::text[],
  status text not null default 'pending_review'
    check (status in ('pending_review','needs_correction','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  product_id uuid references public.seller_products(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dark_store_submission_category_not_food
    check (lower(trim(category)) not in ('food','foods','food & beverages','food and beverages')),
  constraint dark_store_submission_name_length
    check (char_length(trim(name)) between 2 and 180),
  constraint dark_store_submission_description_length
    check (char_length(trim(description)) between 10 and 4000),
  constraint dark_store_submission_sku_length
    check (char_length(trim(sku)) between 2 and 64),
  constraint dark_store_submission_unit_length
    check (char_length(trim(unit_label)) between 1 and 80),
  constraint dark_store_submission_pincode_coverage
    check (availability_mode = 'all' or cardinality(available_pincodes) > 0)
);

create unique index if not exists dark_store_submission_store_sku_unique
  on public.dark_store_product_submissions(store_id, sku);
create index if not exists dark_store_submission_review_queue_idx
  on public.dark_store_product_submissions(status, created_at desc);
create index if not exists dark_store_submission_store_idx
  on public.dark_store_product_submissions(store_id, created_at desc);

alter table public.dark_store_product_submissions enable row level security;
grant select, insert, update on public.dark_store_product_submissions to authenticated;

drop policy if exists dark_store_submissions_read_owner on public.dark_store_product_submissions;
create policy dark_store_submissions_read_owner
on public.dark_store_product_submissions for select to authenticated
using (
  exists (
    select 1 from public.dark_stores ds
    where ds.id = dark_store_product_submissions.store_id
      and ds.owner_user_id = (select auth.uid())
  )
);

drop policy if exists dark_store_submissions_read_admin on public.dark_store_product_submissions;
create policy dark_store_submissions_read_admin
on public.dark_store_product_submissions for select to authenticated
using ((select private.has_role('admin'::text)));

drop policy if exists dark_store_submissions_insert_owner on public.dark_store_product_submissions;
create policy dark_store_submissions_insert_owner
on public.dark_store_product_submissions for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and status = 'pending_review'
  and product_id is null
  and reviewed_by is null
  and reviewed_at is null
  and kind = 'quick'
  and lower(trim(category)) not in ('food','foods','food & beverages','food and beverages')
  and exists (
    select 1 from public.dark_stores ds
    where ds.id = dark_store_product_submissions.store_id
      and ds.owner_user_id = (select auth.uid())
      and ds.status = 'active'
  )
);

drop policy if exists dark_store_submissions_resubmit_owner on public.dark_store_product_submissions;
create policy dark_store_submissions_resubmit_owner
on public.dark_store_product_submissions for update to authenticated
using (
  submitted_by = (select auth.uid())
  and status in ('needs_correction','rejected')
  and product_id is null
)
with check (
  submitted_by = (select auth.uid())
  and status = 'pending_review'
  and product_id is null
  and reviewed_by is null
  and reviewed_at is null
  and kind = 'quick'
  and lower(trim(category)) not in ('food','foods','food & beverages','food and beverages')
  and exists (
    select 1 from public.dark_stores ds
    where ds.id = dark_store_product_submissions.store_id
      and ds.owner_user_id = (select auth.uid())
      and ds.status = 'active'
  )
);

drop policy if exists "Active dark stores upload product submission media" on storage.objects;
create policy "Active dark stores upload product submission media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'items'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and lower(storage.extension(name)) in ('jpg','jpeg','png','webp','gif')
  and exists (
    select 1 from public.dark_stores ds
    where ds.owner_user_id = (select auth.uid())
      and ds.status = 'active'
  )
);

create or replace function public.admin_review_dark_store_product(
  p_submission_id uuid,
  p_action text,
  p_admin_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_submission public.dark_store_product_submissions%rowtype;
  v_seller_id uuid;
  v_product_id uuid;
  v_action text := lower(trim(coalesce(p_action,'')));
begin
  if (select auth.uid()) is null or not (select private.has_role('admin'::text)) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if v_action not in ('approve','reject','request_correction') then
    raise exception 'unsupported review action' using errcode = '22023';
  end if;

  select * into v_submission
  from public.dark_store_product_submissions
  where id = p_submission_id
  for update;
  if not found then
    raise exception 'product submission not found' using errcode = 'P0002';
  end if;
  if v_submission.status <> 'pending_review' then
    raise exception 'only pending product submissions can be reviewed' using errcode = '22023';
  end if;

  if v_action = 'approve' then
    if v_submission.kind <> 'quick'
       or lower(trim(v_submission.category)) in ('food','foods','food & beverages','food and beverages') then
      raise exception 'only non-food quick-commerce items can be approved in this queue' using errcode = '22023';
    end if;
    if char_length(trim(v_submission.description)) < 10
       or v_submission.image_url !~* '^https://[^[:space:]]+$'
       or v_submission.price_minor <= 0
       or v_submission.mrp_minor < v_submission.price_minor
       or char_length(trim(v_submission.unit_label)) = 0 then
      raise exception 'complete product description, image, unit and valid pricing before approval' using errcode = '22023';
    end if;
    if v_submission.availability_mode = 'specific'
       and cardinality(v_submission.available_pincodes) = 0 then
      raise exception 'select at least one serviceable PIN code before approval' using errcode = '22023';
    end if;

    v_seller_id := public.admin_ensure_platform_seller();

    insert into public.seller_products (
      seller_id, kind, name, description, price_minor, currency, status,
      image_url, availability_mode, available_pincodes,
      category, subcategory, brand, sku, barcode, mrp_minor, unit_label, gst_rate
    )
    values (
      v_seller_id, 'quick', trim(v_submission.name), trim(v_submission.description),
      v_submission.price_minor, 'INR', 'active', v_submission.image_url,
      v_submission.availability_mode, v_submission.available_pincodes,
      trim(v_submission.category), nullif(trim(v_submission.subcategory),''),
      nullif(trim(v_submission.brand),''), trim(v_submission.sku),
      nullif(trim(v_submission.barcode),''), v_submission.mrp_minor,
      trim(v_submission.unit_label), v_submission.gst_rate
    )
    returning id into v_product_id;

    insert into public.dark_store_inventory (
      store_id, product_id, stock_on_hand, reserved_quantity,
      availability_mode, available_pincodes, updated_at
    )
    values (
      v_submission.store_id, v_product_id, v_submission.proposed_stock, 0,
      v_submission.availability_mode, v_submission.available_pincodes, now()
    );

    update public.dark_store_product_submissions
    set status = 'approved',
        admin_note = nullif(trim(coalesce(p_admin_note,'')),''),
        reviewed_by = (select auth.uid()),
        reviewed_at = now(),
        product_id = v_product_id,
        updated_at = now()
    where id = p_submission_id;

    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values ((select auth.uid()),'catalogue.dark_store_product_approved',
      'seller_product',v_product_id,
      jsonb_build_object('submission_id',p_submission_id,'store_id',v_submission.store_id,
        'category',v_submission.category,'sku',v_submission.sku));
    return v_product_id;
  end if;

  if v_action = 'request_correction' and char_length(trim(coalesce(p_admin_note,''))) < 5 then
    raise exception 'provide a correction note of at least five characters' using errcode = '22023';
  end if;

  update public.dark_store_product_submissions
  set status = case when v_action = 'reject' then 'rejected' else 'needs_correction' end,
      admin_note = nullif(trim(coalesce(p_admin_note,'')),''),
      reviewed_by = (select auth.uid()),
      reviewed_at = now(),
      updated_at = now()
  where id = p_submission_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values ((select auth.uid()),'catalogue.dark_store_product_' || v_action,
    'dark_store_product_submission',p_submission_id,
    jsonb_build_object('store_id',v_submission.store_id,'sku',v_submission.sku,
      'admin_note',nullif(trim(coalesce(p_admin_note,'')),''));
  return null;
end;
$function$;

revoke all on function public.admin_review_dark_store_product(uuid,text,text) from public, anon;
grant execute on function public.admin_review_dark_store_product(uuid,text,text) to authenticated;
