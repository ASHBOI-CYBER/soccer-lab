// CREATOR PORTAL ACCOUNTS (2026-11-17; supabase/2026-11-17-creator-portal.sql, site/portal.html).
// Creators sign up with email, TikTok @ and a password (2026-11-17, Ali's plan) and log in with email + password.
// The account is made already confirmed, so no email is ever sent (Supabase's built-in mailer only reaches the
// project's own team). Accounts made before this used <username>@creators.soccerlab.invalid.
//   {action: "signup", email, username, password}   -> makes the account + a pending creator (an admin approves)
//   {action: "reset", username}  + an admin's token   -> sets a new temporary password and returns it to the admin
// Deploy: supabase functions deploy creator-auth --no-verify-jwt
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

/** "@Sam.Football" -> "sam.football", or null if it isn't a valid TikTok-style username. */
function handle(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const u = raw.trim().replace(/^@/, "").toLowerCase();
  return /^[a-z0-9._]{2,24}$/.test(u) && !/^\.|\.$/.test(u) ? u : null;
}

function tempPassword() {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const b = crypto.getRandomValues(new Uint8Array(12));
  return [...b].map((x) => abc[x % abc.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "no" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  let body: { action?: string; email?: unknown; username?: unknown; password?: unknown };
  try {
    body = await req.json();
  } catch {
    return reply({ error: "Something went wrong. Try again." }, 400);
  }

  if (body.action === "signup") {
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 200) return reply({ error: "Enter a real email." }, 400);
    const u = handle(body.username);
    if (!u) return reply({ error: "Enter your TikTok @, like @samfootball (letters, numbers, dots, underscores)." }, 400);
    const pw = typeof body.password === "string" ? body.password : "";
    if (pw.length < 8 || pw.length > 72) return reply({ error: "Use a password of at least 8 characters." }, 400);
    const name = "@" + u;

    // a little brake on sign-up floods: at most 30 new creators waiting from the last hour
    const { count } = await admin.from("creators").select("id", { count: "exact", head: true })
      .eq("status", "pending").gte("created_at", new Date(Date.now() - 3600_000).toISOString());
    if ((count ?? 0) >= 30) return reply({ error: "Lots of sign-ups right now. Try again in an hour." }, 429);

    const { data: taken } = await admin.from("creators").select("id").eq("tiktok", "@" + u).maybeSingle();
    if (taken) return reply({ error: "That username already has an account. Log in instead." }, 409);

    const { data: made, error } = await admin.auth.admin.createUser({
      email, password: pw, email_confirm: true, user_metadata: { tiktok: "@" + u, creator: true },
    });
    if (error || !made?.user) {
      const dup = /already|exists|registered/i.test(error?.message ?? "");
      if (!dup) console.error("creator-auth: createUser", error?.message);
      return reply({ error: dup ? "That email already has an account. Log in instead." : "Couldn't make the account. Try again." }, dup ? 409 : 500);
    }
    const { error: regErr } = await admin.rpc("creator_register", { p_user: made.user.id, p_tiktok: "@" + u, p_name: name });
    if (regErr) {
      console.error("creator-auth: creator_register", regErr.message);
      await admin.auth.admin.deleteUser(made.user.id);
      return reply({ error: "Couldn't make the account. Try again." }, 500);
    }
    return reply({ ok: true, email });
  }

  if (body.action === "reset") {
    const auth = req.headers.get("authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return reply({ error: "Admins only." }, 401);
    const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: ok } = await asCaller.rpc("portal_is_admin");
    if (ok !== true) return reply({ error: "Admins only." }, 403);
    const u = handle(body.username);
    if (!u) return reply({ error: "No such username." }, 400);
    const { data: c } = await admin.from("creators").select("portal_user_id").eq("tiktok", "@" + u).maybeSingle();
    if (!c?.portal_user_id) return reply({ error: "No portal account with that username." }, 404);
    const pw = tempPassword();
    const { error } = await admin.auth.admin.updateUserById(c.portal_user_id, { password: pw });
    if (error) return reply({ error: "Couldn't reset it. Try again." }, 500);
    return reply({ ok: true, password: pw });
  }

  return reply({ error: "no" }, 400);
});
