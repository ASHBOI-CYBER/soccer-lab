-- 2026-11-25: team admins for the creator portal. An admin who signs up later is approved straight away.
insert into private.portal_admins (username) values ('@yrshfooty'), ('@soccerlab.app') on conflict do nothing;

create or replace function private.auto_approve_admin() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from private.portal_admins a where a.username = new.tiktok) and new.status <> 'approved' then
    update public.creators set status = 'approved', active = true where id = new.id;
    perform private.assign_offer_code(new.id);
  end if;
  return null;
end $$;
revoke all on function private.auto_approve_admin() from public, anon, authenticated;

drop trigger if exists creators_auto_approve_admin on public.creators;
create trigger creators_auto_approve_admin after insert on public.creators
  for each row execute function private.auto_approve_admin();

-- if either already signed up, approve them now
update public.creators set status = 'approved', active = true
 where tiktok in (select username from private.portal_admins) and status <> 'approved';
select username from private.portal_admins;
