-- LOCAL TEAMS + JOIN REQUESTS (2026-11-08, notes/26 top). User: "allow the option for teams to select a location when
-- being created or after being created so local players can see them and request to join. Only the creator of the
-- group should be able to alter these settings and accept requests."
-- Additive only. A team with a place shows up to nearby players (rounded to ~1 km ? never an exact pitch/house);
-- they REQUEST to join; only the team's owner sees and answers requests. Applied as migration `local_teams`.

alter table public.teams add column if not exists place text;
alter table public.teams add column if not exists lat double precision;
alter table public.teams add column if not exists lng double precision;
create index if not exists teams_located_idx on public.teams (lat, lng) where lat is not null;

create table if not exists public.join_requests (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index if not exists join_requests_user_idx on public.join_requests (user_id);
alter table public.join_requests enable row level security;
-- no direct table access: everything goes through the functions below
revoke all on public.join_requests from anon, authenticated;

-- owner only: set (or clear with nulls) where the team plays. ~1 km rounding happens here.
create or replace function public.set_team_location(p_team uuid, p_place text, p_lat double precision, p_lng double precision)
  returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select owner from public.teams where id = p_team) is distinct from (select auth.uid()) then
    raise exception 'only the team creator can change this' using errcode = '42501';
  end if;
  update public.teams set
    place = nullif(left(trim(coalesce(p_place, '')), 60), ''),
    lat = case when p_lat is null then null else round(p_lat::numeric, 2)::double precision end,
    lng = case when p_lng is null then null else round(p_lng::numeric, 2)::double precision end
  where id = p_team;
end $$;

-- teams near a point (that set a place), not ones I'm already on. Only name/crest/place/size/distance leave the server.
create or replace function public.nearby_teams(p_lat double precision, p_lng double precision, p_km double precision default 30)
  returns table (id uuid, name text, logo text, color integer, place text, members integer, km double precision, requested boolean)
  language sql stable security definer set search_path = '' as $$
  select t.id, t.name, t.logo, t.color, t.place,
         (select count(*)::int from public.team_members m where m.team_id = t.id) as members,
         round((6371 * 2 * asin(sqrt(power(sin(radians(t.lat - p_lat) / 2), 2)
           + cos(radians(p_lat)) * cos(radians(t.lat)) * power(sin(radians(t.lng - p_lng) / 2), 2))))::numeric, 1)::double precision as km,
         exists (select 1 from public.join_requests r where r.team_id = t.id and r.user_id = (select auth.uid())) as requested
  from public.teams t
  where t.lat is not null
    and (select auth.uid()) is not null
    and t.lat between p_lat - p_km / 111.0 and p_lat + p_km / 111.0
    and t.id not in (select team_id from public.team_members where user_id = (select auth.uid()))
  order by km
  limit 25
$$;

create or replace function public.request_join(p_team uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'sign in first'; end if;
  if (select lat from public.teams where id = p_team) is null then raise exception 'that team is not open to requests'; end if;
  if exists (select 1 from public.team_members where team_id = p_team and user_id = uid) then return; end if;
  if (select count(*) from public.join_requests where user_id = uid) >= 10 then raise exception 'too many open requests'; end if;
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;
  insert into public.join_requests (team_id, user_id) values (p_team, uid) on conflict do nothing;
end $$;

create or replace function public.cancel_request(p_team uuid) returns void
  language sql security definer set search_path = '' as $$
  delete from public.join_requests where team_id = p_team and user_id = (select auth.uid())
$$;

-- owner only: who asked to join
create or replace function public.team_requests(p_team uuid)
  returns table (user_id uuid, name text, "position" text, level integer, created_at timestamptz)
  language sql stable security definer set search_path = '' as $$
  select r.user_id, coalesce(p.name, 'Player'), p.position, p.level, r.created_at
  from public.join_requests r join public.profiles p on p.id = r.user_id
  join public.teams t on t.id = r.team_id
  where r.team_id = p_team and t.owner = (select auth.uid())
  order by r.created_at
$$;

-- owner only: accept (joins the team, shows in the feed) or decline. Either way the request goes.
create or replace function public.answer_request(p_team uuid, p_user uuid, p_accept boolean) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if (select owner from public.teams where id = p_team) is distinct from (select auth.uid()) then
    raise exception 'only the team creator can answer requests' using errcode = '42501';
  end if;
  if not exists (select 1 from public.join_requests where team_id = p_team and user_id = p_user) then return; end if;
  delete from public.join_requests where team_id = p_team and user_id = p_user;
  if p_accept and not exists (select 1 from public.team_members where team_id = p_team and user_id = p_user) then
    if (select count(*) from public.team_members where team_id = p_team) >= 30 then raise exception 'team is full'; end if;
    if (select count(*) from public.team_members where user_id = p_user) >= 10 then raise exception 'that player is on too many teams'; end if;
    insert into public.team_members (user_id, team_id) values (p_user, p_team);
    insert into public.feed (team_id, user_id, kind) values (p_team, p_user, 'join');
  end if;
end $$;

do $$ declare f text; begin
  foreach f in array array['set_team_location(uuid,text,double precision,double precision)',
    'nearby_teams(double precision,double precision,double precision)', 'request_join(uuid)', 'cancel_request(uuid)',
    'team_requests(uuid)', 'answer_request(uuid,uuid,boolean)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
