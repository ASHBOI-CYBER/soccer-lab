-- MULTIPLE TEAMS (2026-10-27, notes/26 "Many teams"). User: "allow multiple teams at once".
-- A player can be on up to 10 teams. team_members key = (team_id, user_id); every rule reads "my teams" (a set).
-- Run once on project drhuacxwmlrvaoyjqceg (applied as migration `multi_teams`).

alter table public.team_members drop constraint team_members_pkey;
alter table public.team_members add primary key (team_id, user_id);
create index if not exists team_members_user_idx on public.team_members (user_id);

create or replace function private.my_teams() returns setof uuid
  language sql stable security definer set search_path = '' as $$
  select team_id from public.team_members where user_id = (select auth.uid())
$$;

drop policy "post to team feed" on public.feed;
create policy "post to team feed" on public.feed for insert with check (
  team_id in (select private.my_teams()) and user_id = (select auth.uid())
  and kind = any (array['chat','session','film','share_session','share_film']));
drop policy "read team feed" on public.feed;
create policy "read team feed" on public.feed for select using (team_id in (select private.my_teams()));
drop policy "see self and teammates" on public.profiles;
create policy "see self and teammates" on public.profiles for select using (
  id = (select auth.uid()) or id in (select m.user_id from public.team_members m where m.team_id in (select private.my_teams())));
drop policy "see teammates" on public.team_members;
create policy "see teammates" on public.team_members for select using (team_id in (select private.my_teams()));
drop policy "owner edits team" on public.teams;
create policy "owner edits team" on public.teams for update
  using (id in (select private.my_teams()) and owner = (select auth.uid()))
  with check (id in (select private.my_teams()) and owner = (select auth.uid()));
drop policy "see my team" on public.teams;
create policy "see my teams" on public.teams for select using (id in (select private.my_teams()));

drop function private.my_team();

-- spam guard per team (a finished session is logged to every team you're on)
create or replace function private.feed_rate_limit() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.feed where user_id = new.user_id and team_id = new.team_id
      and created_at > now() - interval '1 minute') >= 8 then
    raise exception 'slow down' using errcode = 'P0001';
  end if;
  return new;
end $$;

create or replace function public.create_team(p_name text, p_logo text default null, p_color integer default 0)
  returns public.teams language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); t public.teams;
begin
  if uid is null then raise exception 'sign in first'; end if;
  if (select count(*) from public.team_members where user_id = uid) >= 10 then raise exception 'too many teams'; end if;
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;
  insert into public.teams (name, logo, color, code, owner)
    values (trim(p_name), p_logo, coalesce(p_color, 0), private.new_code(), uid) returning * into t;
  insert into public.team_members (user_id, team_id) values (uid, t.id);
  insert into public.feed (team_id, user_id, kind) values (t.id, uid, 'create');
  return t;
end $$;

create or replace function public.join_team(p_code text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); t public.teams; granted boolean := false; p public.profiles;
begin
  if uid is null then raise exception 'sign in first'; end if;
  select * into t from public.teams where code = upper(trim(p_code));
  if t.id is null then raise exception 'no team with that code' using errcode = 'P0002'; end if;
  if exists (select 1 from public.team_members where user_id = uid and team_id = t.id) then
    return jsonb_build_object('team_id', t.id, 'trial_granted', false);
  end if;
  if (select count(*) from public.team_members where user_id = uid) >= 10 then raise exception 'too many teams'; end if;
  if (select count(*) from public.team_members where team_id = t.id) >= 30 then raise exception 'team is full'; end if;
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;
  select * into p from public.profiles where id = uid;
  if not p.trial_used then
    update public.profiles set trial_until = now() + interval '7 days', trial_used = true where id = uid;
    granted := true;
  end if;
  insert into public.team_members (user_id, team_id) values (uid, t.id);
  insert into public.feed (team_id, user_id, kind) values (t.id, uid, 'join');
  return jsonb_build_object('team_id', t.id, 'trial_granted', granted);
end $$;

drop function public.leave_team();
-- p_team null = the old app (one team): leave the only team you're on
create or replace function public.leave_team(p_team uuid default null) returns void
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); tid uuid;
begin
  if p_team is null then
    if (select count(*) from public.team_members where user_id = uid) <> 1 then return; end if;
    select team_id into p_team from public.team_members where user_id = uid;
  end if;
  delete from public.team_members where user_id = uid and team_id = p_team returning team_id into tid;
  if tid is null then return; end if;
  if not exists (select 1 from public.team_members where team_id = tid) then
    delete from public.teams where id = tid;               -- last one out: the team and its feed go
  elsif (select owner from public.teams where id = tid) = uid then
    update public.teams set owner = (select user_id from public.team_members where team_id = tid order by joined_at limit 1) where id = tid;
  end if;
end $$;
revoke execute on function public.leave_team(uuid) from public, anon;
grant execute on function public.leave_team(uuid) to authenticated;
