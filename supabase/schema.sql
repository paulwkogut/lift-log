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

alter table public.exercises add column if not exists photo_path text;

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

alter table public.user_settings
  add column if not exists rest_message text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'user_settings_rest_message_len'
  ) then
    alter table public.user_settings
      add constraint user_settings_rest_message_len
      check (rest_message is null or char_length(rest_message) <= 80);
  end if;
end $$;

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

-- Target sets and reps (same statement as supabase/sets-tracking.sql).
alter table public.templates
  add column if not exists exercise_targets jsonb not null default '[]';

-- Lock-screen rest alerts (same script as supabase/push.sql).
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  endpoint text not null,
  keys jsonb not null,
  created_at timestamptz not null default now(),
  constraint push_subscriptions_keys_check check (
    keys ? 'p256dh' and keys ? 'auth'
    and char_length(keys->>'p256dh') > 0
    and char_length(keys->>'auth') > 0
  )
);

create table if not exists public.rest_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  exercise_name text not null default '',
  fire_at timestamptz not null,
  sent_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint rest_alerts_name_len check (char_length(exercise_name) <= 80)
);

create unique index if not exists push_subscriptions_user_endpoint_idx
  on public.push_subscriptions (user_id, endpoint);
create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);
create index if not exists rest_alerts_user_open_idx
  on public.rest_alerts (user_id)
  where sent_at is null and cancelled_at is null;
create index if not exists rest_alerts_due_idx
  on public.rest_alerts (fire_at)
  where sent_at is null and cancelled_at is null;

create or replace function public.push_subscriptions_claim_endpoint()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.push_subscriptions
  where endpoint = new.endpoint and user_id <> new.user_id;
  return new;
end;
$$;

revoke all on function public.push_subscriptions_claim_endpoint() from public, anon, authenticated;

drop trigger if exists push_subscriptions_claim_endpoint on public.push_subscriptions;
create trigger push_subscriptions_claim_endpoint
  before insert or update of endpoint on public.push_subscriptions
  for each row execute function public.push_subscriptions_claim_endpoint();

alter table public.push_subscriptions enable row level security;
alter table public.rest_alerts enable row level security;

revoke all on table public.push_subscriptions from anon, public;
revoke all on table public.rest_alerts from anon, public;
grant select, insert, update, delete on table public.push_subscriptions to authenticated;
grant select, insert, update, delete on table public.rest_alerts to authenticated;

drop policy if exists push_subscriptions_select_own on public.push_subscriptions;
create policy push_subscriptions_select_own on public.push_subscriptions
  for select using (user_id = auth.uid());
drop policy if exists push_subscriptions_insert_own on public.push_subscriptions;
create policy push_subscriptions_insert_own on public.push_subscriptions
  for insert with check (user_id = auth.uid());
drop policy if exists push_subscriptions_update_own on public.push_subscriptions;
create policy push_subscriptions_update_own on public.push_subscriptions
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists push_subscriptions_delete_own on public.push_subscriptions;
create policy push_subscriptions_delete_own on public.push_subscriptions
  for delete using (user_id = auth.uid());

drop policy if exists rest_alerts_select_own on public.rest_alerts;
create policy rest_alerts_select_own on public.rest_alerts
  for select using (user_id = auth.uid());
drop policy if exists rest_alerts_insert_own on public.rest_alerts;
create policy rest_alerts_insert_own on public.rest_alerts
  for insert with check (user_id = auth.uid());
drop policy if exists rest_alerts_update_own on public.rest_alerts;
create policy rest_alerts_update_own on public.rest_alerts
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists rest_alerts_delete_own on public.rest_alerts;
create policy rest_alerts_delete_own on public.rest_alerts
  for delete using (user_id = auth.uid());

-- Delete the signed-in account (same script as supabase/delete-account.sql).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if to_regclass('public.push_subscriptions') is not null then
    delete from public.push_subscriptions where user_id = uid;
  end if;
  if to_regclass('public.rest_alerts') is not null then
    delete from public.rest_alerts where user_id = uid;
  end if;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
