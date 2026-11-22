-- Kinetix friends: usernames, friend codes and invite links, friend requests, shared
-- sessions (routes trimmed by the app: 200 m off the start and end), the weekly
-- leaderboard, head-to-head, challenges between friends, and block / report.
--
-- Paste this whole file into Supabase: Dashboard → SQL Editor → New query → Run.
-- Safe to run more than once. Needs schema.sql first (nothing else).
--
-- Security: every table has row level security. People can read and write only their own
-- rows directly; anything about other people goes through the functions below, which check
-- that you're friends and that neither of you has blocked the other.

-- MARK: Tables

-- Your public name. Friends see the username and display name, never the email.
create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null default '' check (char_length(display_name) <= 40),
  friend_code text not null unique check (friend_code ~ '^[A-Z2-9]{8}$'),
  -- Off: friends don't see your sessions or points (you still see theirs).
  sharing boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.social_profiles enable row level security;
drop policy if exists "read own social profile" on public.social_profiles;
create policy "read own social profile" on public.social_profiles
  for select using (user_id = auth.uid());

-- A request from one person to another; accepted makes them friends.
create table if not exists public.friendships (
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships
  (least(requester, addressee), greatest(requester, addressee));
alter table public.friendships enable row level security;

create table if not exists public.blocks (
  blocker uuid not null references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);
alter table public.blocks enable row level security;

-- Reports for George to review in the dashboard (Table Editor → reports).
create table if not exists public.reports (
  id bigserial primary key,
  reporter uuid not null references auth.users (id) on delete cascade,
  reported uuid not null references auth.users (id) on delete cascade,
  session_id uuid,
  reason text not null check (char_length(reason) <= 500),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;

-- Sessions you share with friends (the app leaves out ones marked "Only me").
-- route: [[latitude, longitude], ...] with the first and last 200 m already removed.
create table if not exists public.shared_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('run', 'gym', 'functional', 'other')),
  title text not null default '' check (char_length(title) <= 80),
  started_at timestamptz not null,
  duration_seconds double precision not null default 0,
  distance_meters double precision not null default 0,
  load double precision not null default 0,
  run_type text,
  average_heart_rate double precision,
  sets integer not null default 0,
  route jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists shared_sessions_user_time on public.shared_sessions (user_id, started_at desc);
alter table public.shared_sessions enable row level security;
drop policy if exists "own shared sessions" on public.shared_sessions;
create policy "own shared sessions" on public.shared_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Your points each week (worked out by the app: plan, full week, streak, training).
create table if not exists public.weekly_points (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  week_start date not null,
  points integer not null default 0 check (points between 0 and 5000),
  planned integer not null default 0,
  full_week integer not null default 0,
  streak integer not null default 0,
  load integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, week_start)
);
alter table public.weekly_points enable row level security;
drop policy if exists "own weekly points" on public.weekly_points;
create policy "own weekly points" on public.weekly_points
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Challenges between friends.
create table if not exists public.friend_challenges (
  id uuid primary key default gen_random_uuid(),
  creator uuid not null references auth.users (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  metric text not null check (metric in ('runKilometres', 'gymSessions', 'activeDays', 'points')),
  target double precision not null check (target > 0),
  starts_on date not null,
  ends_on date not null,
  created_at timestamptz not null default now(),
  check (ends_on > starts_on and ends_on - starts_on <= 92)
);
alter table public.friend_challenges enable row level security;

create table if not exists public.challenge_members (
  challenge_id uuid not null references public.friend_challenges (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined boolean not null default false,
  value double precision not null default 0,
  updated_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);
alter table public.challenge_members enable row level security;

-- MARK: Helpers

create or replace function public.kx_are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

create or replace function public.kx_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b) or (blocker = b and blocked = a)
  );
$$;

-- Words a username can't contain (a short list; reports catch the rest).
create or replace function public.kx_username_allowed(name text)
returns boolean language sql immutable set search_path = '' as $$
  select name !~ '(fuck|shit|cunt|nigg|fag|bitch|whore|slut|rape|nazi|hitler|porn|dick|cock|pussy)'
     and name not in ('admin', 'administrator', 'kinetix', 'support', 'help', 'moderator', 'official', 'staff', 'root', 'system');
$$;

create or replace function public.kx_new_friend_code()
returns text language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..8 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.social_profiles where friend_code = code);
  end loop;
  return code;
