// Kinetix: Strava token exchange.
//
// The app sends either { grant_type: "authorization_code", code } after the athlete
// approves Kinetix on Strava, or { grant_type: "refresh_token", refresh_token } when its
// access token expires. This function adds the client secret (which must never ship in
// the app) and forwards the request to Strava.
//
// Secrets (Supabase dashboard → Edge Functions → Secrets): STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET.
// JWT verification can be off: a code is only valid for this Strava app and only after the
// athlete has approved it, so the function grants nothing on its own.

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ message: "Use POST" }, 405);

  const clientId = Deno.env.get("STRAVA_CLIENT_ID");
  const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    return json({ message: "Strava isn't configured on the server yet (missing secrets)." }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ message: "Invalid JSON" }, 400);
  }

  const params = new URLSearchParams({ client_id: clientId, client_secret: clientSecret });
  if (body.grant_type === "authorization_code" && typeof body.code === "string" && body.code.length > 0) {
    params.set("grant_type", "authorization_code");
    params.set("code", body.code);
  } else if (body.grant_type === "refresh_token" && typeof body.refresh_token === "string" && body.refresh_token.length > 0) {
    params.set("grant_type", "refresh_token");
    params.set("refresh_token", body.refresh_token);
  } else {
    return json({ message: "Expected grant_type authorization_code (with code) or refresh_token (with refresh_token)." }, 400);
  }

  let response: Response;
  try {
    response = await fetch(STRAVA_TOKEN_URL, { method: "POST", body: params });
  } catch {
    return json({ message: "Couldn't reach Strava" }, 502);
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    // 400/401 from Strava mean the code or refresh token is no longer valid.
    const status = response.status === 429 || response.status >= 500 ? 503 : 400;
    return json({ message: data.message ?? "Strava rejected the request", errors: data.errors }, status);
  }

  // Pass back only what the app needs.
  return json({
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_at: data.expires_at,
    athlete: data.athlete
      ? { id: data.athlete.id, firstname: data.athlete.firstname, lastname: data.athlete.lastname }
      : undefined,
  });
});
