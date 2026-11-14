-- Lock-screen rest alerts. Safe to re-run.
-- Paste this whole file into the Supabase SQL editor if schema.sql was already applied.

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

-- One phone belongs to the account that most recently subscribed it.
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

-- Optional backup, not run by this file.
-- The rest-alert Edge Function waits and then continues itself, so a rest of
-- up to 5 minutes still fires about a second after the timer. Run the block
-- below only if you also want a once-a-minute sweep for alerts that wait was
-- killed before sending. A swept alert can be up to 60 seconds late.
-- Replace YOUR_SERVICE_ROLE_KEY with the service_role key from Settings → API.
-- Do not commit that key.
--
-- create extension if not exists pg_net;
-- create extension if not exists pg_cron;
-- select cron.schedule(
--   'lift-log-rest-sweep',
--   '* * * * *',
--   $$
--   select net.http_post(
--     url := 'https://iogspfmaiiurwgjjjteq.supabase.co/functions/v1/rest-alert',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
--       'apikey', 'YOUR_SERVICE_ROLE_KEY'
--     ),
--     body := '{"action":"sweep"}'::jsonb
--   );
--   $$
-- );
