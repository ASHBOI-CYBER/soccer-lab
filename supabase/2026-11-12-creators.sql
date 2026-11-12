-- CREATOR (AFFILIATE) PROGRAM (2026-11-12). A content creator gets ONE 6-digit code in the same number space as team,
-- gift, lifetime and 40%-off codes, so the app's one HAVE A CODE box and the existing invite link
-- (soccermax.app/join/<code>) work for creators with no website change. A viewer who opens the link or types the code
-- is tied to that creator; the creator earns `rate` (default 10%) of what we actually receive from that viewer
-- (price minus store commission and tax) for `months` months (default 12) after the viewer was tied to them.
--
-- Money never moves here: purchases come in from RevenueCat's webhook (functions/revenuecat-webhook), each one is
-- written once to purchase_events with the commission worked out at that moment, and payouts you send by hand
-- (PayPal, bank, Wise) are noted in creator_payouts. Nothing in this file is readable or writable from the app except
-- the functions granted at the bottom: every table has Row Level Security on and NO policies.
--
-- Run once in the Supabase SQL editor (safe to re-run). Then:
--   select * from public.new_creator('Alex Smith', 'alex@example.com');     -- makes a creator, returns code + links
--   select * from public.creator_balances;                                    -- who is owed what
--   insert into public.creator_payouts (creator_id, amount_usd, note) values ('<id>', 42.10, 'PayPal 2026-12-01');

-- ---------------------------------------------------------------------------------------------------------------
-- tables
-- ---------------------------------------------------------------------------------------------------------------

create table if not exists public.creators (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[0-9]{6}$'),
  name text not null check (length(name) between 1 and 60),          -- shown to viewers: "Alex Smith's code"
  email text,                                                        -- where to reach / pay them (never sent to the app)
  user_id uuid references auth.users (id) on delete set null,        -- their own app account, if any (blocks self-referral)
  rate numeric(5,4) not null default 0.10 check (rate >= 0 and rate <= 0.5),
  months integer check (months is null or months between 1 and 120) default 12,   -- null = every payment, forever
  dashboard_key uuid not null default gen_random_uuid(),             -- the secret in the creator's private stats link
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.creators enable row level security;

-- one row per customer: who brought them. `app_user_id` is RevenueCat's id for the customer = the Supabase user id once
-- they sign in with Apple, or RevenueCat's anonymous id when they bought before signing in.
create table if not exists public.creator_referrals (
  app_user_id text primary key,
  user_id uuid,                                   -- no foreign key: the money record outlives a deleted account
  creator_id uuid not null references public.creators (id),
  source text not null default 'code' check (source in ('code', 'purchase')),
  attributed_at timestamptz not null default now()
);
create index if not exists creator_referrals_creator on public.creator_referrals (creator_id);
create unique index if not exists creator_referrals_user on public.creator_referrals (user_id) where user_id is not null;
alter table public.creator_referrals enable row level security;

-- every RevenueCat event, once (event_id is RevenueCat's id, the same on retries).
create table if not exists public.purchase_events (
  event_id text primary key,
  type text not null,
  environment text,
  app_user_id text,
  ids text[] not null default '{}',               -- every id RevenueCat knows this customer by
  product_id text,
  store text,
  period_type text,
  transaction_id text,
  original_transaction_id text,
  currency text,
  price_usd numeric(12,4) not null default 0,     -- what the customer paid, in USD (negative = refund)
  net_usd numeric(12,4) not null default 0,       -- what we keep after the store's cut and tax
  creator_id uuid references public.creators (id),
  rate numeric(5,4),
  commission_usd numeric(12,4) not null default 0,
  event_at timestamptz not null,
  received_at timestamptz not null default now()
);
create index if not exists purchase_events_creator on public.purchase_events (creator_id, event_at);
create index if not exists purchase_events_tx on public.purchase_events (transaction_id);
create index if not exists purchase_events_ids on public.purchase_events using gin (ids);
alter table public.purchase_events enable row level security;

create table if not exists public.creator_payouts (
  id bigint generated always as identity primary key,
  creator_id uuid not null references public.creators (id),
  amount_usd numeric(12,2) not null check (amount_usd > 0),
  note text,
  paid_at timestamptz not null default now()
);
alter table public.creator_payouts enable row level security;

-- belt and braces: the app's roles get nothing on these tables even if a policy is added by mistake later
revoke all on public.creators, public.creator_referrals, public.purchase_events, public.creator_payouts from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- codes: creator codes share the one 6-digit number space
-- ---------------------------------------------------------------------------------------------------------------

create or replace function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where code = c)
          and not exists (select 1 from public.gifts where code = c)
          and not exists (select 1 from public.lifetime_codes where code = c)
          and not exists (select 1 from public.waitlist where code = c)
          and not exists (select 1 from public.creators where code = c);
  end loop;
  return c;
end $$;

-- make a creator (SQL editor / service role only). Returns what to send them.
create or replace function public.new_creator(p_name text, p_email text default null, p_rate numeric default 0.10, p_months integer default 12)
  returns table (creator_id uuid, creator_code text, share_link text, stats_link text)
  language plpgsql security definer set search_path = '' as $$
declare c public.creators;
begin
  insert into public.creators (code, name, email, rate, months)
    values (private.new_code(), trim(p_name), nullif(trim(p_email), ''), p_rate, p_months)
    returning * into c;
  return query select c.id, c.code,
    'https://soccermax.app/join/' || c.code,
    'https://soccermax.app/creator#' || c.code || '.' || c.dashboard_key::text;
end $$;
revoke all on function public.new_creator(text, text, numeric, integer) from public, anon, authenticated;
grant execute on function public.new_creator(text, text, numeric, integer) to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- the app: is this a creator code? / tie me to this creator
-- ---------------------------------------------------------------------------------------------------------------

-- the creator's display name, or null. Locked out while the account is over the shared 10-wrong-codes-per-hour limit
-- (private.code_misses), but a miss here is not counted: the app asks this for every code that isn't a team or gift,
-- and all it can reveal is a creator's public name.
create or replace function public.creator_preview(p_code text) returns text
  language plpgsql stable security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); n text;
