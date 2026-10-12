-- Kinetix database setup. Paste this whole file into Supabase:
-- Dashboard → SQL Editor → New query → Run. Safe to run more than once.

-- One table holds every synced item (sessions, runs, sets, …) as JSON.
create table if not exists public.records (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  payload jsonb not null,
  server_updated_at timestamptz not null default now()
);

create index if not exists records_user_sync_idx on public.records (user_id, server_updated_at);

-- Row Level Security: each person can only ever see and change their own records.
alter table public.records enable row level security;

drop policy if exists "Own records: read" on public.records;
create policy "Own records: read" on public.records
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Own records: insert" on public.records;
create policy "Own records: insert" on public.records
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Own records: update" on public.records;
create policy "Own records: update" on public.records
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Own records: delete" on public.records;
create policy "Own records: delete" on public.records
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Last write wins: an upload older than what's stored is ignored, and every accepted
-- write gets a fresh server timestamp (the app downloads changes after its last one).
create or replace function public.records_last_write_wins()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at < old.updated_at then
      return old;
    end if;
    new.user_id := old.user_id; -- records can't move between accounts
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists records_last_write_wins on public.records;
create trigger records_last_write_wins
  before insert or update on public.records
  for each row execute function public.records_last_write_wins();

-- Account deletion from inside the app (required by the App Store). Deleting the user
-- also deletes all their records (on delete cascade above).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
