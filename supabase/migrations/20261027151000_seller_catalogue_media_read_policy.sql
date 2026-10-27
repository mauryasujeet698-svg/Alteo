-- Allow approved sellers to read only their own product uploads.
-- Required for upload replacement cleanup and verifying uploaded object metadata.
drop policy if exists "Approved sellers read own catalogue media" on storage.objects;
create policy "Approved sellers read own catalogue media"
on storage.objects for select to authenticated
using (
  bucket_id = 'app-media'
  and (storage.foldername(name))[1] = 'items'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.sellers s
    where s.owner_id = (select auth.uid()) and s.status = 'approved'
  )
);
