-- Workout templates. Safe to re-run.
-- Paste this if supabase/schema.sql was already applied.

create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  kind text not null default 'custom',
  position int not null default 0,
  exercise_names text[] not null default '{}',
  created_at timestamptz not null default now(),
  constraint templates_kind_check check (kind in ('push', 'pull', 'legs', 'custom'))
);

create index if not exists templates_user_position_idx on public.templates (user_id, position);
create unique index if not exists templates_user_builtin_kind_idx
  on public.templates (user_id, kind) where kind <> 'custom';

alter table public.user_settings
  add column if not exists last_template_id uuid,
  add column if not exists templates_seeded boolean not null default false;

alter table public.templates enable row level security;
revoke all on table public.templates from anon, public;
grant select, insert, update, delete on table public.templates to authenticated;

drop policy if exists templates_select_own on public.templates;
create policy templates_select_own on public.templates
  for select using (user_id = auth.uid());
drop policy if exists templates_insert_own on public.templates;
create policy templates_insert_own on public.templates
  for insert with check (user_id = auth.uid());
drop policy if exists templates_update_own on public.templates;
create policy templates_update_own on public.templates
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists templates_delete_own on public.templates;
create policy templates_delete_own on public.templates
  for delete using (user_id = auth.uid());
