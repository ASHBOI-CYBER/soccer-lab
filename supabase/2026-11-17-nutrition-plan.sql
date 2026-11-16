-- AI NUTRITION PLAN allowance (2026-11-17; functions/nutrition-plan). A third AI kind, 'plan', next to 'film' and
-- 'food' in private.ai_usage (2026-11-15-ai-and-ranks.sql). Safe to re-run.
alter table private.ai_usage drop constraint if exists ai_usage_kind_check;
alter table private.ai_usage add constraint ai_usage_kind_check check (kind in ('film', 'food', 'plan'));

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
  if p_kind not in ('film', 'food', 'plan') then raise exception 'bad kind'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'bad limit'; end if;

  insert into private.ai_usage as u (user_id, day, kind, used)
  values (v_uid, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update set used = u.used + 1
    where u.used < p_limit
  returning u.used into v_used;

  if v_used is null then return -1; end if;
  return p_limit - v_used;
end $$;
