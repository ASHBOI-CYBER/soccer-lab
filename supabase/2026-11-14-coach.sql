-- AI COACH, daily allowance (2026-11-14, functions/coach). Each Coach message takes one from today's allowance.
-- The count lives in the private schema, which the app can't read or write; the only way in is coach_take(),
-- and it only ever counts the caller's own messages. Safe to re-run.

create table if not exists private.coach_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  used integer not null default 0,
  primary key (user_id, day)
);
alter table private.coach_usage enable row level security;
revoke all on private.coach_usage from public, anon, authenticated;

-- Takes one message from today's allowance. Returns how many are left after this one, or -1 when there were none
-- left (nothing is taken then). "Today" is UTC.
create or replace function public.coach_take(p_limit integer)
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
  if p_limit is null or p_limit < 1 or p_limit > 200 then raise exception 'bad limit'; end if;

  insert into private.coach_usage as u (user_id, day, used)
  values (v_uid, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day) do update set used = u.used + 1
    where u.used < p_limit
  returning u.used into v_used;

  if v_used is null then return -1; end if;   -- already at the limit: the update did nothing
  return p_limit - v_used;
end $$;

revoke all on function public.coach_take(integer) from public, anon;
grant execute on function public.coach_take(integer) to authenticated;

-- old days are of no use: keep two weeks
delete from private.coach_usage where day < (now() at time zone 'utc')::date - 14;
