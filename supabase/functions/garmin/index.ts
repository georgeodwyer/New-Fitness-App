// Kinetix × Garmin Connect: the server side of "send my plan to my Garmin watch".
//
// One function, five routes (…/functions/v1/garmin/<route>):
//   POST connect     (app, signed in)  → { url }: Garmin's sign-in page for this account
//   GET  callback    (Garmin redirect) → swaps the code for tokens, then back to the app
//   POST workouts    (app, signed in)  → publishes planned runs to the Garmin calendar
//   POST webhook     (Garmin push)     → finished activities, kept for the app to bring in
//   POST disconnect  (app, signed in)  → unlinks Garmin and deletes the tokens
//
// The Garmin keys never ship in the app: they live in this function's secrets
// (Supabase → Edge Functions → Secrets): GARMIN_CLIENT_ID, GARMIN_CLIENT_SECRET and
// GARMIN_WEBHOOK_KEY (any long random string, also put at the end of the webhook URL
// given to Garmin: …/garmin/webhook?key=<it>). SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are provided by Supabase. Turn "Verify JWT" OFF for this function: Garmin's redirect and
// pushes carry no Supabase sign-in, so the app routes check the sign-in themselves.
//
// Database: supabase/garmin.sql. Guide: docs/GARMIN_TRAINING_API.md.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// --- Garmin's addresses ------------------------------------------------------------------
// From Garmin's Connect Developer Program (OAuth 2.0 with PKCE, Training API, Activity API).
// Check these against the documentation Garmin sends with the approval; each can be
// overridden with a secret of the same name without changing the code.
const env = (name: string, fallback = "") => Deno.env.get(name) ?? fallback;
const GARMIN = {
  authorize: env("GARMIN_AUTHORIZE_URL", "https://connect.garmin.com/oauth2Confirm"),
  token: env("GARMIN_TOKEN_URL", "https://diauth.garmin.com/di-oauth2-service/oauth/token"),
  api: env("GARMIN_API_BASE", "https://apis.garmin.com"),
  userId: "/wellness-api/rest/user/id",
  deregister: "/wellness-api/rest/user/registration",
  workout: "/training-api/workout",
  schedule: "/training-api/schedule",
};
const APP_RETURN = "kinetix://garmin";
const PENDING_MINUTES = 15;
const MAX_WORKOUTS = 30;

type Link = {
  user_id: string;
  garmin_user_id: string | null;
  access_token: string;
  refresh_token: string | null;
  expires_at: string | null;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function redirect(to: string): Response {
  return new Response(null, { status: 302, headers: { Location: to } });
}

function admin(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
}

function configured(): boolean {
  return env("GARMIN_CLIENT_ID") !== "" && env("GARMIN_CLIENT_SECRET") !== "";
}

/** The signed-in Kinetix user making an app request, or null. */
async function signedInUser(req: Request, db: SupabaseClient): Promise<string | null> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data, error } = await db.auth.getUser(jwt);
  return error || !data.user ? null : data.user.id;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomString(length = 64): string {
  return base64url(crypto.getRandomValues(new Uint8Array(length))).slice(0, length);
}

async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

