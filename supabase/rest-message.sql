-- Custom rest-over message. Safe to re-run.
-- Adds a nullable column on the existing per-user settings row.
-- Deleting the account already removes that row (auth.users cascades).

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
