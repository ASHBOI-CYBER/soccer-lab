-- BACKUP (2026-10-29): delete the app, sign back in ? everything is still there.
-- CHEAP ON PURPOSE (user: Caffeine Mog's photo storage cost more than the profits): ONE row per player, ONE small
-- JSON blob (sessions, set log, minutes, streak days, answers, settings ? usually 5?40 KB) + ONE small profile picture
-- (240 px JPEG, ~12 KB, sent only when it changes). No Storage bucket, no files, no videos.
-- The app writes it at most when it goes to the background AND something changed, and reads it once per sign-in.
-- Hard caps below so one player can never grow the bill.

create table if not exists public.backups (
  user_id    uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  data       jsonb not null,
  photo      text,
  updated_at timestamptz not null default now(),
  constraint backups_data_small  check (pg_column_size(data) < 300000),
  constraint backups_photo_small check (photo is null or length(photo) < 40000)
);

alter table public.backups enable row level security;

drop policy if exists "own backup read" on public.backups;
drop policy if exists "own backup insert" on public.backups;
drop policy if exists "own backup update" on public.backups;
create policy "own backup read"   on public.backups for select to authenticated using (user_id = (select auth.uid()));
create policy "own backup insert" on public.backups for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own backup update" on public.backups for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select, insert, update on public.backups to authenticated;
