-- Delete the signed-in account. Safe to re-run.
-- Paste this into the Supabase SQL editor. It does not use the service role key.
-- Deleting auth.users cascades exercises, sets, settings, and templates.
-- push_subscriptions and rest_alerts are removed explicitly when those tables exist.

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
