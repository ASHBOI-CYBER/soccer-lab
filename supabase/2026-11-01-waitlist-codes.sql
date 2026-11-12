-- WAITLIST 40% OFF CODES (2026-11-01). User: "if they put in their email they get 40% off and that's the whole selling
-- point. The launch day email should give them the code for at checkout."
-- Every waitlist email gets its own one-use 6-digit code, in the same number space as team / gift / lifetime codes
-- (one HAVE A CODE box takes them all). In the app: HAVE A CODE ? off40_preview ? redeem_off40 ? the 40% OFF plans
-- (the .off40 products, StayOfferView launch mode ? no 10-minute clock). The launch email sends each person their code.
-- One code = one account; the same account can use it again (closed the page, came back). RUN 2026-11-01.

alter table public.waitlist add column if not exists code text unique check (code ~ '^[0-9]{6}$');
alter table public.waitlist add column if not exists redeemed_by uuid references auth.users (id) on delete set null;
alter table public.waitlist add column if not exists redeemed_at timestamptz;

-- new codes never take a number that's already a team, gift, lifetime or waitlist code
create or replace function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where code = c)
          and not exists (select 1 from public.gifts where code = c)
          and not exists (select 1 from public.lifetime_codes where code = c)
          and not exists (select 1 from public.waitlist where code = c);
  end loop;
  return c;
end $$;

-- sign-up: email in, code made now (sent in the launch email). true = new on the list.
create or replace function public.join_waitlist(p_email text, p_src text default null, p_country text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email));
begin
  insert into public.waitlist (email, src, country, code) values (e, left(p_src, 40), left(p_country, 4), private.new_code())
  on conflict (email) do nothing;
  return found;
end $$;
revoke all on function public.join_waitlist(text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text) to anon;

update public.waitlist set code = private.new_code() where code is null;
alter table public.waitlist alter column code set not null;

-- is this a 40% OFF code this account can use? (wrong guesses count toward the same 10-per-hour limit)
create or replace function public.off40_preview(p_code text) returns boolean
  language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); ok boolean;
begin
  if me is null then return false; end if;
  if (select count(*) from private.code_misses where code_misses.uid = me and at > now() - interval '1 hour') >= 10 then
    return false;
  end if;
  select (redeemed_by is null or redeemed_by = me) into ok from public.waitlist where code = trim(p_code);
  if ok is null then insert into private.code_misses (uid) values (me); end if;
  return coalesce(ok, false);
end $$;

-- {ok: true} or {ok: false, error: "?"}
create or replace function public.redeem_off40(p_code text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); w public.waitlist;
begin
  if me is null then raise exception 'sign in first'; end if;
  if (select count(*) from private.code_misses where code_misses.uid = me and at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Too many tries. Wait an hour and try again.');
  end if;
  select * into w from public.waitlist where code = trim(p_code) for update;
  if w.code is null then
    insert into private.code_misses (uid) values (me);
    return jsonb_build_object('ok', false, 'error', 'That code doesn''t work.');
  end if;
  if w.redeemed_by is not null and w.redeemed_by <> me then
    return jsonb_build_object('ok', false, 'error', 'That code was already used.');
  end if;
  update public.waitlist set redeemed_by = me, redeemed_at = coalesce(redeemed_at, now()) where code = w.code;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.off40_preview(text) from public;
revoke all on function public.redeem_off40(text) from public;
grant execute on function public.off40_preview(text) to authenticated;
grant execute on function public.redeem_off40(text) to authenticated;
