-- 2026-11-17: Apple one-time OFFER CODES for creators (Ali's plan: creators get 1 free month of Soccer Lab Pro).
-- An admin pastes the codes file from App Store Connect into the portal's Admin tab; every approved creator gets one
-- unused code automatically (on approval, or as soon as codes are added), shown on their dashboard with Apple's
-- redeem link. A code is only ever given to one creator. Deleting a creator deletes their code (it may be used).
create table if not exists public.creator_offer_codes (
  code text primary key check (code ~ '^[A-Za-z0-9]{6,32}$'),
  creator_id uuid references public.creators(id) on delete cascade,
  added_at timestamptz not null default now(),
  assigned_at timestamptz
);
create unique index if not exists creator_offer_codes_one_each on public.creator_offer_codes (creator_id) where creator_id is not null;
alter table public.creator_offer_codes enable row level security;   -- no policies: only the functions below touch it
revoke all on public.creator_offer_codes from anon, authenticated;

-- this creator's code, giving them the next unused one if they're approved and don't have one yet (null = none left)
create or replace function private.assign_offer_code(p_creator uuid) returns text
  language plpgsql security definer set search_path = '' as $$
declare got text;
begin
  select code into got from public.creator_offer_codes where creator_id = p_creator;
  if got is not null then return got; end if;
  if not exists (select 1 from public.creators where id = p_creator and status = 'approved') then return null; end if;
  update public.creator_offer_codes set creator_id = p_creator, assigned_at = now()
    where code = (select code from public.creator_offer_codes where creator_id is null
                  order by added_at, code limit 1 for update skip locked)
    returning code into got;
  return got;
end $$;
revoke all on function private.assign_offer_code(uuid) from public, anon, authenticated;

-- admin: add codes (the portal reads them out of the pasted file), then hand them to approved creators without one
create or replace function public.portal_admin_add_codes(p_codes text[]) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare n int; given int := 0; c record;
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  with ins as (
    insert into public.creator_offer_codes (code)
      select distinct trim(x) from unnest(coalesce(p_codes, '{}')) x where trim(x) ~ '^[A-Za-z0-9]{6,32}$'
      on conflict do nothing returning 1)
  select count(*) into n from ins;
  for c in select cr.id from public.creators cr
             where cr.status = 'approved' and not exists (select 1 from public.creator_offer_codes o where o.creator_id = cr.id)
             order by cr.created_at loop
    if private.assign_offer_code(c.id) is not null then given := given + 1; end if;
  end loop;
  return jsonb_build_object('added', n, 'given', given,
    'left', (select count(*) from public.creator_offer_codes where creator_id is null));
end $$;
revoke all on function public.portal_admin_add_codes(text[]) from public, anon;
grant execute on function public.portal_admin_add_codes(text[]) to authenticated;

-- a creator's own free-month code and Apple's redeem link (code null = not approved yet, or none left)
create or replace function public.creator_offer_code() returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare cid uuid; got text;
begin
  select id into cid from public.creators where portal_user_id = auth.uid() limit 1;
  if cid is null then raise exception 'Not a creator account.'; end if;
  got := private.assign_offer_code(cid);
  return jsonb_build_object('code', got, 'redeem_url',
    case when got is null then null else 'https://apps.apple.com/redeem?ctx=offercodes&id=6814847450&code=' || got end);
end $$;
revoke all on function public.creator_offer_code() from public, anon;
grant execute on function public.creator_offer_code() to authenticated;

-- approving a creator also gives them a code
create or replace function public.portal_admin_set_status(p_creator uuid, p_status text) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  if p_status not in ('approved', 'rejected', 'pending') then raise exception 'bad status'; end if;
  update public.creators set status = p_status, active = (p_status = 'approved') where id = p_creator;
  if p_status = 'approved' then perform private.assign_offer_code(p_creator); end if;
end $$;

-- the admin list shows each creator's code and how many are left
create or replace function public.portal_admin_overview() returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  return jsonb_build_object(
    'codes_left', (select count(*) from public.creator_offer_codes where creator_id is null),
    'creators', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'tiktok', c.tiktok, 'code', c.code, 'status', c.status, 'active', c.active,
        'rate', c.rate, 'months', c.months, 'created_at', c.created_at, 'portal', c.portal_user_id is not null,
        'email', (select u.email from auth.users u where u.id = c.portal_user_id),
        'offer_code', (select o.code from public.creator_offer_codes o where o.creator_id = c.id),
        'payout_method', c.payout_method, 'payout_details', c.payout_details) || private.creator_numbers(c)
        order by (c.status = 'pending') desc, c.created_at desc) from public.creators c), '[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object(
        'id', w.id, 'creator', c.name, 'tiktok', c.tiktok, 'amount_usd', w.amount_usd, 'method', w.method,
        'details', w.details, 'status', w.status, 'requested_at', w.requested_at, 'done_at', w.done_at)
        order by (w.status = 'requested') desc, w.requested_at desc)
        from public.creator_withdrawals w join public.creators c on c.id = w.creator_id), '[]'::jsonb));
end $$;
