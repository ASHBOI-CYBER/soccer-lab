-- CREATOR PORTAL (2026-11-17; site/portal.html, site/admin.html, functions/creator-auth). Creators sign up on the
-- website with their TikTok @username and a password (no email: Supabase's own mailer can't reach outside addresses,
-- so accounts are made by functions/creator-auth with an internal address and no email is ever sent). A new creator
-- waits for an admin to approve them; then their link works and they see their numbers and can ask to withdraw.
--   pending   = commission from the last 30 days (Apple can still refund it)
--   available = commission older than 30 days, minus payouts and open withdrawal requests
-- Builds on 2026-11-12-creators.sql (creators, creator_referrals, purchase_events, creator_payouts). Safe to re-run.

-- ---------------------------------------------------------------------------------------------------------------
-- creators: who owns the portal account, their TikTok name, approval, where to pay them
-- ---------------------------------------------------------------------------------------------------------------
alter table public.creators add column if not exists portal_user_id uuid unique references auth.users (id) on delete set null;
alter table public.creators add column if not exists tiktok text;
alter table public.creators add column if not exists status text not null default 'approved' check (status in ('pending', 'approved', 'rejected'));
alter table public.creators add column if not exists payout_method text check (payout_method in ('paypal', 'bank', 'other'));
alter table public.creators add column if not exists payout_details text check (length(payout_details) <= 400);
create unique index if not exists creators_tiktok on public.creators (lower(tiktok)) where tiktok is not null;

-- link visits, one row per creator per day (the join page counts a browser once a day)
create table if not exists public.creator_visits (
  creator_id uuid not null references public.creators (id) on delete cascade,
  day date not null,
  visits integer not null default 0,
  primary key (creator_id, day)
);
alter table public.creator_visits enable row level security;

create table if not exists public.creator_withdrawals (
  id bigint generated always as identity primary key,
  creator_id uuid not null references public.creators (id),
  amount_usd numeric(12,2) not null check (amount_usd > 0),
  method text,
  details text,
  status text not null default 'requested' check (status in ('requested', 'paid', 'rejected')),
  requested_at timestamptz not null default now(),
  done_at timestamptz,
  payout_id bigint references public.creator_payouts (id),
  note text
);
create index if not exists creator_withdrawals_creator on public.creator_withdrawals (creator_id, status);
alter table public.creator_withdrawals enable row level security;

-- admins: portal usernames (lowercase, with the @) that may approve creators and mark payouts paid
create table if not exists private.portal_admins (username text primary key);

revoke all on public.creator_visits, public.creator_withdrawals from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------------
create or replace function private.site() returns text language sql immutable as $$
  select 'https://glittery-banoffee-bbbd05.netlify.app'   -- change here when the site gets its own name
$$;

-- the caller's portal username ("@samfootball"), from their account's internal address
create or replace function private.portal_username() returns text language sql stable set search_path = '' as $$
  select case when (auth.jwt() ->> 'email') like '%@creators.soccerlab.invalid'
              then '@' || split_part(auth.jwt() ->> 'email', '@', 1) end
$$;

create or replace function private.is_portal_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.portal_admins where username = private.portal_username())
$$;

create or replace function private.creator_numbers(c public.creators) returns jsonb
  language sql stable security definer set search_path = '' as $$
  with ev as (select * from public.purchase_events e where e.creator_id = c.id),
  paid as (select coalesce(sum(amount_usd), 0) s from public.creator_payouts p where p.creator_id = c.id),
  asked as (select coalesce(sum(amount_usd), 0) s from public.creator_withdrawals w where w.creator_id = c.id and w.status = 'requested'),
  settled as (select coalesce(sum(commission_usd), 0) s from ev where commission_usd < 0 or event_at < now() - interval '30 days')
  select jsonb_build_object(
    'visits', coalesce((select sum(visits) from public.creator_visits v where v.creator_id = c.id), 0),
    'visits_30', coalesce((select sum(visits) from public.creator_visits v where v.creator_id = c.id and v.day > current_date - 30), 0),
    'signups', (select count(*) from public.creator_referrals r where r.creator_id = c.id),
    'subscribers', (select count(distinct r.app_user_id) from public.creator_referrals r
                    where r.creator_id = c.id and exists (select 1 from ev where ev.commission_usd > 0 and ev.ids @> array[r.app_user_id])),
    'earned_usd', round(coalesce((select sum(commission_usd) from ev), 0), 2),
    'pending_usd', round(greatest(0, coalesce((select sum(commission_usd) from ev where commission_usd > 0 and event_at >= now() - interval '30 days'), 0)), 2),
    'available_usd', round(greatest(0, (select s from settled) - (select s from paid) - (select s from asked)), 2),
    'requested_usd', round((select s from asked), 2),
    'paid_usd', round((select s from paid), 2)
  )
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- the creator
-- ---------------------------------------------------------------------------------------------------------------

