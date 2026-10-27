-- Partner onboarding supports multiple independent roles per Google account.
alter table public.role_requests
  add column if not exists phone text,
  add column if not exists profile_photo_path text,
  add column if not exists application_data jsonb not null default '{}'::jsonb,
  add column if not exists document_paths jsonb not null default '[]'::jsonb,
  add column if not exists rejection_reason text,
  add column if not exists updated_at timestamptz not null default now();

-- A rejected applicant can correct their details and resubmit the same role request.
drop policy if exists role_requests_resubmit_rejected_own on public.role_requests;
create policy role_requests_resubmit_rejected_own on public.role_requests
for update to authenticated
using (user_id = (select auth.uid()) and status = 'rejected')
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and reviewed_at is null
  and reviewed_by is null
);

-- Store partner profile photos and verification documents in a private bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partner-onboarding', 'partner-onboarding', false, 10485760,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 10485760,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists partner_onboarding_upload_own on storage.objects;
create policy partner_onboarding_upload_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'partner-onboarding'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists partner_onboarding_read_own_or_admin on storage.objects;
create policy partner_onboarding_read_own_or_admin on storage.objects
for select to authenticated
using (
  bucket_id = 'partner-onboarding'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (select private.has_role('admin'))
  )
);

drop policy if exists partner_onboarding_update_own on storage.objects;
create policy partner_onboarding_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'partner-onboarding'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'partner-onboarding'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
