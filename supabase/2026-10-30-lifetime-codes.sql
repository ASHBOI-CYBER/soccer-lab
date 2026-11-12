-- FREE LIFETIME CODES (2026-10-30, notes/40). The user: "instead of just team code, change it to 'Have a code' and
-- ? generate 100 free codes that when typed in grant lifetime free pass". 100 one-use 6-digit codes in the same
-- number space as team + gift codes (so the one HAVE A CODE box takes all three, never two the same number).
-- Redeem ? profiles.free_for_life = true + trial_until far in the future (so the app's existing access check opens).
-- Both columns are SELECT-only for the app (column grants), so only these functions can set them. Codes never live
-- in the app ? the list is on the PostHog "? Free Codes" dashboard (app/scripts/posthog-codes.mjs).
-- RUN 2026-10-30 (migrations lifetime_codes + lifetime_codes_miss_fix).
-- Guessing is limited: 10 wrong lifetime tries per account per hour.

alter table public.profiles add column if not exists free_for_life boolean not null default false;

create table if not exists public.lifetime_codes (
  code text primary key check (code ~ '^[0-9]{6}$'),
  redeemed_by uuid unique references auth.users (id) on delete set null,
  redeemed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.lifetime_codes enable row level security;   -- no policies: only the functions below touch it

create table if not exists private.code_misses (uid uuid not null, at timestamptz not null default now());
create index if not exists code_misses_uid_at on private.code_misses (uid, at);

-- new team / gift codes never take a lifetime code's number
create or replace function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where code = c)
          and not exists (select 1 from public.gifts where code = c)
          and not exists (select 1 from public.lifetime_codes where code = c);
  end loop;
  return c;
end $$;

-- the 100 codes (only when the table is empty, so re-running never makes more)
do $$
begin
  if not exists (select 1 from public.lifetime_codes) then
    for i in 1..100 loop
      insert into public.lifetime_codes (code) values (private.new_code());
    end loop;
  end if;
end $$;

-- is this an unused lifetime code? (a wrong guess counts toward the 10-per-hour limit). Misses are RETURNED, never
-- raised ? a raise would roll back the miss row and the limit would never count.
create or replace function public.lifetime_preview(p_code text) returns boolean
  language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); ok boolean;
begin
  if me is null then return false; end if;
  if (select count(*) from private.code_misses where code_misses.uid = me and at > now() - interval '1 hour') >= 10 then
    return false;
  end if;
  select (redeemed_by is null or redeemed_by = me) into ok from public.lifetime_codes where code = trim(p_code);
  if ok is null then insert into private.code_misses (uid) values (me); end if;
  return coalesce(ok, false);
end $$;

-- {lifetime: true} or {lifetime: false, error: "?"}
create or replace function public.redeem_lifetime(p_code text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); c public.lifetime_codes;
begin
  if me is null then raise exception 'sign in first'; end if;
  if (select count(*) from private.code_misses where code_misses.uid = me and at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('lifetime', false, 'error', 'Too many tries. Wait an hour and try again.');
  end if;
  select * into c from public.lifetime_codes where code = trim(p_code) for update;
  if c.code is null then
    insert into private.code_misses (uid) values (me);
    return jsonb_build_object('lifetime', false, 'error', 'That code doesn''t work.');
  end if;
  if c.redeemed_by is not null and c.redeemed_by <> me then
    return jsonb_build_object('lifetime', false, 'error', 'That code was already used.');
  end if;
  update public.lifetime_codes set redeemed_by = me, redeemed_at = coalesce(redeemed_at, now()) where code = c.code;
  insert into public.profiles (id) values (me) on conflict (id) do nothing;
  update public.profiles set free_for_life = true, trial_until = '2999-12-31T00:00:00Z' where id = me;
  return jsonb_build_object('lifetime', true);
end $$;

revoke all on function public.lifetime_preview(text), public.redeem_lifetime(text) from public, anon;
grant execute on function public.lifetime_preview(text), public.redeem_lifetime(text) to authenticated;
