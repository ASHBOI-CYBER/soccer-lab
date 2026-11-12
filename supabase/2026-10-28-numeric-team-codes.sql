-- 6-DIGIT TEAM CODES (2026-10-28, notes/26 v3). The app's join keypad is numbers only, but the server still made
-- letter+digit codes, so no code it made could be typed in. Independent of the multi-teams file (migration `numeric_team_codes`).

create or replace function private.new_code() returns text
  language plpgsql set search_path = '' as $$
declare c text;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where code = c);
  end loop;
  return c;
end $$;

-- teams made before this keep working: give any letter code a fresh 6-digit one (1 team on 2026-10-28).
-- The old check only allowed [A-Z2-9] (no 0 or 1), so swap it for digits-only around the update. RUN 2026-10-28.
alter table public.teams drop constraint teams_code_check;
update public.teams set code = private.new_code() where code !~ '^[0-9]{6}$';
alter table public.teams add constraint teams_code_check check (code ~ '^[0-9]{6}$');
