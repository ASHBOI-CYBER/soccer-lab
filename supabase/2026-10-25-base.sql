-- BASE TABLES for a NEW Supabase project (written 2026-11-12).
-- The other files in this folder are changes made on top of the first Supabase project, whose original setup was
-- never saved as a file. This file rebuilds that starting point from what the app sends and reads (Data/Team.swift)
-- and from what the later files expect to find (table, rule and constraint names they change or drop), so that on an
-- empty project every file runs without edits, this one first and 2026-11-13-new-project-finish.sql last.
-- The exact order is in make-setup.py, which joins them all into  setup-new-project.sql : paste that ONE file into
-- the new project's SQL editor instead of running these one by one. Run it ONCE; it is not meant to be re-run.

create schema if not exists private;
-- rules below call private.* functions as the signed-in player, so the role needs to reach the schema (tables in it
-- are never granted)
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- profiles: one row per signed-in player (what teammates see: name, position, streak, minutes, a tiny picture)
-- ---------------------------------------------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text check (name is null or length(name) <= 40),
  "position" text check ("position" is null or length("position") <= 40),
  streak integer not null default 0 check (streak between 0 and 100000),
  week_minutes integer not null default 0 check (week_minutes between 0 and 20000),
  week_start date,
  last_active timestamptz,
  club text check (club is null or length(club) <= 60),
  level integer check (level is null or level between 0 and 999),
  avatar text check (avatar is null or length(avatar) < 40000),      -- a small JPEG as base64
  avatar_v integer,
  trial_until timestamptz,                                           -- set only by the join / gift / code functions
  trial_used boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- teams
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 40),
  logo text check (logo is null or length(logo) < 20000),            -- a 128 px JPEG as base64
  color integer not null default 0 check (color between 0 and 31),
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),          -- 2026-10-28 swaps this for 6 digits
  owner uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.teams enable row level security;

-- who is on which team (2026-10-27 changes the key so a player can be on many)
create table public.team_members (
  user_id uuid not null references public.profiles (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  joined_at timestamptz not null default now(),
  constraint team_members_pkey primary key (user_id)
);
create index team_members_team_idx on public.team_members (team_id);
alter table public.team_members enable row level security;

-- the team feed: chat + activity. Text only.
create table public.feed (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (length(kind) <= 20),
  body text check (body is null or length(body) <= 500),
  ref text check (ref is null or length(ref) <= 80),
  meta jsonb check (meta is null or pg_column_size(meta) < 20000),
  created_at timestamptz not null default now()
);
create index feed_team_idx on public.feed (team_id, id desc);
create index feed_user_recent_idx on public.feed (user_id, created_at desc);
alter table public.feed enable row level security;

-- ---------------------------------------------------------------------------------------------------------------
-- what the app's signed-in role may touch. Nothing for signed-out visitors. Columns that carry access
-- (trial_until, trial_used, later free_for_life) and a team's code / owner are readable but never writable from the
-- app: only the functions change them.
-- ---------------------------------------------------------------------------------------------------------------
revoke all on public.profiles, public.teams, public.team_members, public.feed from anon, authenticated;

grant select on public.profiles to authenticated;
grant insert (id, name, "position", streak, week_minutes, week_start, last_active, club, level, avatar, avatar_v),
      update (name, "position", streak, week_minutes, week_start, last_active, club, level, avatar, avatar_v)
  on public.profiles to authenticated;

grant select on public.teams to authenticated;
grant update (name, logo, color) on public.teams to authenticated;

grant select on public.team_members to authenticated;

grant select, delete on public.feed to authenticated;
grant insert (team_id, user_id, kind, body, ref, meta) on public.feed to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------------

-- my team (one team per player at first; 2026-10-27 replaces this with private.my_teams())
create function private.my_team() returns uuid
  language sql stable security definer set search_path = '' as $$
  select team_id from public.team_members where user_id = (select auth.uid())
$$;

-- a team code nobody has yet
create function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text; abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  loop
    c := '';
    for i in 1..6 loop c := c || substr(abc, 1 + floor(random() * length(abc))::int, 1); end loop;
    exit when not exists (select 1 from public.teams where code = c);
  end loop;
  return c;
end $$;

-- spam guard on the feed (2026-10-27 makes it per team)
create function private.feed_rate_limit() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.feed where user_id = new.user_id and created_at > now() - interval '1 minute') >= 8 then
    raise exception 'slow down' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger feed_rate_limit before insert on public.feed
  for each row execute function private.feed_rate_limit();

-- ---------------------------------------------------------------------------------------------------------------
-- rules (Row Level Security)
-- ---------------------------------------------------------------------------------------------------------------

create policy "see self and teammates" on public.profiles for select using (
  id = (select auth.uid()) or id in (select m.user_id from public.team_members m where m.team_id = (select private.my_team())));
create policy "make own profile" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "edit own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "see my team" on public.teams for select using (id = (select private.my_team()));
create policy "owner edits team" on public.teams for update
  using (id = (select private.my_team()) and owner = (select auth.uid()))
  with check (id = (select private.my_team()) and owner = (select auth.uid()));

create policy "see teammates" on public.team_members for select using (team_id = (select private.my_team()));

create policy "read team feed" on public.feed for select using (team_id = (select private.my_team()));
create policy "post to team feed" on public.feed for insert with check (
  team_id = (select private.my_team()) and user_id = (select auth.uid())
  and kind = any (array['chat','session','film','share_session','share_film']));
create policy "delete own posts" on public.feed for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------
-- functions the app calls (create_team / join_team / leave_team(uuid) arrive with 2026-10-27-multi-teams.sql)
-- ---------------------------------------------------------------------------------------------------------------

-- what a team code opens, before joining: name, crest, colour, size. Signed-in players only.
create function public.team_preview(p_code text)
  returns table (name text, logo text, color integer, members integer)
  language sql stable security definer set search_path = '' as $$
  select t.name, t.logo, t.color, (select count(*)::int from public.team_members m where m.team_id = t.id)
  from public.teams t
  where t.code = upper(trim(p_code)) and (select auth.uid()) is not null
$$;
revoke all on function public.team_preview(text) from public, anon;
grant execute on function public.team_preview(text) to authenticated;

-- the first app version's "leave my team" (2026-10-27 drops it for leave_team(uuid))
create function public.leave_team() returns void
  language plpgsql security definer set search_path = '' as $$
begin
  delete from public.team_members where user_id = (select auth.uid());
end $$;
revoke all on function public.leave_team() from public, anon;
grant execute on function public.leave_team() to authenticated;
