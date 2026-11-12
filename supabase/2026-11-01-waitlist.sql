-- soccermax.app launch WAITLIST (2026-11-01, notes/38 ? site). Emails from the site / TikTok bio page until the app is live.
-- Nobody can read or change the table from outside: no policies, RLS on. The ONLY way in is join_waitlist() (adds one
-- email, 13+ ticked on the page), called by the site's Cloudflare worker. Read it in the Supabase dashboard / service key.
create table if not exists public.waitlist (
  email      text primary key check (email = lower(email) and length(email) between 6 and 254 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'),
  src        text check (length(src) <= 40),
  country    text check (length(country) <= 4),
  created_at timestamptz not null default now()
);
alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon, authenticated;

create or replace function public.join_waitlist(p_email text, p_src text default null, p_country text default null)
returns boolean            -- true = new on the list, false = was already on it
language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email));
begin
  insert into public.waitlist (email, src, country) values (e, left(p_src, 40), left(p_country, 4))
  on conflict (email) do nothing;
  return found;
end $$;
revoke all on function public.join_waitlist(text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text) to anon;
