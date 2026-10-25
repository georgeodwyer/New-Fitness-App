# Setting up Strava

Kinetix uploads finished runs (with route, splits and heart rate) to Strava, offers an
"Upload to Strava" button for gym sessions (or uploads them automatically if you switch that
on), and **imports activities recorded elsewhere** (a Garmin, the Strava app, Zwift…): runs
appear in Progress marked *From Strava*, and everything counts towards training load.

Strava's login needs the app's **client secret** to swap a login code for tokens. There are
two ways to hold it:

- **Now (testing): in the TestFlight build.** The secret is stored as a GitHub secret (never
  in the code) and baked into TestFlight builds. Quick, but someone with the app file could
  dig it out, so this is for you and a few testers only.
- **Before App Store release: in Supabase.** A tiny Edge Function holds the secret instead
  (see "Moving the secret to Supabase" below). As soon as the `SUPABASE_URL` secret is set,
  builds use Supabase and stop including the Strava secret: no code changes.

About 10 minutes, all in a web browser.

## 1. Create a Strava API application

1. Sign in at <https://www.strava.com/settings/api>.
2. Fill in:
   - **Application Name:** Kinetix
   - **Category:** Training
   - **Website:** any page you own (e.g. your GitHub profile)
   - **Authorization Callback Domain:** `localhost` ← exactly this
3. Agree to the terms and create it. Upload any icon when asked.
4. Keep this page open: you need the **Client ID** (a number) and the **Client Secret**
   (click "Show").

## 2. Give the build your Client ID and Client Secret

GitHub → your repository → **Settings → Secrets and variables → Actions → New repository
secret**, twice:

- name `STRAVA_CLIENT_ID`, value your Client ID
- name `STRAVA_CLIENT_SECRET`, value your Client Secret

Then ask Claude for a new TestFlight build (or run the TestFlight workflow yourself).

**Builds from Xcode on your Mac:** add both to `Config/Secrets.xcconfig`
(`STRAVA_CLIENT_ID = 12345` and `STRAVA_CLIENT_SECRET = abc…`). That file is git-ignored.

## 3. Connect

In the app: **Settings → Integrations → Strava → Connect with Strava**. Sign in, leave
**both** "Upload your activities" and "View data about your activities" ticked, and approve.
Kinetix then imports your last 90 days (check Progress → Running), and from now on:

- finished runs appear on Strava within a minute;
- gym sessions have an **Upload to Strava** button on their summary (or switch on
  "Upload gym sessions" to send them automatically);
- new Strava activities are imported whenever you open Kinetix (or tap **Check now**).

## Moving the secret to Supabase (before App Store release)

1. Set up Supabase (`docs/SUPABASE.md`) and add its `SUPABASE_URL` / `SUPABASE_ANON_KEY`
   GitHub secrets.
2. In the Supabase dashboard open your project → **Edge Functions** → **Deploy a new
   function** → **Via Editor**. Name it exactly `strava-token`, paste in the whole of
   `supabase/functions/strava-token/index.ts` from this repository, and **Deploy**.
3. In the function's settings switch **off** "Enforce JWT verification" / "Verify JWT".
   (It's safe: a code only works for your Strava app, after the athlete approved it.)
4. **Edge Functions → Secrets**: add `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET`.
5. Delete the `STRAVA_CLIENT_SECRET` GitHub secret, then make a new build. In Strava's API
   settings you can also **reset the client secret** (and update it in Supabase), so the
   one that was in testing builds stops working.

## Good to know

- New Strava apps can connect **one athlete (you)** until Strava reviews the app. Before
  inviting testers, request a review from the same settings page. Strava's brand rules
  (official "Connect with Strava" button and "Compatible with Strava" logo) are part of
  Milestone 9's polish.
- Rate limits: 200 requests per 15 minutes and 2,000 per day for the whole app. Each run
  upload uses about 3–6.
- Uploads that fail because you're offline are retried the next time Kinetix opens (for a
  week). Runs recorded with simulated GPS are never uploaded, and imported activities are
  never sent back to Strava or to Apple Health.
- The same workout is counted once: Kinetix's own uploads aren't imported back, and an
  activity that overlaps a Kinetix session (or an Apple Health workout) by half or more is
  treated as the same one.
- Imported runs' routes come from Strava's summary map, without timings, so they don't
  produce best efforts or pace charts. Their effort is estimated from heart rate; tap Edit
  on the run to set it yourself.
- Strava's API terms ask apps to show where data came from: imported runs are labelled
  *From Strava* with a "View on Strava" link.
- Disconnecting in Kinetix also revokes its access on Strava.

## Getting more athletes (before testers or launch)

New Strava apps can connect **one athlete** (you). Anyone else sees "Error 403: Limit of
connected athletes exceeded" on Strava's page; in test builds, Kinetix's Strava screen
explains this. To raise the limit, request a review with Strava's developer program form
(linked from developers.strava.com, under rate limits / athlete capacity). Have ready:

- Your app's **Client ID** (strava.com/settings/api).
- What Kinetix does with Strava: uploads your own runs and gym sessions; imports your own
  activities so your history and training load are complete. Each person only sees their
  own data, and Strava data isn't used to train AI models.
- Screenshots: the Connect with Strava button (Settings → Integrations → Strava) and an
  imported run (Progress → a run marked From Strava) showing "Powered by Strava" and
  "View on Strava".
- A link to the privacy policy.

### Brand images

Strava's rules ask for their own artwork, unchanged. Download the "Connect with Strava"
buttons and the "Powered by" / "Compatible with" logos from developers.strava.com/guidelines,
unzip them into one folder and run:

    python3 scripts/add_strava_assets.py path/to/strava-files

That adds `StravaConnectButton`, `PoweredByStrava` and `StravaCompatible` to the asset
catalog; the app switches from its plain stand-ins to them automatically.