end;
$$;

-- "friend", "incoming" (they asked you), "outgoing" (you asked them) or "none".
create or replace function public.kx_relation(me uuid, other uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case
      when status = 'accepted' then 'friend'
      when requester = me then 'outgoing'
      else 'incoming' end
    from public.friendships
    where (requester = me and addressee = other) or (requester = other and addressee = me)
    limit 1
  ), 'none');
$$;

-- MARK: Profile

-- Choose (or change) your username and display name. Returns your profile.
create or replace function public.claim_username(p_username text, p_display_name text default '')
returns json language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  name text := lower(trim(p_username));
  shown text := left(trim(coalesce(p_display_name, '')), 40);
  result json;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if name !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'Usernames are 3 to 20 letters, numbers or underscores';
  end if;
  if not public.kx_username_allowed(name) or not public.kx_username_allowed(lower(shown)) then
    raise exception 'That name isn''t allowed';
  end if;
  if exists (select 1 from public.social_profiles where username = name and user_id <> me) then
    raise exception 'That username is taken';
  end if;
  insert into public.social_profiles (user_id, username, display_name, friend_code)
  values (me, name, shown, public.kx_new_friend_code())
  on conflict (user_id) do update set username = excluded.username, display_name = excluded.display_name;
  select json_build_object('user_id', user_id, 'username', username, 'display_name', display_name,
                           'friend_code', friend_code, 'sharing', sharing)
    into result from public.social_profiles where user_id = me;
  return result;
end;
$$;

create or replace function public.my_social_profile()
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('user_id', user_id, 'username', username, 'display_name', display_name,
                           'friend_code', friend_code, 'sharing', sharing)
  from public.social_profiles where user_id = auth.uid();
$$;

create or replace function public.set_sharing(p_sharing boolean)
returns void language sql security definer set search_path = '' as $$
  update public.social_profiles set sharing = p_sharing where user_id = auth.uid();
$$;

-- MARK: Finding people

create or replace function public.search_users(p_query text)
returns table (user_id uuid, username text, display_name text, relation text)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username, p.display_name, public.kx_relation(auth.uid(), p.user_id)
  from public.social_profiles p
  where char_length(trim(p_query)) >= 2
    and p.user_id <> auth.uid()
    and (p.username like replace(replace(lower(trim(p_query)), '%', ''), '_', '\_') || '%'
         or p.display_name ilike replace(replace(trim(p_query), '%', ''), '_', '\_') || '%')
    and not public.kx_blocked(auth.uid(), p.user_id)
  order by p.username
  limit 20;
$$;

create or replace function public.find_by_code(p_code text)
returns table (user_id uuid, username text, display_name text, relation text)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username, p.display_name, public.kx_relation(auth.uid(), p.user_id)
  from public.social_profiles p
  where p.friend_code = upper(trim(p_code))
    and p.user_id <> auth.uid()
    and not public.kx_blocked(auth.uid(), p.user_id);
$$;

-- MARK: Friends

