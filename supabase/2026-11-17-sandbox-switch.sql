-- SANDBOX TEST SWITCH (2026-11-17). Real commission only ever comes from real-money (PRODUCTION) purchases. To test the
-- whole creator flow with TestFlight's free sandbox purchases, an admin can turn this switch on for a while:
--   update private.settings set value = 'on'  where key = 'count_sandbox';   -- sandbox purchases count
--   update private.settings set value = 'off' where key = 'count_sandbox';   -- back to real money only
-- and afterwards remove the test rows: delete from public.purchase_events where environment = 'SANDBOX';
-- record_purchase_event below is 2026-11-12-creators.sql's, with its 2 PRODUCTION checks also accepting the switch.
create table if not exists private.settings (key text primary key, value text not null);
insert into private.settings values ('count_sandbox', 'off') on conflict do nothing;
create or replace function private.sandbox_counts() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select value = 'on' from private.settings where key = 'count_sandbox'), false)
$$;

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
  if ref.creator_id is null and tag is not null and (env = 'PRODUCTION' or private.sandbox_counts())
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
  if c.id is not null and (env = 'PRODUCTION' or private.sandbox_counts()) then
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
