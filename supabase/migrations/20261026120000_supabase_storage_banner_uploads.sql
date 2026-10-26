-- Public customer-facing banner images live in Supabase Storage.
-- Uploads require an authenticated session and are restricted to the banners/ prefix.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-media',
  'app-media',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = true,
    file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

drop policy if exists "Public can read app media" on storage.objects;
create policy "Public can read app media"
on storage.objects for select
to public
using (bucket_id = 'app-media');

drop policy if exists "Authenticated users upload banner media" on storage.objects;
create policy "Authenticated users upload banner media"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'banners'
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'gif')
);

drop policy if exists "Authenticated users update banner media" on storage.objects;
create policy "Authenticated users update banner media"
on storage.objects for update
to authenticated
using (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'banners'
)
with check (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'banners'
);

drop policy if exists "Authenticated users delete banner media" on storage.objects;
create policy "Authenticated users delete banner media"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'banners'
);
