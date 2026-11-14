-- Lift Log schema
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to run again: tables use IF NOT EXISTS, policies are dropped and recreated.

create extension if not exists pgcrypto;

create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  custom boolean not null default true,
  created_at timestamptz not null default now(),
  constraint exercises_name_len check (char_length(btrim(name)) > 0 and char_length(name) <= 60)
);

create table if not exists public.sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  weight numeric not null,
  reps integer not null,
  unit text not null default 'lbs',
  performed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint sets_weight_nonnegative check (weight >= 0),
  constraint sets_reps_positive check (reps >= 1),
  constraint sets_unit_check check (unit in ('lbs', 'kg'))
);

create table if not exists public.user_settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  unit text not null default 'lbs',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_settings_unit_check check (unit in ('lbs', 'kg'))
);

comment on column public.sets.weight is 'Weight value in the unit stored on this row.';
comment on column public.sets.unit is 'lbs or kg. Display conversion uses the account unit in user_settings.';
comment on column public.sets.performed_at is 'When the set was performed. History days use this timestamp.';

-- (id, user_id) lets sets reference an exercise only when both belong to the same account.
create unique index if not exists exercises_id_user_id_key on public.exercises (id, user_id);
create unique index if not exists exercises_user_lower_name_idx on public.exercises (user_id, lower(name));
create index if not exists exercises_user_id_idx on public.exercises (user_id);

create index if not exists sets_user_id_idx on public.sets (user_id);
create index if not exists sets_exercise_id_idx on public.sets (exercise_id);
create index if not exists sets_user_performed_idx on public.sets (user_id, performed_at desc);
create index if not exists sets_exercise_performed_idx on public.sets (exercise_id, performed_at desc);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sets_exercise_same_user_fk'
  ) then
    alter table public.sets
      add constraint sets_exercise_same_user_fk
      foreign key (exercise_id, user_id)
      references public.exercises (id, user_id)
      on delete cascade;
  end if;
end $$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_settings_touch_updated_at on public.user_settings;
create trigger user_settings_touch_updated_at
  before update on public.user_settings
  for each row execute function public.touch_updated_at();

revoke all on table public.exercises from anon, public;
revoke all on table public.sets from anon, public;
revoke all on table public.user_settings from anon, public;

grant select, insert, update, delete on table public.exercises to authenticated;
grant select, insert, update, delete on table public.sets to authenticated;
grant select, insert, update, delete on table public.user_settings to authenticated;

alter table public.exercises enable row level security;
alter table public.sets enable row level security;
alter table public.user_settings enable row level security;

drop policy if exists exercises_select_own on public.exercises;
create policy exercises_select_own on public.exercises
  for select using (user_id = auth.uid());

drop policy if exists exercises_insert_own on public.exercises;
create policy exercises_insert_own on public.exercises
  for insert with check (user_id = auth.uid());

drop policy if exists exercises_update_own on public.exercises;
create policy exercises_update_own on public.exercises
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists exercises_delete_own on public.exercises;
create policy exercises_delete_own on public.exercises
  for delete using (user_id = auth.uid());

drop policy if exists sets_select_own on public.sets;
create policy sets_select_own on public.sets
  for select using (user_id = auth.uid());

drop policy if exists sets_insert_own on public.sets;
create policy sets_insert_own on public.sets
  for insert with check (user_id = auth.uid());

drop policy if exists sets_update_own on public.sets;
create policy sets_update_own on public.sets
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists sets_delete_own on public.sets;
create policy sets_delete_own on public.sets
  for delete using (user_id = auth.uid());

drop policy if exists user_settings_select_own on public.user_settings;
create policy user_settings_select_own on public.user_settings
  for select using (user_id = auth.uid());

drop policy if exists user_settings_insert_own on public.user_settings;
create policy user_settings_insert_own on public.user_settings
  for insert with check (user_id = auth.uid());

drop policy if exists user_settings_update_own on public.user_settings;
create policy user_settings_update_own on public.user_settings
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_settings_delete_own on public.user_settings;
create policy user_settings_delete_own on public.user_settings
  for delete using (user_id = auth.uid());

-- Workout templates (same script as supabase/templates.sql).
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
