// Shared by the AI edge functions (film-review, food-scan; 2026-11-15): who is asking, what their subscription
// allows today, and taking one use off that allowance (public.ai_take in supabase/2026-11-15-ai-and-ranks.sql).
// Coach keeps its own copy of the subscription check (functions/coach) so it doesn't change while it is live.
import { createClient } from "jsr:@supabase/supabase-js@2";

export const MODEL = "claude-haiku-5-5";
const ENTITLEMENT = "soccer_max_pro";
const FIRST_WEEK_MS = 7 * 24 * 3600 * 1000;

/** Daily allowances. Trial = a free trial, an intro offer, or the first 7 days after the first purchase.
 *  2026-11-15: 2 a day each for everyone (keeps the worst-case AI bill well under what a yearly plan pays). */
export const LIMITS = {
  film: { trial: 2, paid: 2 },
  food: { trial: 2, paid: 2 },
} as const;
export type Kind = keyof typeof LIMITS;

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

export function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

/** The signed-in player and a database client that acts as them, or null when the token is missing or bad. */
export async function player(req: Request) {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data, error } = await db.auth.getUser(auth.slice(7));
  if (error || !data?.user) return null;
  return { id: data.user.id, db };
}

/** Today's allowance of `kind` for this player, from their RevenueCat subscription (0 = no subscription). */
export async function dailyLimit(uid: string, kind: Kind): Promise<number> {
  const l = LIMITS[kind];
  // Until RevenueCat is connected (testing, before payments are on) nobody can be checked: the trial allowance.
  const key = Deno.env.get("RC_SECRET_KEY");
  if (!key) return l.trial;
  try {
    const r = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!r.ok) {
      console.error(`${kind}: RevenueCat answered`, r.status);
      return l.trial;   // can't tell: the smaller allowance, never nothing
    }
    const sub = (await r.json())?.subscriber ?? {};
    const ent = sub.entitlements?.[ENTITLEMENT];
    const now = Date.now();
    if (!ent || (ent.expires_date && Date.parse(ent.expires_date) <= now)) return 0;
    const s = sub.subscriptions?.[ent.product_identifier] ?? {};
    const first = Date.parse(s.original_purchase_date ?? ent.purchase_date ?? "");
    const trial = s.period_type === "trial" || s.period_type === "intro" || (Number.isFinite(first) && now - first < FIRST_WEEK_MS);
    return trial ? l.trial : l.paid;
  } catch (e) {
    console.error(`${kind}: RevenueCat check failed`, e);
    return l.trial;
  }
}

type Db = NonNullable<Awaited<ReturnType<typeof player>>>["db"];

/**
 * Takes one use off today's allowance. Returns how many are left, or a ready error Response (no subscription,
 * or nothing left today).
 */
export async function take(db: Db, uid: string, kind: Kind, noun: string): Promise<number | Response> {
  const limit = await dailyLimit(uid, kind);
  if (limit < 1) return reply({ error: `${noun} is part of Soccer Lab Pro.`, remaining: 0 }, 403);
  const { data: left, error } = await db.rpc("ai_take", { p_kind: kind, p_limit: limit });
  if (error) {
    console.error(`${kind}: ai_take failed`, error.message);
    return reply({ error: "Something went wrong. Try again in a minute." }, 500);
  }
  if (typeof left !== "number" || left < 0) {
    return reply({ error: `That's all ${limit} ${noun.toLowerCase()}s for today. You get ${limit} more tomorrow.`, remaining: 0, limit }, 429);
  }
  return left;
}

/** The AI call failed: that use shouldn't count. */
export async function giveBack(db: Db, kind: Kind) {
  const { error } = await db.rpc("ai_give_back", { p_kind: kind });
  if (error) console.error(`${kind}: ai_give_back failed`, error.message);
}

/** A base64 JPEG from the app: checks the size and that it really is a JPEG. */
export function jpeg(b64: unknown, maxBytes: number): string | null {
  if (typeof b64 !== "string" || b64.length < 100 || b64.length > Math.ceil(maxBytes * 4 / 3) + 4) return null;
  if (!b64.startsWith("/9j/")) return null;   // JPEG files start FF D8 FF
  return b64;
}

/** The first text block, parsed as JSON (structured output), or null. */
export function parsed<T>(content: Array<{ type: string; text?: string }>): T | null {
  const text = content.find((b) => b.type === "text")?.text;
  if (!text) return null;
  try {
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}
