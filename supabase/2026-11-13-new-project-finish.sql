-- NEW PROJECT, LAST STEP (2026-11-12). Run after every other file in this folder (or as the end of
-- setup-new-project.sql). It closes the gaps the dated files leave on a project that isn't the original one.
-- Safe to re-run.

-- 1. Columns added after the base file that the app itself writes: the streak bitmap (2026-10-27-team-streak.sql).
--    free_for_life (lifetime codes) is deliberately NOT here: only redeem_lifetime() may set it.
grant insert (kept, kept_end), update (kept, kept_end) on public.profiles to authenticated;

-- 2. Team functions made without an explicit grant: signed-in players only, never signed-out visitors.
revoke all on function public.create_team(text, text, integer), public.join_team(text) from public, anon;
grant execute on function public.create_team(text, text, integer), public.join_team(text) to authenticated;

-- 3. Internal helpers: callable by the rules that use them, by nobody directly from outside.
revoke all on function private.new_code() from public, anon, authenticated;
revoke all on function private.feed_rate_limit() from public, anon, authenticated;
revoke all on function private.my_teams() from public, anon;
grant execute on function private.my_teams() to authenticated;

-- 3b. Signed-out visitors get no table at all except public match data. Row Level Security already returns them
--     nothing; this takes away the empty answer too. Tables with no rules are also closed to signed-in players.
revoke all on public.backups, public.blocks, public.gifts, public.lifetime_codes, public.reports from anon;
revoke all on public.gifts, public.lifetime_codes, public.reports from authenticated;

-- 4. Matchday's two nightly jobs were written with the FIRST project's address inside them. On a new project they
--    would call someone else's server, so they are removed here. To turn Matchday's nightly pull on for this
--    project: deploy functions/matchday-pull, set its APISPORTS_KEY secret, put this project's ref (the letters in
--    https://<ref>.supabase.co) in v_ref below, and run this file again.
do $$
declare
  v_ref text := '';      -- e.g. 'abcdefghijklmnopqrst'
  v_url text;
begin
  perform cron.unschedule(jobname) from cron.job where jobname in ('matchday-pull-europe', 'matchday-pull-americas');
  if v_ref ~ '^[a-z0-9]{15,30}$' then
    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/matchday-pull';
    perform cron.schedule('matchday-pull-europe', '50 23 * * *', format(
      $job$select net.http_post(url := %L, headers := jsonb_build_object('x-cron-secret', (select secret from private.matchday_cron)), timeout_milliseconds := 140000)$job$,
      v_url || '?tz=UTC'));
    perform cron.schedule('matchday-pull-americas', '30 5 * * *', format(
      $job$select net.http_post(url := %L, headers := jsonb_build_object('x-cron-secret', (select secret from private.matchday_cron)), timeout_milliseconds := 140000)$job$,
      v_url || '?tz=America/Sao_Paulo'));
    raise notice 'Matchday nightly pull scheduled for %', v_url;
  else
    raise notice 'Matchday nightly pull is OFF (no project ref set in this file).';
  end if;
end $$;

-- 5. A last look: every table in public must have Row Level Security on. This stops the run if one doesn't.
do $$
declare bad text;
begin
  select string_agg(c.relname, ', ') into bad
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if bad is not null then raise exception 'Row Level Security is OFF on: %', bad; end if;
end $$;
