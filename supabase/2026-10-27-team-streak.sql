-- TEAM STREAK (2026-10-27, notes/26 "Team streak"). Run once on project drhuacxwmlrvaoyjqceg.
-- Each player's kept days (10+ min trained) for the last 400 days, as a hex bitmap: bit i (from the left,
-- 4 bits per hex char) = kept_end minus i days. The app works the team streak out from these + team_members.joined_at.
-- Text only, ? 100 chars per player. The app keeps working before this runs (team streak just shows join days).
alter table public.profiles
  add column if not exists kept text,
  add column if not exists kept_end date;
alter table public.profiles drop constraint if exists profiles_kept_len;
alter table public.profiles add constraint profiles_kept_len
  check (kept is null or (length(kept) <= 100 and kept ~ '^[0-9a-f]*$'));
