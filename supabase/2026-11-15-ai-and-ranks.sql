-- AI FILM REVIEW + FOOD SCAN allowances, and the GLOBAL LEADERBOARD (2026-11-15; functions/film-review,
-- functions/food-scan). Safe to re-run.
--
-- 1. Daily allowances: each AI film review or food photo scan takes one from today's allowance for that kind.
--    Like coach_usage, the counts live in the private schema; the only ways in are ai_take() / ai_give_back(),
--    and they only touch the caller's own counts. The limit itself is decided by the edge function (trial / paid).
-- 2. Leaderboard: every signed-in player's XP total, written only through xp_sync() (which caps how fast it can
--    rise), read through leaderboard(). Shown names are first name + last initial, and a player can hide.

create schema if not exists private;

-- ---------------------------------------------------------------------------------------------------------------
-- 1. AI allowances
-- ---------------------------------------------------------------------------------------------------------------
create table if not exists private.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('film', 'food')),
  used integer not null default 0,
  primary key (user_id, day, kind)
);
alter table private.ai_usage enable row level security;
revoke all on private.ai_usage from public, anon, authenticated;

-- Takes one from today's allowance of p_kind. Returns how many are left after this one, or -1 when there were none
-- left (nothing is taken then). "Today" is UTC.
create or replace function public.ai_take(p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_used integer;
begin
  if v_uid is null then raise exception 'sign in first'; end if;
  if p_kind not in ('film', 'food') then raise exception 'bad kind'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'bad limit'; end if;

  insert into private.ai_usage as u (user_id, day, kind, used)
  values (v_uid, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update set used = u.used + 1
    where u.used < p_limit
  returning u.used into v_used;

  if v_used is null then return -1; end if;
  return p_limit - v_used;
end $$;

-- Gives one back (the AI call failed, so it shouldn't count). Never goes below zero.
create or replace function public.ai_give_back(p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  update private.ai_usage set used = greatest(0, used - 1)
   where user_id = auth.uid() and day = (now() at time zone 'utc')::date and kind = p_kind;
end $$;

-- How many of p_kind the caller has used today (the app shows "3 of 5 left" before the first scan).
create or replace function public.ai_used_today(p_kind text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select used from private.ai_usage
                    where user_id = auth.uid() and day = (now() at time zone 'utc')::date and kind = p_kind), 0);
$$;

revoke all on function public.ai_take(text, integer) from public, anon;
revoke all on function public.ai_give_back(text) from public, anon;
revoke all on function public.ai_used_today(text) from public, anon;
grant execute on function public.ai_take(text, integer) to authenticated;
grant execute on function public.ai_give_back(text) to authenticated;
grant execute on function public.ai_used_today(text) to authenticated;

delete from private.ai_usage where day < (now() at time zone 'utc')::date - 14;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Global leaderboard
-- ---------------------------------------------------------------------------------------------------------------
create table if not exists private.player_xp (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text not null default 'Player',
  position text,
  xp integer not null default 0 check (xp >= 0),
  hidden boolean not null default false,
  -- anti-cheat: XP can only rise so much per UTC day
  day date not null default (now() at time zone 'utc')::date,
  day_start_xp integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table private.player_xp enable row level security;
revoke all on private.player_xp from public, anon, authenticated;
create index if not exists player_xp_xp on private.player_xp (xp desc);

-- How much XP one day may add. A huge training day earns about 1,000; this leaves room and stops edited numbers.
create or replace function private.xp_day_cap() returns integer language sql immutable as $$ select 2500 $$;

-- "Muhammad Ali" -> "Muhammad A." ; empty -> "Player". Letters, digits, spaces, dots, hyphens and apostrophes only.
create or replace function private.short_name(p text)
returns text
language sql
immutable
as $$
  with c as (select trim(regexp_replace(coalesce(p, ''), '[^[:alnum:] .''-]', '', 'g')) as s),
       w as (select regexp_split_to_array(s, '\s+') as a from c)
  select case
    when (select s from c) = '' then 'Player'
    when array_length(a, 1) = 1 then left(a[1], 16)
    else left(a[1], 16) || ' ' || left(a[array_length(a, 1)], 1) || '.'
  end
  from w;
$$;

-- Save my XP (the app sends its own total) and return where I stand:
-- {"rank": 12, "total": 340, "xp": 4210, "hidden": false}. XP never goes down here (a reinstall that lost history
-- keeps the best total), and it can rise at most xp_day_cap() per UTC day.
create or replace function public.xp_sync(p_xp integer, p_name text, p_position text, p_hidden boolean default null)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  r private.player_xp;
  v_new integer;
begin
  if v_uid is null then raise exception 'sign in first'; end if;
  insert into private.player_xp (user_id, name, position, xp, day, day_start_xp)
  values (v_uid, private.short_name(p_name), left(p_position, 4), 0, v_today, 0)
  on conflict (user_id) do nothing;

  select * into r from private.player_xp where user_id = v_uid for update;
  if r.day <> v_today then r.day := v_today; r.day_start_xp := r.xp; end if;
  v_new := greatest(r.xp, least(coalesce(p_xp, 0), r.day_start_xp + private.xp_day_cap()));

  update private.player_xp set
    xp = v_new,
    name = private.short_name(p_name),
    position = left(p_position, 4),
    hidden = coalesce(p_hidden, hidden),
    day = r.day,
    day_start_xp = r.day_start_xp,
    updated_at = now()
  where user_id = v_uid
  returning * into r;

  return json_build_object(
    'rank', 1 + (select count(*) from private.player_xp where xp > r.xp),
    'total', (select count(*) from private.player_xp),
    'xp', r.xp,
    'hidden', r.hidden);
end $$;

-- The top of the table (hidden players left out; the caller is always marked "me").
create or replace function public.leaderboard(p_limit integer default 50)
returns table (place bigint, name text, pos text, xp integer, me boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select rank() over (order by p.xp desc) as place, p.name, p.position as pos, p.xp, p.user_id = auth.uid() as me
  from private.player_xp p
  where (not p.hidden or p.user_id = auth.uid()) and auth.uid() is not null
  order by p.xp desc, p.updated_at
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

revoke all on function public.xp_sync(integer, text, text, boolean) from public, anon;
revoke all on function public.leaderboard(integer) from public, anon;
grant execute on function public.xp_sync(integer, text, text, boolean) to authenticated;
grant execute on function public.leaderboard(integer) to authenticated;
