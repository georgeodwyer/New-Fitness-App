-- Kinetix × Garmin Connect (Training API + Activity API). Paste this whole file into
-- Supabase: Dashboard → SQL Editor → New query → Run, once Garmin has approved Kinetix.
-- Safe to run more than once. See docs/GARMIN_TRAINING_API.md.

-- A runner's link to their Garmin account. Tokens are only ever read by the `garmin`
-- function (service role): there are no policies, so the app can't read them.
create table if not exists public.garmin_links (
  user_id uuid primary key references auth.users (id) on delete cascade,
  garmin_user_id text unique,
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  scopes text,
  connected_at timestamptz not null default now()
);
alter table public.garmin_links enable row level security;

-- Sign-ins in progress (the PKCE verifier between "Connect" and Garmin's redirect back).
create table if not exists public.garmin_pending (
  state text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  code_verifier text not null,
  created_at timestamptz not null default now()
);
alter table public.garmin_pending enable row level security;

-- Planned sessions published to the runner's Garmin calendar, so a changed session
-- replaces its Garmin copy and a removed one is deleted. Server only.
create table if not exists public.garmin_workouts (
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id text not null,
  scheduled_date date not null,
  garmin_workout_id text,
  content_hash text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id)
);
alter table public.garmin_workouts enable row level security;

-- Finished Garmin activities pushed by Garmin, waiting for the app to bring them in.
-- The app reads its own and deletes them once saved.
create table if not exists public.garmin_activities (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  garmin_activity_id text not null,
  kind text not null,              -- 'summary' or 'details'
  payload jsonb not null,
  received_at timestamptz not null default now(),
  unique (garmin_activity_id, kind)
);
create index if not exists garmin_activities_user_idx on public.garmin_activities (user_id, received_at);
alter table public.garmin_activities enable row level security;

drop policy if exists "Own Garmin activities: read" on public.garmin_activities;
create policy "Own Garmin activities: read" on public.garmin_activities
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Own Garmin activities: delete" on public.garmin_activities;
create policy "Own Garmin activities: delete" on public.garmin_activities
  for delete to authenticated using ((select auth.uid()) = user_id);

-- For the app's Settings screen: is this account linked to Garmin, and since when?
create or replace function public.garmin_status()
returns table (connected boolean, connected_at timestamptz)
language sql
security definer
set search_path = ''
as $$
  select exists (select 1 from public.garmin_links l where l.user_id = auth.uid()),
         (select l.connected_at from public.garmin_links l where l.user_id = auth.uid());
$$;

revoke all on function public.garmin_status() from public, anon;
grant execute on function public.garmin_status() to authenticated;