async function hash(value: unknown): Promise<string> {
  return Array.from(await sha256(JSON.stringify(value))).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function callbackURL(): string {
  return `${env("SUPABASE_URL")}/functions/v1/garmin/callback`;
}

/** Garmin's token endpoint (sign-in code or refresh). */
async function tokenRequest(params: Record<string, string>): Promise<Record<string, unknown>> {
  const body = new URLSearchParams({ client_id: env("GARMIN_CLIENT_ID"), client_secret: env("GARMIN_CLIENT_SECRET"), ...params });
  const response = await fetch(GARMIN.token, { method: "POST", body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`Garmin token request failed (${response.status})`);
  return data;
}

function expiry(data: Record<string, unknown>): string | null {
  const seconds = Number(data.expires_in);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(Date.now() + seconds * 1000).toISOString() : null;
}

/** A link with a usable access token, refreshed (and saved) when it's about to expire. */
async function fresh(db: SupabaseClient, link: Link): Promise<Link> {
  const expires = link.expires_at ? Date.parse(link.expires_at) : Infinity;
  if (expires - Date.now() > 60_000 || !link.refresh_token) return link;
  const data = await tokenRequest({ grant_type: "refresh_token", refresh_token: link.refresh_token });
  const updated: Link = {
    ...link,
    access_token: String(data.access_token),
    refresh_token: data.refresh_token ? String(data.refresh_token) : link.refresh_token,
    expires_at: expiry(data),
  };
  await db.from("garmin_links").update({
    access_token: updated.access_token, refresh_token: updated.refresh_token, expires_at: updated.expires_at,
  }).eq("user_id", link.user_id);
  return updated;
}

async function garmin(link: Link, path: string, init: RequestInit = {}): Promise<Response> {
  const url = path.startsWith("http") ? path : GARMIN.api + path;
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${link.access_token}`);
  if (init.body) headers.set("Content-Type", "application/json");
  return await fetch(url, { ...init, headers });
}

async function linkFor(db: SupabaseClient, userId: string): Promise<Link | null> {
  const { data } = await db.from("garmin_links").select("*").eq("user_id", userId).maybeSingle();
  return (data as Link | null) ?? null;
}

// --- Routes ----------------------------------------------------------------------------------

/** Garmin's sign-in page for this Kinetix account (PKCE). */
async function connect(req: Request, db: SupabaseClient): Promise<Response> {
  const userId = await signedInUser(req, db);
  if (!userId) return json({ message: "Sign in to Kinetix first." }, 401);
  const state = randomString(32);
  const verifier = randomString(64);
  await db.from("garmin_pending").delete().lt("created_at", new Date(Date.now() - PENDING_MINUTES * 60_000).toISOString());
  const { error } = await db.from("garmin_pending").insert({ state, user_id: userId, code_verifier: verifier });
  if (error) return json({ message: "Couldn't start the Garmin sign-in." }, 500);
  const url = new URL(GARMIN.authorize);
  url.search = new URLSearchParams({
    response_type: "code",
    client_id: env("GARMIN_CLIENT_ID"),
    code_challenge: base64url(await sha256(verifier)),
    code_challenge_method: "S256",
    redirect_uri: callbackURL(),
    state,
  }).toString();
  return json({ url: url.toString() });
}

/** Garmin sends the runner back here after they approve Kinetix. */
async function callback(req: Request, db: SupabaseClient): Promise<Response> {
  const params = new URL(req.url).searchParams;
  const state = params.get("state") ?? "";
  const code = params.get("code") ?? "";
  if (!state || !code) return redirect(`${APP_RETURN}?error=cancelled`);
  const { data: pending } = await db.from("garmin_pending").select("*").eq("state", state).maybeSingle();
  await db.from("garmin_pending").delete().eq("state", state);
  if (!pending || Date.now() - Date.parse(pending.created_at) > PENDING_MINUTES * 60_000) {
    return redirect(`${APP_RETURN}?error=expired`);
  }
  try {
    const tokens = await tokenRequest({
      grant_type: "authorization_code", code, code_verifier: pending.code_verifier, redirect_uri: callbackURL(),
    });
    let link: Link = {
      user_id: pending.user_id,
      garmin_user_id: null,
      access_token: String(tokens.access_token),
      refresh_token: tokens.refresh_token ? String(tokens.refresh_token) : null,
      expires_at: expiry(tokens),
    };
    const who = await garmin(link, GARMIN.userId);
    const garminUserId = who.ok ? String((await who.json()).userId ?? "") : "";
    if (!garminUserId) throw new Error("No Garmin user id");
    link = { ...link, garmin_user_id: garminUserId };
    // One Kinetix account per Garmin account: a re-link from another account moves it.
    await db.from("garmin_links").delete().eq("garmin_user_id", garminUserId).neq("user_id", link.user_id);
    const { error } = await db.from("garmin_links").upsert({
      ...link, scopes: tokens.scope ? String(tokens.scope) : null, connected_at: new Date().toISOString(),
    });
    if (error) throw error;
    return redirect(`${APP_RETURN}?connected=1`);
  } catch {
    return redirect(`${APP_RETURN}?error=failed`);
  }
}

type Scheduled = { sessionId: string; date: string; workout: Record<string, unknown> };

/** Publishes planned runs (from GarminCalendar in the app) and removes ones no longer planned. */
async function workouts(req: Request, db: SupabaseClient): Promise<Response> {
  const userId = await signedInUser(req, db);
  if (!userId) return json({ message: "Sign in to Kinetix first." }, 401);
  let link = await linkFor(db, userId);
  if (!link) return json({ message: "Garmin isn't connected." }, 409);
  const body = await req.json().catch(() => null) as { workouts?: Scheduled[]; from?: string } | null;
  const list = (body?.workouts ?? []).slice(0, MAX_WORKOUTS)
    .filter((w) => w && typeof w.sessionId === "string" && /^\d{4}-\d{2}-\d{2}$/.test(w.date ?? "") && w.workout);
  const from = /^\d{4}-\d{2}-\d{2}$/.test(body?.from ?? "") ? body!.from! : new Date().toISOString().slice(0, 10);
  link = await fresh(db, link);

  const { data: existingRows } = await db.from("garmin_workouts").select("*").eq("user_id", userId).gte("scheduled_date", from);
  type Row = { session_id: string; garmin_workout_id: string | null; content_hash: string };
  const existing = new Map<string, Row>(((existingRows ?? []) as Row[]).map((row) => [row.session_id, row]));
  const result = { created: 0, updated: 0, unchanged: 0, removed: 0, failed: 0 };

  const remove = async (garminWorkoutId: string | null) => {
    if (garminWorkoutId) await garmin(link!, `${GARMIN.workout}/${garminWorkoutId}`, { method: "DELETE" }).catch(() => {});
  };

  for (const item of list) {
    const contentHash = await hash({ date: item.date, workout: item.workout });
    const row = existing.get(item.sessionId);
    existing.delete(item.sessionId);
    if (row && row.content_hash === contentHash) { result.unchanged++; continue; }
    try {
      if (row) await remove(row.garmin_workout_id);
      const created = await garmin(link, GARMIN.workout, { method: "POST", body: JSON.stringify(item.workout) });
      if (!created.ok) throw new Error(`create ${created.status}`);
      const workoutId = String((await created.json()).workoutId ?? "");
      if (!workoutId) throw new Error("no workoutId");
      const scheduled = await garmin(link, GARMIN.schedule, { method: "POST", body: JSON.stringify({ workoutId, date: item.date }) });
      if (!scheduled.ok) throw new Error(`schedule ${scheduled.status}`);
      await db.from("garmin_workouts").upsert({
        user_id: userId, session_id: item.sessionId, scheduled_date: item.date, garmin_workout_id: workoutId,
        content_hash: contentHash, updated_at: new Date().toISOString(),
      });
      if (row) result.updated++; else result.created++;
    } catch {
      result.failed++;
    }
  }
  // Still on the calendar but no longer in the plan.
  for (const [sessionId, row] of existing) {
    await remove(row.garmin_workout_id);
    await db.from("garmin_workouts").delete().eq("user_id", userId).eq("session_id", sessionId);
    result.removed++;
  }
  return json(result);
}

/** Garmin pushes finished activities (and unlinks) here. Always answers 200 so Garmin doesn't retry forever. */
async function webhook(req: Request, db: SupabaseClient): Promise<Response> {
  const key = env("GARMIN_WEBHOOK_KEY");
  if (!key || new URL(req.url).searchParams.get("key") !== key) return json({ message: "Unknown sender" }, 401);
  const body = await req.json().catch(() => ({})) as Record<string, Array<Record<string, unknown>>>;

  const links = new Map<string, Link>();
  async function linkForGarmin(garminUserId: string): Promise<Link | null> {
    if (links.has(garminUserId)) return links.get(garminUserId)!;
    const { data } = await db.from("garmin_links").select("*").eq("garmin_user_id", garminUserId).maybeSingle();
    if (data) links.set(garminUserId, data as Link);
    return (data as Link | null) ?? null;
  }

  /** Items arrive in full ("push") or as a link to fetch them ("ping"). */
  async function items(list: Array<Record<string, unknown>>): Promise<Array<{ link: Link; item: Record<string, unknown> }>> {
    const out: Array<{ link: Link; item: Record<string, unknown> }> = [];
    for (const entry of list ?? []) {
      const link = await linkForGarmin(String(entry.userId ?? ""));
      if (!link) continue;
      if (typeof entry.callbackURL === "string") {
        try {
          const ready = await fresh(db, link);
          const response = await garmin(ready, entry.callbackURL);
          const fetched = response.ok ? await response.json() : [];
          for (const item of Array.isArray(fetched) ? fetched : []) out.push({ link: ready, item });
        } catch { /* fetched again on Garmin's next ping */ }
      } else {
        out.push({ link, item: entry });
      }
    }
    return out;
  }

  for (const [field, kind] of [["activities", "summary"], ["activityDetails", "details"], ["manuallyUpdatedActivities", "summary"]] as const) {
    for (const { link, item } of await items(body[field] ?? [])) {
      const activityId = String(item.activityId ?? item.summaryId ?? "");
      if (!activityId) continue;
      await db.from("garmin_activities").upsert(
        { user_id: link.user_id, garmin_activity_id: activityId, kind, payload: item },
        { onConflict: "garmin_activity_id,kind" },
      );
    }
  }
  // Unlinked in Garmin Connect: forget the tokens.
  for (const entry of body.deregistrations ?? []) {
    const link = await linkForGarmin(String(entry.userId ?? ""));
    if (!link) continue;
    await db.from("garmin_workouts").delete().eq("user_id", link.user_id);
    await db.from("garmin_links").delete().eq("user_id", link.user_id);
  }
  return json({ ok: true });
}

/** Unlinks Garmin: tells Garmin, removes the tokens and the calendar bookkeeping. */
async function disconnect(req: Request, db: SupabaseClient): Promise<Response> {
  const userId = await signedInUser(req, db);
  if (!userId) return json({ message: "Sign in to Kinetix first." }, 401);
  const link = await linkFor(db, userId);
  if (link) {
    try {
      await garmin(await fresh(db, link), GARMIN.deregister, { method: "DELETE" });
    } catch { /* removed here regardless */ }
  }
  await db.from("garmin_workouts").delete().eq("user_id", userId);
  await db.from("garmin_links").delete().eq("user_id", userId);
  return json({ ok: true });
}

Deno.serve(async (req: Request) => {
  if (!configured()) return json({ message: "Garmin isn't set up on the server yet (missing secrets)." }, 503);
  const route = new URL(req.url).pathname.split("/").filter(Boolean).pop() ?? "";
  const db = admin();
  try {
    if (route === "callback" && req.method === "GET") return await callback(req, db);
    if (req.method !== "POST") return json({ message: "Use POST" }, 405);
    switch (route) {
      case "connect": return await connect(req, db);
      case "workouts": return await workouts(req, db);
      case "webhook": return await webhook(req, db);
      case "disconnect": return await disconnect(req, db);
      default: return json({ message: `Unknown route '${route}'` }, 404);
    }
  } catch (error) {
    console.error(route, error);
    return route === "webhook" ? json({ ok: false }) : json({ message: "Something went wrong talking to Garmin." }, 502);
  }
});
