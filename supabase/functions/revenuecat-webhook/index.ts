// REVENUECAT WEBHOOK (2026-11-12, supabase/2026-11-12-creators.sql). RevenueCat calls this for every purchase, renewal
// and refund; each event is written once to public.purchase_events, and when the customer came from a creator's code
// the creator's commission is worked out in the database (public.record_purchase_event).
//
// Who may call it: only RevenueCat. Two checks, both must pass:
//   1. the Authorization header equals the secret RC_WEBHOOK_AUTH (set the same value in RevenueCat's webhook form);
//   2. the HMAC signature header (X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>) matches RC_WEBHOOK_SIGNING_SECRET
//      over "<t>.<raw body>" and is less than 5 minutes old. RevenueCat shows that secret once when "HMAC webhook
//      signing" is switched on.
// Deploy with JWT checking off (RevenueCat has no Supabase token):
//   supabase functions deploy revenuecat-webhook --no-verify-jwt
//   supabase secrets set RC_WEBHOOK_AUTH=<long random text> RC_WEBHOOK_SIGNING_SECRET=<from RevenueCat>
// URL for RevenueCat: https://<project>.supabase.co/functions/v1/revenuecat-webhook
import { createClient } from "jsr:@supabase/supabase-js@2";

const enc = new TextEncoder();
const TOLERANCE_S = 300;
const MAX_BODY = 256 * 1024;

/** Compare without leaking where the two differ. */
function same(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

function hex(buf: ArrayBuffer) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function signed(header: string | null, raw: Uint8Array, secret: string) {
  if (!header) return false;
  const parts = Object.fromEntries(header.split(",").map((kv) => kv.trim().split("=", 2) as [string, string]));
  const t = Number(parts.t);
  if (!Number.isFinite(t) || !parts.v1) return false;
  if (Math.abs(Date.now() / 1000 - t) > TOLERANCE_S) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const head = enc.encode(`${parts.t}.`);
  const msg = new Uint8Array(head.length + raw.length);
  msg.set(head);
  msg.set(raw, head.length);
  const mac = hex(await crypto.subtle.sign("HMAC", key, msg));
  return same(enc.encode(mac), enc.encode(parts.v1.toLowerCase()));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("no", { status: 405 });
  const auth = Deno.env.get("RC_WEBHOOK_AUTH");
  const signing = Deno.env.get("RC_WEBHOOK_SIGNING_SECRET");
  // closed until both secrets are set: a webhook nobody can verify must never write money rows
  if (!auth || !signing) return new Response("not configured", { status: 500 });

  const got = req.headers.get("authorization") ?? "";
  if (!same(enc.encode(got), enc.encode(auth)) && !same(enc.encode(got), enc.encode(`Bearer ${auth}`))) {
    return new Response("no", { status: 401 });
  }
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.length > MAX_BODY) return new Response("too big", { status: 413 });
  if (!(await signed(req.headers.get("x-revenuecat-webhook-signature"), raw, signing))) {
    return new Response("bad signature", { status: 401 });
  }

  let event: Record<string, unknown> | undefined;
  try {
    event = JSON.parse(new TextDecoder().decode(raw))?.event;
  } catch {
    return new Response("bad json", { status: 400 });
  }
  if (!event || typeof event !== "object" || typeof event.id !== "string") return new Response("no event", { status: 400 });
  if (event.type === "TEST") return new Response("ok");

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await db.rpc("record_purchase_event", { p: event });
  if (error) {
    // 500 = RevenueCat tries again later (5 times over ~80 minutes); the event id makes a repeat harmless
    console.error("record_purchase_event failed", event.id, error.message);
    return new Response("try again", { status: 500 });
  }
  return new Response(String(data ?? "ok"));
});
