-- MATCHDAY PACK (2026-10-28, notes/22 "Before launch"). One server pull for everyone instead of every phone
-- calling API-Football (100 calls/day for the whole key). Migration `matchday_pack` on drhuacxwmlrvaoyjqceg.

create table if not exists public.matchday_fixtures (
  id integer primary key,          -- API-Football fixture id
  day text not null,               -- "2026-10-28"
  league integer not null,
  data jsonb not null,             -- the raw fixture, exactly what the app's Fixture decoder reads
  created_at timestamptz not null default now()
);
create index if not exists matchday_fixtures_created_idx on public.matchday_fixtures (created_at desc);

alter table public.matchday_fixtures enable row level security;
-- public match data: anyone with the app can read it; only the edge function (service role) writes
create policy "anyone reads matchday" on public.matchday_fixtures for select using (true);
grant select on public.matchday_fixtures to anon, authenticated;

-- The nightly runs (migration `matchday_cron`). The password is made inside the database and never leaves it.
create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists pgcrypto with schema extensions;
create table if not exists private.matchday_cron (id int primary key default 1 check (id = 1), secret text not null);
insert into private.matchday_cron (secret) values (encode(extensions.gen_random_bytes(24), 'hex')) on conflict (id) do nothing;
revoke all on private.matchday_cron from public, anon, authenticated;
create or replace function public.matchday_cron_ok(p text) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.matchday_cron where secret = p)
$$;
revoke execute on function public.matchday_cron_ok(text) from public, anon, authenticated;
grant execute on function public.matchday_cron_ok(text) to service_role;

-- 23:50 UTC = Europe's games for the UTC day; 05:30 UTC = the Americas' evening (Brasileirao, MLS) for their day.
select cron.schedule('matchday-pull-europe', '50 23 * * *', $$
  select net.http_post(url := 'https://drhuacxwmlrvaoyjqceg.supabase.co/functions/v1/matchday-pull?tz=UTC',
    headers := jsonb_build_object('x-cron-secret', (select secret from private.matchday_cron)), timeout_milliseconds := 140000)
$$);
select cron.schedule('matchday-pull-americas', '30 5 * * *', $$
  select net.http_post(url := 'https://drhuacxwmlrvaoyjqceg.supabase.co/functions/v1/matchday-pull?tz=America/Sao_Paulo',
    headers := jsonb_build_object('x-cron-secret', (select secret from private.matchday_cron)), timeout_milliseconds := 140000)
$$);
