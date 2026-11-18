-- 2026-11-18: creator_stats (the old private stats page, site/creator.html) still handed out a soccermax.app link,
-- which now belongs to another app. Point it at our site, the same as the portal (private.site()).
do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'creator_stats';
  if def like '%https://soccermax.app/join/%' then
    execute replace(def, '''https://soccermax.app/join/''', 'private.site() || ''/join/''');
  end if;
end $$;
