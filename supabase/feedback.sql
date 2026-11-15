-- Feedback. Safe to re-run.
-- Needs public.app_admins from supabase/admin-stats.sql.
-- Deleting an account removes that person's rows (auth.users cascades).

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  user_email text,
  category text not null,
  message text not null,
  contact_ok boolean not null default false,
  created_at timestamptz not null default now(),
  constraint feedback_category_check check (category in ('bug', 'idea', 'other')),
  constraint feedback_message_len check (char_length(message) between 1 and 2000),
  constraint feedback_email_len check (user_email is null or char_length(user_email) <= 320)
);

create index if not exists feedback_user_created_idx
  on public.feedback (user_id, created_at desc);

alter table public.feedback enable row level security;
revoke all on table public.feedback from anon, public;
grant insert, select on table public.feedback to authenticated;

drop policy if exists feedback_insert_own on public.feedback;
create policy feedback_insert_own on public.feedback
  for insert with check (user_id = auth.uid());

drop policy if exists feedback_select_admin on public.feedback;
create policy feedback_select_admin on public.feedback
  for select using (
    exists (select 1 from public.app_admins a where a.user_id = auth.uid())
  );