begin
  if me is null then return null; end if;
  if (select count(*) from private.code_misses where code_misses.uid = me and at > now() - interval '1 hour') >= 10 then
    return null;
  end if;
  select name into n from public.creators where code = trim(p_code) and active;
  return n;
end $$;

-- {ok: true, name: "Alex"} or {ok: false, error: "..."}. First creator wins and is never replaced; an account that
-- has already paid can't be tied to a creator afterwards (that would hand out commission for a customer they didn't
-- bring). A wrong code is NOT counted as a miss here: the app calls this quietly with whatever code came from a link
-- (it may be a team code), and guessing creator codes through it gains nothing.
create or replace function public.claim_creator(p_code text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); c public.creators; mine public.creator_referrals;
begin
  if me is null then raise exception 'sign in first'; end if;
  select * into c from public.creators where code = trim(p_code) and active;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'That code doesn''t work.'); end if;

  select * into mine from public.creator_referrals where app_user_id = me::text or user_id = me limit 1;
  if mine.creator_id is not null then
    if mine.creator_id = c.id then return jsonb_build_object('ok', true, 'name', c.name); end if;
    return jsonb_build_object('ok', false, 'error', 'This account already used a creator code.');
  end if;
  if c.user_id = me then return jsonb_build_object('ok', false, 'error', 'You can''t use your own code.'); end if;
  if exists (select 1 from public.purchase_events e
             where e.ids @> array[me::text] and e.environment = 'PRODUCTION' and e.price_usd > 0) then
    return jsonb_build_object('ok', false, 'error', 'Creator codes only work before your first purchase.');
  end if;

  insert into public.creator_referrals (app_user_id, user_id, creator_id, source)
    values (me::text, me, c.id, 'code')
    on conflict do nothing;
  return jsonb_build_object('ok', true, 'name', c.name);
end $$;

revoke all on function public.creator_preview(text), public.claim_creator(text) from public, anon;
grant execute on function public.creator_preview(text), public.claim_creator(text) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RevenueCat webhook -> one row per event, commission worked out here (service role only)
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.record_purchase_event(p jsonb) returns text
  language plpgsql security definer set search_path = '' as $$
