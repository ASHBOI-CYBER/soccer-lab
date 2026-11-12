// MATCHDAY NIGHTLY PULL (2026-10-28, notes/22 "Before launch").
// The API-Football free plan = 100 calls a day for the WHOLE key, today's games only. So phones never call it:
// this function runs twice a night (pg_cron, see 2026-10-28-matchday-pack.sql), takes the finished big-league games
// with a goal, and saves each raw fixture into public.matchday_fixtures. The app reads that table (anyone can read it).
// Cost: 1 day list + up to 8 fixtures per run = at most 18 calls a day.
// Secret: APISPORTS_KEY (the football key, set in the dashboard). pg_cron sends a random password made inside the
// database (private.matchday_cron) as x-cron-secret; public.matchday_cron_ok() checks it.
import { createClient } from "jsr:@supabase/supabase-js@2";

// same list as Matchday.leaguePriority in the app (lower = bigger)
const PRIORITY: Record<number, number> = {
  2: 0, 39: 1, 140: 2, 135: 3, 78: 4, 61: 5, 3: 6, 1: 0, 4: 0, 9: 1, 13: 6, 848: 7,
  94: 8, 88: 9, 40: 10, 253: 11, 71: 12, 307: 13, 262: 14, 45: 8, 143: 8, 137: 8, 81: 8, 66: 9,
};
const DONE = new Set(["FT", "AET", "PEN"]);
const PER_RUN = 8;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let last = 0;
async function football(path: string) {
  const wait = 6500 - (Date.now() - last); // the plan allows 10 calls a minute
  if (wait > 0) await sleep(wait);
  last = Date.now();
  const r = await fetch(`https://v3.football.api-sports.io/${path}`, {
    headers: { "x-apisports-key": Deno.env.get("APISPORTS_KEY")! },
  });
  if (!r.ok) throw new Error(`api-football ${r.status}`);
  return await r.json();
}

/** "2026-10-28" in a time zone. */
function dayIn(tz: string) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

Deno.serve(async (req) => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: ok } = await db.rpc("matchday_cron_ok", { p: req.headers.get("x-cron-secret") ?? "" });
  if (ok !== true) return new Response("no", { status: 401 });
  if (!Deno.env.get("APISPORTS_KEY")) return new Response("APISPORTS_KEY not set", { status: 500 });
  const tz = new URL(req.url).searchParams.get("tz") ?? "UTC";
  const date = dayIn(tz);

  const day = await football(`fixtures?date=${date}&timezone=${encodeURIComponent(tz)}`);
  const { data: have } = await db.from("matchday_fixtures").select("id").eq("day", date);
  const got = new Set((have ?? []).map((r: { id: number }) => r.id));
  const goals = (f: any) => (f.goals?.home ?? 0) + (f.goals?.away ?? 0);
  const prio = (f: any) => PRIORITY[f.league?.id] ?? 99;
  const want = (day.response ?? [])
    .filter((f: any) => DONE.has(f.fixture?.status?.short) && prio(f) < 99 && goals(f) >= 1 && !got.has(f.fixture.id))
    .sort((a: any, b: any) => prio(a) - prio(b) || goals(b) - goals(a))
    .slice(0, PER_RUN);

  const saved: number[] = [];
  for (const f of want) {
    try {
      const one = await football(`fixtures?id=${f.fixture.id}`);
      const fx = one.response?.[0];
      if (!fx) continue;
      const { error } = await db.from("matchday_fixtures").upsert({ id: fx.fixture.id, day: date, league: fx.league.id, data: fx });
      if (!error) saved.push(fx.fixture.id);
    } catch (_) { /* one bad match never stops the rest */ }
  }
  // keep two weeks
  await db.from("matchday_fixtures").delete().lt("created_at", new Date(Date.now() - 14 * 864e5).toISOString());
  return Response.json({ date, tz, candidates: want.length, saved });
});
