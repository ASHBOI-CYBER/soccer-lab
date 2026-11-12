-- 2026-10-30 ? App Store safety: block + report in team chat (Guideline 1.2) and in-app account deletion (5.1.1(v)).
-- Safe to re-run. Applied to drhuacxwmlrvaoyjqceg by MCP 2026-10-30.

-- BLOCKS: I never see posts from someone I blocked (the feed read rule below hides them on the server).
create table if not exists public.blocks (
  blocker uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);
alter table public.blocks enable row level security;
drop policy if exists "see own blocks" on public.blocks;
create policy "see own blocks" on public.blocks for select to authenticated using (blocker = (select auth.uid()));
drop policy if exists "add own blocks" on public.blocks;
create policy "add own blocks" on public.blocks for insert to authenticated with check (blocker = (select auth.uid()) and blocked <> (select auth.uid()));
drop policy if exists "remove own blocks" on public.blocks;
create policy "remove own blocks" on public.blocks for delete to authenticated using (blocker = (select auth.uid()));

-- the feed: my teams' posts, minus anyone I blocked
drop policy if exists "read team feed" on public.feed;
create policy "read team feed" on public.feed for select to authenticated using (
  team_id in (select private.my_teams())
  and user_id not in (select b.blocked from public.blocks b where b.blocker = (select auth.uid()))
);

-- REPORTS: written only through report_post (keeps a copy of the message, even if it's deleted later). Nobody can read
-- them from the app ? the developer reviews them in the Supabase dashboard (Table editor ? reports) within 24 h.
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter uuid references auth.users (id) on delete set null,
  reported uuid,
  post_id bigint,
  team_id uuid,
  kind text,
  body text,
  reason text not null,
  created_at timestamptz not null default now(),
  handled boolean not null default false
);
alter table public.reports enable row level security;   -- no policies: no direct reads or writes

create or replace function public.report_post(p_post bigint, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare f public.feed%rowtype;
begin
  select * into f from public.feed where id = p_post and team_id in (select private.my_teams());
  if not found then raise exception 'Message not found'; end if;
  insert into public.reports (reporter, reported, post_id, team_id, kind, body, reason)
  values ((select auth.uid()), f.user_id, f.id, f.team_id, f.kind, f.body, left(coalesce(p_reason, 'Other'), 60));
end $$;

create or replace function public.report_player(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.team_members where user_id = p_user and team_id in (select private.my_teams())) then
    raise exception 'Player not found';
  end if;
  insert into public.reports (reporter, reported, reason) values ((select auth.uid()), p_user, left(coalesce(p_reason, 'Other'), 60));
end $$;

-- DELETE MY ACCOUNT: removes the sign-in account; profiles, team memberships, posts, backups and gift codes all cascade.
-- Teams left with nobody on them go too.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid());
begin
  if me is null then raise exception 'Not signed in'; end if;
  delete from auth.users where id = me;
  delete from public.teams t where not exists (select 1 from public.team_members m where m.team_id = t.id);
end $$;

revoke all on function public.report_post(bigint, text) from public, anon;
revoke all on function public.report_player(uuid, text) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.report_post(bigint, text) to authenticated;
grant execute on function public.report_player(uuid, text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
