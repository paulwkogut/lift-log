create table if not exists public.app_admins (user_id uuid primary key);
alter table public.app_admins enable row level security;
revoke all on public.app_admins from public, anon, authenticated;
insert into public.app_admins (user_id)
select id from auth.users where email = 'paulwkogut@gmail.com'
on conflict (user_id) do nothing;

create or replace function public.admin_stats()
returns json language sql stable security definer set search_path = public, auth as $$
select case when auth.uid() is null or not exists (
  select 1 from public.app_admins where user_id = auth.uid()) then null
else json_build_object(
  'users', (select count(*) from auth.users),
  'new7', (select count(*) from auth.users where created_at >= now() - interval '7 days'),
  'seen7', (select count(*) from auth.users where last_sign_in_at >= now() - interval '7 days'),
  'lifters1', (select count(distinct user_id) from sets where performed_at >= date_trunc('day', now())),
  'lifters7', (select count(distinct user_id) from sets where performed_at >= now() - interval '7 days'),
  'lifters30', (select count(distinct user_id) from sets where performed_at >= now() - interval '30 days'),
  'sets1', (select count(*) from sets where performed_at >= date_trunc('day', now())),
  'sets7', (select count(*) from sets where performed_at >= now() - interval '7 days'),
  'sets', (select count(*) from sets),
  'days', (select coalesce(json_agg(json_build_object('d', d::date, 'n', n) order by d), '[]'::json)
    from generate_series((current_date - 13)::timestamp, current_date::timestamp, interval '1 day') d
    cross join lateral (select count(distinct user_id)::int n from sets s
      where s.performed_at >= d and s.performed_at < d + interval '1 day') x)
) end $$;

revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;