declare
  eid text := p->>'id';
  typ text := coalesce(p->>'type', '');
  env text := p->>'environment';
  v_ids text[];
  at_ timestamptz := to_timestamp(coalesce((p->>'event_timestamp_ms')::numeric, extract(epoch from now()) * 1000) / 1000.0);
  price numeric := coalesce((p->>'price')::numeric, 0);
  tax numeric := (p->>'tax_percentage')::numeric;
  cut numeric := (p->>'commission_percentage')::numeric;
  keep numeric;
  net numeric;
  ref public.creator_referrals;
  c public.creators;
  tag text := p #>> '{subscriber_attributes,creator_code,value}';
  prior public.purchase_events;
  r numeric;
  com numeric := 0;
  who uuid;
begin
  if eid is null or eid = '' then return 'no id'; end if;
  if exists (select 1 from public.purchase_events where event_id = eid) then return 'duplicate'; end if;

  -- every id for this customer (the current one, the first one, and any RevenueCat merged into it)
  select coalesce(array_agg(distinct x), '{}') into v_ids from (
    select p->>'app_user_id' as x
    union select p->>'original_app_user_id'
    union select jsonb_array_elements_text(case when jsonb_typeof(p->'aliases') = 'array' then p->'aliases' else '[]'::jsonb end)
  ) s where x is not null and x <> '';

  -- what we keep: price minus the store's cut and tax. Unknown cut = 30% (the worst case), so we never overpay.
  if tax is not null or cut is not null then keep := 1 - coalesce(tax, 0) - coalesce(cut, 0.30);
  elsif (p->>'takehome_percentage') is not null then keep := (p->>'takehome_percentage')::numeric;
  else keep := 0.70;
  end if;
  keep := greatest(0, least(1, keep));
  net := round(price * keep, 4);

  select * into ref from public.creator_referrals where app_user_id = any(v_ids) order by attributed_at limit 1;

  -- bought before signing in: the app tagged the RevenueCat customer with the code from the link. Tie them now,
  -- (a free-trial start counts), but never once they have already paid (same rule as claim_creator).
  if ref.creator_id is null and tag is not null and env = 'PRODUCTION'
     and typ in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL')
     and not exists (select 1 from public.purchase_events e where e.ids && v_ids and e.environment = 'PRODUCTION' and e.price_usd > 0) then
    select * into c from public.creators where code = trim(tag) and active;
    if c.id is not null and (c.user_id is null or not (c.user_id::text = any(v_ids))) then
      insert into public.creator_referrals (app_user_id, user_id, creator_id, source, attributed_at)
        values (coalesce(p->>'original_app_user_id', p->>'app_user_id'), null, c.id, 'purchase', at_)
        on conflict do nothing;
      select * into ref from public.creator_referrals where app_user_id = any(v_ids) order by attributed_at limit 1;
    end if;
  end if;

  if ref.creator_id is not null then select * into c from public.creators where id = ref.creator_id; end if;

  -- commission: real money only (never sandbox), on purchases and renewals inside the creator's window
  if c.id is not null and env = 'PRODUCTION' then
    if price > 0 and typ in ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE', 'REFUND_REVERSED')
       and (c.months is null or at_ <= ref.attributed_at + make_interval(months => c.months)) then
      r := c.rate;
      com := round(net * r, 4);
    elsif price < 0 then
      -- a refund takes back exactly what that payment earned (same rate), and nothing if it earned nothing
      select * into prior from public.purchase_events e
        where e.creator_id = c.id and e.commission_usd > 0
          and e.transaction_id is not null and e.transaction_id = p->>'transaction_id'
        order by e.event_at desc limit 1;
      if prior.event_id is not null then
        r := prior.rate;
        com := greatest(round(net * r, 4), -prior.commission_usd);
      end if;
    end if;
  end if;

  select x::uuid into who from unnest(v_ids) x
    where x ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' limit 1;
  if who is not null and ref.app_user_id is not null and ref.user_id is null then
    -- the anonymous buyer signed in later: remember the account, so claim_creator sees them as already tied
    update public.creator_referrals set user_id = who where app_user_id = ref.app_user_id
      and not exists (select 1 from public.creator_referrals o where o.user_id = who);
  end if;

  insert into public.purchase_events (event_id, type, environment, app_user_id, ids, product_id, store, period_type,
      transaction_id, original_transaction_id, currency, price_usd, net_usd, creator_id, rate, commission_usd, event_at)
    values (eid, typ, env, p->>'app_user_id', v_ids, p->>'product_id', p->>'store', p->>'period_type',
      p->>'transaction_id', p->>'original_transaction_id', p->>'currency', price, net, c.id, r, com, at_)
    on conflict (event_id) do nothing;
  return case when com <> 0 then 'commission' else 'recorded' end;
