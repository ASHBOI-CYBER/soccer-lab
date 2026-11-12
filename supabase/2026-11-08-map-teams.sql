-- MAP TEAMS (2026-11-08, notes/19 top). User: "put teams on the map with a person type icon, only applies to teams who
-- put in their location". Read-only and additive: teams that set a place (lat/lng already rounded to ~1 km by
-- set_team_location) near a point, plus every located team I'm on. Only name/colour/place/size/spot leave the server.
-- Applied as migration `map_teams`.
create or replace function public.map_teams(p_lat double precision, p_lng double precision, p_km double precision default 50)
  returns table (id uuid, name text, color integer, place text, members integer,
                 lat double precision, lng double precision, mine boolean, requested boolean)
  language sql stable security definer set search_path = '' as $$
  select t.id, t.name, t.color, t.place,
         (select count(*)::int from public.team_members m where m.team_id = t.id) as members,
         t.lat, t.lng,
         exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = (select auth.uid())) as mine,
         exists (select 1 from public.join_requests r where r.team_id = t.id and r.user_id = (select auth.uid())) as requested
  from public.teams t
  where t.lat is not null and t.lng is not null
    and (select auth.uid()) is not null
    and (
      exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = (select auth.uid()))
      or (t.lat between p_lat - p_km / 111.0 and p_lat + p_km / 111.0
          and t.lng between p_lng - p_km / (111.0 * greatest(cos(radians(p_lat)), 0.2))
                        and p_lng + p_km / (111.0 * greatest(cos(radians(p_lat)), 0.2)))
    )
  limit 80
$$;
revoke execute on function public.map_teams(double precision, double precision, double precision) from public, anon;
grant execute on function public.map_teams(double precision, double precision, double precision) to authenticated;