-- Ask someone to be friends. If they already asked you, you're now friends.
-- Returns 'friend', 'outgoing' or raises.
create or replace function public.send_friend_request(p_user uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_user = me then raise exception 'That''s you'; end if;
  if not exists (select 1 from public.social_profiles where user_id = me) then
    raise exception 'Choose a username first';
  end if;
  if not exists (select 1 from public.social_profiles where user_id = p_user) or public.kx_blocked(me, p_user) then
    raise exception 'Couldn''t find that person';
  end if;
  update public.friendships set status = 'accepted'
    where requester = p_user and addressee = me and status = 'pending';
  if found then return 'friend'; end if;
  insert into public.friendships (requester, addressee) values (me, p_user) on conflict do nothing;
  return public.kx_relation(me, p_user);
end;
$$;

create or replace function public.respond_friend_request(p_user uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_accept then
    update public.friendships set status = 'accepted'
      where requester = p_user and addressee = auth.uid() and status = 'pending';
  else
    delete from public.friendships
      where requester = p_user and addressee = auth.uid() and status = 'pending';
  end if;
end;
$$;

-- Unfriend, or cancel a request you sent.
create or replace function public.remove_friend(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.friendships
  where (requester = auth.uid() and addressee = p_user) or (requester = p_user and addressee = auth.uid());
$$;

create or replace function public.list_friends()
returns table (user_id uuid, username text, display_name text, relation text)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username, p.display_name, public.kx_relation(auth.uid(), p.user_id)
  from public.friendships f
  join public.social_profiles p
    on p.user_id = case when f.requester = auth.uid() then f.addressee else f.requester end
  where (f.requester = auth.uid() or f.addressee = auth.uid())
    and not public.kx_blocked(auth.uid(), p.user_id)
  order by (f.status = 'accepted'), p.username;
$$;

-- MARK: Block and report

-- Blocking also unfriends and takes them out of your challenges (and you out of theirs).
create or replace function public.block_user(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or p_user = me then return; end if;
  insert into public.blocks (blocker, blocked) values (me, p_user) on conflict do nothing;
  delete from public.friendships
    where (requester = me and addressee = p_user) or (requester = p_user and addressee = me);
  delete from public.challenge_members m using public.friend_challenges c
    where m.challenge_id = c.id
      and ((c.creator = me and m.user_id = p_user) or (c.creator = p_user and m.user_id = me));
end;
$$;

create or replace function public.unblock_user(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.blocks where blocker = auth.uid() and blocked = p_user;
$$;

create or replace function public.list_blocked()
returns table (user_id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username, p.display_name
  from public.blocks b join public.social_profiles p on p.user_id = b.blocked
  where b.blocker = auth.uid()
  order by p.username;
$$;

create or replace function public.report_user(p_user uuid, p_session uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if (select count(*) from public.reports where reporter = auth.uid() and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Too many reports today';
  end if;
  insert into public.reports (reporter, reported, session_id, reason)
  values (auth.uid(), p_user, p_session, left(coalesce(p_reason, ''), 500));
end;
$$;

-- MARK: Feed, leaderboard and head-to-head

-- Friends' shared sessions, newest first (pages with p_before).
create or replace function public.friend_feed(p_before timestamptz default null, p_limit integer default 30)
returns table (id uuid, user_id uuid, username text, display_name text, kind text, title text,
               started_at timestamptz, duration_seconds double precision, distance_meters double precision,
               load double precision, run_type text, average_heart_rate double precision, sets integer, route jsonb)
language sql stable security definer set search_path = '' as $$
  select s.id, s.user_id, p.username, p.display_name, s.kind, s.title, s.started_at, s.duration_seconds,
         s.distance_meters, s.load, s.run_type, s.average_heart_rate, s.sets, s.route
  from public.shared_sessions s
  join public.social_profiles p on p.user_id = s.user_id
  where p.sharing
    and public.kx_are_friends(auth.uid(), s.user_id)
    and not public.kx_blocked(auth.uid(), s.user_id)
    and s.started_at < coalesce(p_before, now() + interval '1 day')
  order by s.started_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

-- You and your friends for one week (Monday), most points first.
create or replace function public.leaderboard(p_week date)
returns table (user_id uuid, username text, display_name text, points integer, planned integer,
               full_week integer, streak integer, load integer, is_me boolean)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username, p.display_name,
         coalesce(w.points, 0), coalesce(w.planned, 0), coalesce(w.full_week, 0),
         coalesce(w.streak, 0), coalesce(w.load, 0), p.user_id = auth.uid()
  from public.social_profiles p
  left join public.weekly_points w on w.user_id = p.user_id and w.week_start = p_week
  where p.user_id = auth.uid()
     or (p.sharing and public.kx_are_friends(auth.uid(), p.user_id) and not public.kx_blocked(auth.uid(), p.user_id))
  order by coalesce(w.points, 0) desc, p.username;
$$;

-- Week by week, your points against a friend's (the last p_weeks weeks up to p_week).
create or replace function public.head_to_head(p_user uuid, p_week date, p_weeks integer default 8)
returns table (week_start date, my_points integer, their_points integer)
language sql stable security definer set search_path = '' as $$
  select wk::date,
         coalesce((select w.points from public.weekly_points w where w.user_id = auth.uid() and w.week_start = wk::date), 0),
         coalesce((select w.points from public.weekly_points w
                   join public.social_profiles p on p.user_id = w.user_id and p.sharing
                   where w.user_id = p_user and w.week_start = wk::date), 0)
  from generate_series(p_week - 7 * (least(greatest(p_weeks, 1), 52) - 1), p_week, interval '7 days') as wk
  where public.kx_are_friends(auth.uid(), p_user) and not public.kx_blocked(auth.uid(), p_user)
  order by wk;
$$;

-- MARK: Challenges between friends

-- Start a challenge and invite friends (only friends can be invited). Returns its id.
create or replace function public.create_challenge(p_title text, p_metric text, p_target double precision,
                                                   p_starts date, p_ends date, p_friends uuid[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  new_id uuid;
  friend uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if (select count(*) from public.friend_challenges where creator = me and ends_on >= current_date) >= 10 then
    raise exception 'You have 10 challenges running already';
  end if;
  insert into public.friend_challenges (creator, title, metric, target, starts_on, ends_on)
  values (me, left(trim(p_title), 60), p_metric, p_target, p_starts, p_ends)
  returning id into new_id;
  insert into public.challenge_members (challenge_id, user_id, joined) values (new_id, me, true);
  foreach friend in array coalesce(p_friends, '{}') loop
    if public.kx_are_friends(me, friend) and not public.kx_blocked(me, friend) then
      insert into public.challenge_members (challenge_id, user_id) values (new_id, friend) on conflict do nothing;
    end if;
  end loop;
  return new_id;
end;
$$;

-- Join (true) or decline / leave (false) a challenge you were invited to.
create or replace function public.respond_challenge(p_id uuid, p_join boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_join then
    update public.challenge_members set joined = true where challenge_id = p_id and user_id = auth.uid();
  else
    delete from public.challenge_members where challenge_id = p_id and user_id = auth.uid();
    -- The last person out removes it.
    delete from public.friend_challenges c
      where c.id = p_id and not exists (select 1 from public.challenge_members m where m.challenge_id = p_id);
  end if;
end;
$$;

-- Your progress in each challenge you're in: [{"id": "...", "value": 12.5}, ...].
create or replace function public.update_challenge_progress(p_values jsonb)
returns void language sql security definer set search_path = '' as $$
  update public.challenge_members m
  set value = greatest((v ->> 'value')::double precision, 0), updated_at = now()
  from jsonb_array_elements(coalesce(p_values, '[]'::jsonb)) as v
  where m.challenge_id = (v ->> 'id')::uuid and m.user_id = auth.uid() and m.joined;
$$;

-- Challenges you're in or invited to (finished in the last 30 days included), with everyone's progress.
create or replace function public.my_challenges()
returns json language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
    'id', c.id, 'title', c.title, 'metric', c.metric, 'target', c.target,
    'starts_on', c.starts_on, 'ends_on', c.ends_on, 'creator', c.creator,
    'joined', me.joined,
    'members', (
      select coalesce(json_agg(json_build_object(
        'user_id', m.user_id, 'username', p.username, 'display_name', p.display_name,
        'joined', m.joined, 'value', m.value) order by m.value desc), '[]'::json)
      from public.challenge_members m join public.social_profiles p on p.user_id = m.user_id
      where m.challenge_id = c.id and (m.user_id = auth.uid() or not public.kx_blocked(auth.uid(), m.user_id))
    )) order by c.ends_on), '[]'::json)
  from public.friend_challenges c
  join public.challenge_members me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.ends_on >= current_date - 30;
$$;

-- MARK: Who can call what

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.kx_are_friends(uuid, uuid)', 'public.kx_blocked(uuid, uuid)', 'public.kx_relation(uuid, uuid)',
    'public.kx_new_friend_code()', 'public.kx_username_allowed(text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array[
    'public.claim_username(text, text)', 'public.my_social_profile()', 'public.set_sharing(boolean)',
    'public.search_users(text)', 'public.find_by_code(text)', 'public.send_friend_request(uuid)',
    'public.respond_friend_request(uuid, boolean)', 'public.remove_friend(uuid)', 'public.list_friends()',
    'public.block_user(uuid)', 'public.unblock_user(uuid)', 'public.list_blocked()',
    'public.report_user(uuid, uuid, text)', 'public.friend_feed(timestamptz, integer)',
    'public.leaderboard(date)', 'public.head_to_head(uuid, date, integer)',
    'public.create_challenge(text, text, double precision, date, date, uuid[])',
    'public.respond_challenge(uuid, boolean)', 'public.update_challenge_progress(jsonb)', 'public.my_challenges()'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
