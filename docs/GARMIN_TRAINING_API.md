# Garmin Connect: your plan on any Garmin watch, results back in Kinetix

**What it does.** Kinetix puts each planned run on the runner's **Garmin Connect calendar**
(warm-up, reps with pace targets, recoveries, cool-down). It syncs to **any Garmin watch** by
itself, with nothing extra to install, and runs in Garmin's own workout screens. When the run
is finished, Garmin sends the activity back to Kinetix (time, distance, pace, heart rate,
laps), which ticks off the plan and adapts as usual.

This is how apps such as Runna and TrainingPeaks work with Garmin. It needs two of Garmin's
APIs:

| API | What Kinetix uses it for |
|---|---|
| **Training API** | Put planned runs on the Garmin Connect calendar, change them when the plan changes, remove them when they're no longer planned. |
| **Activity API** | Get each finished run back, with laps and heart rate, so Kinetix can compare planned with actual. |

**Status:** not applied for yet. The server side is ready (below); the app side is switched
on once Garmin approves.

## 1. Apply (about 15 minutes, in a browser)

1. Open https://developer.garmin.com/gc-developer-program/overview and click **Apply** /
   **Request access**. Sign in with, or create, a Garmin account (use the account you'll
   own Kinetix with, not a personal one if you can).
2. Fill in the form:
   - **Company / app name:** Kinetix
   - **Website:** your website or App Store page (a simple landing page is fine).
   - **Privacy policy:** the link to Kinetix's privacy policy.
   - **APIs requested:** **Training API** and **Activity API**. Leave Health / Women's
     Health / Courses off.
   - **Description** (copy this):

     > Kinetix is an iPhone app that builds hybrid running and strength training plans that
     > adapt to each athlete. With the Training API we'd publish each user's planned
     > structured runs (warm-up, intervals with pace targets, recoveries, cool-down) to
     > their Garmin Connect calendar, updating them when the plan changes, so they can follow
     > the plan on any Garmin device. With the Activity API we'd receive the user's completed
     > activities (summary and laps) so the plan can mark sessions done and compare planned
     > with actual pace and heart rate. Data is shown only to the user it belongs to, is
     > never sold or shared, and is deleted when the user disconnects Garmin or deletes their
     > account. Nothing is used to train AI models.

   - **Expected users:** a realistic number (for example "under 1,000 in the first year").
3. Submit. Garmin replies by email; it can take a few weeks and they may ask follow-up
   questions. Send them to Claude and we'll answer them together.

Garmin may ask for these addresses (replace `<project>` with your Supabase project's id,
from its URL `https://<project>.supabase.co`):

| They ask for | Give them |
|---|---|
| OAuth redirect / callback URL | `https://<project>.supabase.co/functions/v1/garmin/callback` |
| Activity (summary / details) push URL | `https://<project>.supabase.co/functions/v1/garmin/webhook?key=<your webhook key>` |
| Deregistration push URL | the same webhook URL |
| User permission change push URL | the same webhook URL |

The **webhook key** is any long random string you make up (a password manager can generate
one). It stops anyone but Garmin sending runs in. You'll also save it in Supabase (step 2.4).

## 2. Once Garmin approves: the server (about 15 minutes)

Garmin sends a **client ID** and **client secret** (they may call them consumer key and
secret). Don't paste them into chat or the code: they go into Supabase only.

1. **Database.** Supabase dashboard → **SQL Editor** → **New query**. Paste the whole of
   [`supabase/garmin.sql`](../supabase/garmin.sql) and **Run**. ("Success. No rows returned.")
2. **Function.** **Edge Functions** → **Deploy a new function** → **Via Editor**. Name it
   exactly `garmin`, paste the whole of
   [`supabase/functions/garmin/index.ts`](../supabase/functions/garmin/index.ts) and **Deploy**.
3. In the function's settings switch **off** "Enforce JWT verification" / "Verify JWT".
   (Garmin's redirect and pushes don't carry a Kinetix sign-in; the app's own requests are
   checked inside the function.)
4. **Edge Functions → Secrets**, add:

   | Secret | Value |
   |---|---|
   | `GARMIN_CLIENT_ID` | from Garmin |
   | `GARMIN_CLIENT_SECRET` | from Garmin |
   | `GARMIN_WEBHOOK_KEY` | the webhook key you made up |

5. In Garmin's developer portal, set the callback and push URLs from the table above, and
   turn on **push** (not ping) for Activities and Activity Details if it asks.
6. Tell Claude. The app side is then switched on and tested: a **Connect Garmin** button in
   Settings, the next two weeks of runs sent to the calendar whenever the plan changes, and
   finished Garmin runs brought in when Kinetix opens.

**One thing to check with Garmin's documentation when it arrives:** the function and the
app use Garmin's usual addresses and workout format (sign-in, token, user id, workout and
schedule). They're all at the top of `supabase/functions/garmin/index.ts` and in
`GarminCalendar.swift`; if Garmin's documentation differs, Claude changes them there (the
addresses can also be overridden with Supabase secrets of the same name, without a redeploy).

## How it fits together

```
Kinetix app ──(planned runs, Garmin format)──▶ Supabase "garmin" ──▶ Garmin Connect calendar ──▶ watch
Kinetix app ◀──(reads, then deletes)── garmin_activities ◀── Supabase "garmin" ◀── Garmin (run finished)
```

- **Keys** stay in Supabase; the app never sees Garmin tokens.
- **Changes**: the app sends the next 14 days of planned runs; unchanged sessions are skipped,
  changed ones are replaced on the calendar, and ones no longer planned are removed.
- **Finished runs** wait in the `garmin_activities` table, readable only by that runner, and
  are deleted once Kinetix has saved them.
- **Disconnecting** (in Kinetix, or in Garmin Connect) deletes the tokens and calendar
  bookkeeping straight away.
- **Gym sessions** are runs-only for now. Garmin supports strength workouts too; they can
  follow once runs are working.
- The **Kinetix Connect IQ app** (`garmin/`, docs/GARMIN.md) stays as an optional extra for
  people who want Kinetix's own screens on the watch.

## Other brands

- **COROS:** a similar partner API that can push structured workouts and return activities.
  Also by application; worth doing after Garmin.
- **Polar:** doesn't let other apps send workouts to its watches. Polar runs still reach
  Kinetix through Apple Health.
- **Suunto:** not confirmed yet.