-- Everything the portal shows. null = this account isn't a creator.
create or replace function public.creator_me() returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
declare c public.creators; res jsonb;
begin
  select * into c from public.creators where portal_user_id = (select auth.uid());
  if c.id is null then return null; end if;
  res := jsonb_build_object(
    'name', c.name, 'tiktok', c.tiktok, 'status', c.status, 'code', c.code,
    'rate', c.rate, 'months', c.months, 'min_withdraw_usd', 50, 'hold_days', 30,
    'link', private.site() || '/join/' || c.code,
    'payout_method', c.payout_method, 'payout_details', c.payout_details,
    'admin', private.is_portal_admin(),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'amount_usd', w.amount_usd, 'status', w.status,
                              'requested_at', w.requested_at, 'done_at', w.done_at) order by w.requested_at desc)
                             from public.creator_withdrawals w where w.creator_id = c.id), '[]'::jsonb),
    'months_chart', coalesce((select jsonb_agg(jsonb_build_object('month', m, 'usd', usd) order by m) from (
        select to_char(date_trunc('month', e.event_at), 'YYYY-MM') as m, sum(e.commission_usd)::numeric(12,2) as usd
        from public.purchase_events e
        where e.creator_id = c.id and e.event_at >= date_trunc('month', now()) - interval '5 months'
        group by 1) t), '[]'::jsonb));
  return res || private.creator_numbers(c);
end $$;

create or replace function public.creator_set_payout(p_method text, p_details text) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if p_method not in ('paypal', 'bank', 'other') then raise exception 'Pick PayPal, bank or other.'; end if;
  if length(trim(coalesce(p_details, ''))) < 3 then raise exception 'Add where to send the money.'; end if;
  update public.creators set payout_method = p_method, payout_details = left(trim(p_details), 400)
   where portal_user_id = (select auth.uid());
  if not found then raise exception 'Not a creator account.'; end if;
end $$;

-- Ask for everything available. At least $50, one open request at a time, payout details needed.
create or replace function public.creator_withdraw() returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare c public.creators; n jsonb; amt numeric;
begin
  select * into c from public.creators where portal_user_id = (select auth.uid()) for update;
  if c.id is null then raise exception 'Not a creator account.'; end if;
  if c.status <> 'approved' then raise exception 'Your account isn''t approved yet.'; end if;
  if c.payout_method is null then raise exception 'Add your PayPal or bank details first.'; end if;
  if exists (select 1 from public.creator_withdrawals where creator_id = c.id and status = 'requested') then
    raise exception 'You already have a withdrawal on its way.';
  end if;
  n := private.creator_numbers(c);
  amt := (n ->> 'available_usd')::numeric;
  if amt < 50 then raise exception 'You can withdraw once you have $50 available.'; end if;
  insert into public.creator_withdrawals (creator_id, amount_usd, method, details)
    values (c.id, amt, c.payout_method, c.payout_details);
  return jsonb_build_object('ok', true, 'amount_usd', amt);
end $$;

-- the join page counts a visit (anyone; once per browser per day is done on the page; at most 1 per call)
create or replace function public.creator_visit(p_code text) returns void
  language plpgsql security definer set search_path = '' as $$
