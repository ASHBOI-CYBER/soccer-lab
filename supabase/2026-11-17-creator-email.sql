-- 2026-11-17 (later): creators sign up with email (Ali's plan); the admin list shows each creator's email.
create or replace function public.portal_admin_overview() returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_portal_admin() then raise exception 'Admins only.'; end if;
  return jsonb_build_object(
    'creators', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'tiktok', c.tiktok, 'code', c.code, 'status', c.status, 'active', c.active,
        'rate', c.rate, 'months', c.months, 'created_at', c.created_at, 'portal', c.portal_user_id is not null,
        'email', (select u.email from auth.users u where u.id = c.portal_user_id),
        'payout_method', c.payout_method, 'payout_details', c.payout_details) || private.creator_numbers(c)
        order by (c.status = 'pending') desc, c.created_at desc) from public.creators c), '[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object(
        'id', w.id, 'creator', c.name, 'tiktok', c.tiktok, 'amount_usd', w.amount_usd, 'method', w.method,
        'details', w.details, 'status', w.status, 'requested_at', w.requested_at, 'done_at', w.done_at)
        order by (w.status = 'requested') desc, w.requested_at desc)
        from public.creator_withdrawals w join public.creators c on c.id = w.creator_id), '[]'::jsonb));
end $$;

-- the signed-in portal user's TikTok @ (admins are listed by it): from their creator row now that logins are real
-- emails; accounts from before keep working through the old <username>@creators.soccerlab.invalid address.
create or replace function private.portal_username() returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select c.tiktok from public.creators c where c.portal_user_id = auth.uid() limit 1),
    case when (auth.jwt() ->> 'email') like '%@creators.soccerlab.invalid'
         then '@' || split_part(auth.jwt() ->> 'email', '@', 1) end)
$$;
revoke all on function private.portal_username() from public, anon;
