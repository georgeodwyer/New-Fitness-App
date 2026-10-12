# Setting up Strava

Kinetix uploads finished runs (with route, splits and heart rate) and, optionally, strength
sessions to Strava. To keep Strava's **client secret** out of the app, the app swaps the
login code for tokens through a tiny Supabase Edge Function, so **Supabase needs setting up
first** (see `docs/SUPABASE.md`).

Everything below is done in a web browser: no Terminal needed. About 15 minutes.

## 1. Create a Strava API application

1. Sign in at <https://www.strava.com/settings/api>.
2. Fill in:
   - **Application Name:** Kinetix
   - **Category:** Training
   - **Website:** any page you own (e.g. your GitHub profile)
   - **Authorization Callback Domain:** `localhost` ← exactly this
3. Agree to the terms and create it. Upload any icon when asked.
4. Keep this page open: you need the **Client ID** (a number) and the **Client Secret**.

## 2. Add the token-exchange function to Supabase

1. In the Supabase dashboard open your project → **Edge Functions** → **Deploy a new
   function** → **Via Editor**.
2. Name it exactly `strava-token`.
3. Delete the sample code, then paste in the whole of
   `supabase/functions/strava-token/index.ts` from this repository (open it on GitHub and
   use the copy button). Click **Deploy**.
4. Open the function's **Details** (or **Settings**) and switch **off** "Enforce JWT
   verification" / "Verify JWT", then save. (The function is safe without it: a code only
   works for your Strava app and only after the athlete approved it.)
5. Go to **Edge Functions → Secrets** and add two secrets:
   - `STRAVA_CLIENT_ID` = your Client ID
   - `STRAVA_CLIENT_SECRET` = your Client Secret

## 3. Give the app your Client ID

The Client ID isn't secret, but it's kept with the other settings:

- **TestFlight builds:** GitHub → your repository → Settings → Secrets and variables →
  Actions → New repository secret → name `STRAVA_CLIENT_ID`, value your Client ID.
- **Builds from Xcode on your Mac:** add a line to `Config/Secrets.xcconfig`:
  `STRAVA_CLIENT_ID = 12345` (see `docs/SUPABASE.md` for creating that file).

## 4. Connect

In the app: **Settings → Integrations → Strava → Connect with Strava**. Sign in, leave
"Upload your activities" ticked and approve. Then finish a real (not simulated) run: it
appears on Strava within a minute.

## Good to know

- New Strava apps can connect **one athlete (you)** until Strava reviews the app. Before
  inviting testers, request a review from the same settings page. Strava's brand rules
  (official "Connect with Strava" button and "Compatible with Strava" logo) are part of
  Milestone 9's polish.
- Rate limits: 200 requests per 15 minutes and 2,000 per day for the whole app. Each run
  upload uses about 3–6.
- Uploads that fail because you're offline are retried the next time Kinetix opens (for a
  week). Runs recorded with simulated GPS are never uploaded.
- Disconnecting in Kinetix also revokes its access on Strava.
