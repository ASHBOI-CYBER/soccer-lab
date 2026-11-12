-- GIFT TRIALS + ONE TRIAL PER ACCOUNT (2026-10-29, notes/19 "SHARE LINKS v2").
-- The user: "add on the profile a share for a free 7 day trial no card? Make sure maximum 1 free or card 7 day trial
-- per account". Every player gets ONE personal 6-digit gift code (same number space as team codes, never the same
-- number, so the one code box + soccermax.app/join/<code> work for both). A friend who redeems it gets 7 days free, no
-- card ? only if their account never had a trial: profiles.trial_used is the single flag for team trials, gift trials
-- AND Apple's card trial (the app calls mark_trial_used() once Apple says the free trial was used). trial_* columns are
-- SELECT-only for the app, so only these functions can change them. Migration `gift_trials`.

create table if not exists public.gifts (
  code text primary key check (code ~ '^[0-9]{6}$'),
  owner uuid not null unique references auth.users (id) on delete cascade,
  uses integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.gifts enable row level security;   -- no policies: only the functions below touch it

create or replace function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where code = c)
          and not exists (select 1 from public.gifts where code = c);
  end loop;
  return c;
end $$;

-- your own gift code (made the first time you ask)
create or replace function public.my_gift_code() returns text
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); c text;
begin
  if uid is null then raise exception 'sign in first'; end if;
  select code into c from public.gifts where owner = uid;
  if c is null then
    insert into public.gifts (code, owner) values (private.new_code(), uid) returning code into c;
  end if;
  return c;
end $$;

-- who the gift is from (first name only)
create or replace function public.gift_preview(p_code text) returns table (name text)
  language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(split_part(trim(p.name), ' ', 1), ''), 'A friend')
  from public.gifts g left join public.profiles p on p.id = g.owner
  where g.code = trim(p_code) and (select auth.uid()) is not null
$$;

create or replace function public.redeem_gift(p_code text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); g public.gifts; p public.profiles; granted boolean := false;
begin
  if uid is null then raise exception 'sign in first'; end if;
  select * into g from public.gifts where code = trim(p_code);
  if g.code is null then raise exception 'no gift with that code' using errcode = 'P0002'; end if;
  if g.owner = uid then raise exception 'that is your own code'; end if;
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;
  select * into p from public.profiles where id = uid for update;
  if not p.trial_used then
    update public.profiles set trial_until = now() + interval '7 days', trial_used = true where id = uid;
    update public.gifts set uses = uses + 1 where code = g.code;
    granted := true;
  end if;
  return jsonb_build_object('trial_granted', granted);
end $$;

-- Apple's card trial was used on this Apple ID ? no free week on top (it can only ever switch the flag on)
create or replace function public.mark_trial_used() returns void
  language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then return; end if;
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;
  update public.profiles set trial_used = true where id = uid and not trial_used;
end $$;

revoke all on function public.my_gift_code(), public.gift_preview(text), public.redeem_gift(text), public.mark_trial_used() from public, anon;
grant execute on function public.my_gift_code(), public.gift_preview(text), public.redeem_gift(text), public.mark_trial_used() to authenticated;
