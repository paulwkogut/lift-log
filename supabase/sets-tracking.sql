-- Target sets and reps for each template exercise. Safe to re-run.
-- Each item is {"name":"Bench Press","sets":3,"reps":10}.
alter table public.templates
  add column if not exists exercise_targets jsonb not null default '[]';
