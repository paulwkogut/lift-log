-- Exercise photos. Run after supabase/schema.sql and supabase/admin-stats.sql.
-- Safe to run again. Paste each part on its own if you prefer.

-- 1. Private photo path on a user's own exercise.
alter table public.exercises add column if not exists photo_path text;

-- 2. Built-in library photos, one per library exercise name. Signed-in users can read them.
create table if not exists public.library_photos (
  name text primary key,
  photo_path text not null,
  updated_at timestamptz not null default now()
);

alter table public.library_photos enable row level security;
revoke all on table public.library_photos from anon, public;
grant select, insert, update, delete on table public.library_photos to authenticated;

-- 3. Admin check that storage policies can call. app_admins stays hidden from clients.
create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid());
$$;

revoke all on function public.is_app_admin() from public, anon;
grant execute on function public.is_app_admin() to authenticated;

drop policy if exists library_photos_select on public.library_photos;
create policy library_photos_select on public.library_photos
  for select to authenticated using (true);

drop policy if exists library_photos_insert on public.library_photos;
create policy library_photos_insert on public.library_photos
  for insert to authenticated with check (public.is_app_admin());

drop policy if exists library_photos_update on public.library_photos;
create policy library_photos_update on public.library_photos
  for update to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists library_photos_delete on public.library_photos;
create policy library_photos_delete on public.library_photos
  for delete to authenticated using (public.is_app_admin());

-- 4. Private Storage bucket. 5 MB, images only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'exercise-photos',
  'exercise-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 5. Storage policies. A user's files live at user_id/.... Library files live at library/....
drop policy if exists exercise_photos_select_own on storage.objects;
create policy exercise_photos_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists exercise_photos_insert_own on storage.objects;
create policy exercise_photos_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists exercise_photos_update_own on storage.objects;
create policy exercise_photos_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists exercise_photos_delete_own on storage.objects;
create policy exercise_photos_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists exercise_photos_select_library on storage.objects;
create policy exercise_photos_select_library on storage.objects
  for select to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = 'library'
  );

drop policy if exists exercise_photos_insert_library on storage.objects;
create policy exercise_photos_insert_library on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = 'library'
    and public.is_app_admin()
  );

drop policy if exists exercise_photos_update_library on storage.objects;
create policy exercise_photos_update_library on storage.objects
  for update to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = 'library'
    and public.is_app_admin()
  )
  with check (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = 'library'
    and public.is_app_admin()
  );

drop policy if exists exercise_photos_delete_library on storage.objects;
create policy exercise_photos_delete_library on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'exercise-photos'
    and (storage.foldername(name))[1] = 'library'
    and public.is_app_admin()
  );
