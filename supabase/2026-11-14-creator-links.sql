-- CREATOR LINKS ON THE NEW WEBSITE (2026-11-14). new_creator() used to hand out soccermax.app links (the old app's
-- site, which we don't own). It now returns links on Soccer Lab's own site. Default rate 20% for 12 months, as in the
-- current proposal; pass other values to change them per creator. Safe to re-run.

create or replace function public.new_creator(p_name text, p_email text default null, p_rate numeric default 0.20, p_months integer default 12)
  returns table (creator_id uuid, creator_code text, share_link text, stats_link text)
  language plpgsql security definer set search_path = '' as $$
declare
  c public.creators;
  site constant text := 'https://glittery-banoffee-bbbd05.netlify.app';   -- change here when the site gets its own name
begin
  insert into public.creators (code, name, email, rate, months)
    values (private.new_code(), trim(p_name), nullif(trim(p_email), ''), p_rate, p_months)
    returning * into c;
  return query select c.id, c.code,
    site || '/join/' || c.code,
    site || '/creator#' || c.code || '.' || c.dashboard_key::text;
end $$;
revoke all on function public.new_creator(text, text, numeric, integer) from public, anon, authenticated;
grant execute on function public.new_creator(text, text, numeric, integer) to service_role;