end $$;
revoke all on function public.record_purchase_event(jsonb) from public, anon, authenticated;
grant execute on function public.record_purchase_event(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- numbers: for you (creator_balances, SQL editor only) and for the creator (creator_stats, their private link)
-- ---------------------------------------------------------------------------------------------------------------

-- `payable` = earned more than 30 days ago (past the usual refund window) minus what was already paid out.
create or replace view public.creator_balances with (security_invoker = true) as
select c.id, c.code, c.name, c.email, c.rate, c.months, c.active,
  (select count(*) from public.creator_referrals r where r.creator_id = c.id) as signups,
  (select count(*) from public.creator_referrals r where r.creator_id = c.id and exists (select 1 from public.purchase_events e where e.creator_id = c.id and e.commission_usd > 0 and e.ids @> array[r.app_user_id])) as customers,
  coalesce((select sum(e.net_usd) from public.purchase_events e where e.creator_id = c.id and e.commission_usd <> 0), 0)::numeric(12,2) as net_sales_usd,
  coalesce((select sum(e.commission_usd) from public.purchase_events e where e.creator_id = c.id), 0)::numeric(12,2) as earned_usd,
  coalesce((select sum(p.amount_usd) from public.creator_payouts p where p.creator_id = c.id), 0)::numeric(12,2) as paid_usd,
  greatest(0,
    coalesce((select sum(e.commission_usd) from public.purchase_events e
              where e.creator_id = c.id and (e.commission_usd < 0 or e.event_at < now() - interval '30 days')), 0)
    - coalesce((select sum(p.amount_usd) from public.creator_payouts p where p.creator_id = c.id), 0))::numeric(12,2) as payable_usd
from public.creators c;
revoke all on public.creator_balances from anon, authenticated;

-- the creator's own numbers, opened with the secret key in their stats link. No customer details, totals only.
create or replace function public.creator_stats(p_code text, p_key uuid) returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
declare c public.creators; res jsonb;
begin
  select * into c from public.creators where code = trim(p_code) and dashboard_key = p_key;
  if c.id is null then return null; end if;
  select jsonb_build_object(
    'name', c.name, 'code', c.code, 'rate', c.rate, 'months', c.months, 'active', c.active,
    'link', 'https://soccermax.app/join/' || c.code,
    'signups', (select count(*) from public.creator_referrals r where r.creator_id = c.id),
    'customers', (select count(*) from public.creator_referrals r where r.creator_id = c.id and exists (select 1 from public.purchase_events e where e.creator_id = c.id and e.commission_usd > 0 and e.ids @> array[r.app_user_id])),
    'earned_usd', coalesce((select sum(e.commission_usd) from public.purchase_events e where e.creator_id = c.id), 0)::numeric(12,2),
    'paid_usd', coalesce((select sum(p.amount_usd) from public.creator_payouts p where p.creator_id = c.id), 0)::numeric(12,2),
    'last_30_days_usd', coalesce((select sum(e.commission_usd) from public.purchase_events e
                                  where e.creator_id = c.id and e.event_at >= now() - interval '30 days'), 0)::numeric(12,2),
    'months_chart', coalesce((select jsonb_agg(jsonb_build_object('month', m, 'usd', usd) order by m) from (
        select to_char(date_trunc('month', e.event_at), 'YYYY-MM') as m, sum(e.commission_usd)::numeric(12,2) as usd
        from public.purchase_events e
        where e.creator_id = c.id and e.event_at >= date_trunc('month', now()) - interval '5 months'
        group by 1) t), '[]'::jsonb)
  ) into res;
  return res;
end $$;
revoke all on function public.creator_stats(text, uuid) from public;
grant execute on function public.creator_stats(text, uuid) to anon, authenticated;