declare cid uuid;
begin
  select id into cid from public.creators where code = trim(p_code) and active;
  if cid is null then return; end if;
  insert into public.creator_visits as v (creator_id, day, visits) values (cid, current_date, 1)
    on conflict (creator_id, day) do update set visits = v.visits + 1;
end $$;

revoke all on function public.creator_me(), public.creator_set_payout(text, text), public.creator_withdraw() from public, anon;
grant execute on function public.creator_me(), public.creator_set_payout(text, text), public.creator_withdraw() to authenticated;
revoke all on function public.creator_visit(text) from public;
grant execute on function public.creator_visit(text) to anon, authenticated;

-- called by functions/creator-auth (service role) right after it makes the account
create or replace function public.creator_register(p_user uuid, p_tiktok text, p_name text) returns text
  language plpgsql security definer set search_path = '' as $$
declare code text;
begin
  insert into public.creators (code, name, tiktok, portal_user_id, status, active, rate, months)
    values (private.new_code(), left(trim(p_name), 60), p_tiktok, p_user, 'pending', false, 0.20, 12)
    returning creators.code into code;
  return code;
end $$;
revoke all on function public.creator_register(uuid, text, text) from public, anon, authenticated;
grant execute on function public.creator_register(uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- admin
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.portal_admin_overview() returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  return jsonb_build_object(
    'creators', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'tiktok', c.tiktok, 'code', c.code, 'status', c.status, 'active', c.active,
        'rate', c.rate, 'months', c.months, 'created_at', c.created_at, 'portal', c.portal_user_id is not null,
        'payout_method', c.payout_method, 'payout_details', c.payout_details) || private.creator_numbers(c)
        order by (c.status = 'pending') desc, c.created_at desc) from public.creators c), '[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object(
        'id', w.id, 'creator', c.name, 'tiktok', c.tiktok, 'amount_usd', w.amount_usd, 'method', w.method,
        'details', w.details, 'status', w.status, 'requested_at', w.requested_at, 'done_at', w.done_at)
        order by (w.status = 'requested') desc, w.requested_at desc)
        from public.creator_withdrawals w join public.creators c on c.id = w.creator_id), '[]'::jsonb));
end $$;

create or replace function public.portal_admin_set_status(p_creator uuid, p_status text) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  if p_status not in ('approved', 'rejected', 'pending') then raise exception 'bad status'; end if;
  update public.creators set status = p_status, active = (p_status = 'approved') where id = p_creator;
end $$;

-- the money was sent: record the payout and close the request (or reject it, nothing paid)
create or replace function public.portal_admin_withdrawal(p_id bigint, p_paid boolean, p_note text default null) returns void
  language plpgsql security definer set search_path = '' as $$
declare w public.creator_withdrawals; pid bigint;
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  select * into w from public.creator_withdrawals where id = p_id and status = 'requested' for update;
  if w.id is null then raise exception 'That request is already done.'; end if;
  if p_paid then
    insert into public.creator_payouts (creator_id, amount_usd, note)
      values (w.creator_id, w.amount_usd, coalesce(nullif(trim(p_note), ''), w.method || ' ' || to_char(now(), 'YYYY-MM-DD')))
      returning id into pid;
    update public.creator_withdrawals set status = 'paid', done_at = now(), payout_id = pid, note = p_note where id = p_id;
  else
    update public.creator_withdrawals set status = 'rejected', done_at = now(), note = p_note where id = p_id;
  end if;
end $$;

revoke all on function public.portal_admin_overview(), public.portal_admin_set_status(uuid, text),
  public.portal_admin_withdrawal(bigint, boolean, text) from public, anon;
grant execute on function public.portal_admin_overview(), public.portal_admin_set_status(uuid, text),
  public.portal_admin_withdrawal(bigint, boolean, text) to authenticated;

-- for functions/creator-auth: may this caller reset passwords? (the function checks with the caller's own token)
create or replace function public.portal_is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_portal_admin()
$$;
revoke all on function public.portal_is_admin() from public, anon;
grant execute on function public.portal_is_admin() to authenticated;
