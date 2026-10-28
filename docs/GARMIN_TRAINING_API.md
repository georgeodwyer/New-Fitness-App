# Garmin Training API: sending your plan to any Garmin watch

**What it does:** with Garmin's Training API, Kinetix can put planned runs straight onto your
Garmin Connect calendar. They then sync to any Garmin watch and run in Garmin's own workout
screens, so you don't need the Kinetix Connect IQ app. Garmin has to approve Kinetix first.

**Status:** not applied for yet. Kinetix can't use the API until Garmin says yes, so nothing in
the app depends on it.

## How to apply (about 15 minutes, in a browser)

1. Open https://developer.garmin.com/gc-developer-program/training-api and click
   **Request access** (or **Apply**). It may ask you to sign in with, or create, a Garmin account.
2. Fill in the form:
   - **Company / app name:** Kinetix
   - **Website:** your app's website or App Store page (a simple landing page is fine).
   - **Description:** "Kinetix is an iPhone app that builds hybrid running and strength
     training plans. We'd like to publish each user's planned structured runs (warm-up,
     intervals with pace targets, cool-down) to their Garmin Connect calendar so they can
     follow the plan on any Garmin device."
   - **APIs wanted:** Training API. Leave the Health and Activity APIs off for now: Kinetix
     already gets finished runs back through Apple Health.
   - **Expected users:** a realistic estimate (for example "under 1,000 in year one").
3. Submit. Garmin usually replies by email. The program is aimed at businesses, so they may ask
   for more detail; send any questions to Claude and we'll answer them together.

## Once approved

Garmin sends a **consumer key and secret**. Don't paste them into chat or into the code.
Add them as GitHub secrets, as with TestFlight:

| Secret | Value |
|---|---|
| `GARMIN_CONSUMER_KEY` | the consumer key |
| `GARMIN_CONSUMER_SECRET` | the consumer secret |

Then tell Claude. The rest is code:
- a "Connect Garmin Connect" sign-in in Settings;
- publishing the next week's runs, using the same warm-up / repeats / cool-down grouping as the
  Apple Workout app (`WorkoutBlocks`);
- keeping them up to date when the plan changes.

The secret must stay on a server (Supabase), never in the app, so the sign-in goes through a
small Supabase function.

## Other brands

- **COROS:** has a partner API that can push structured workouts. It's by application too, and
  the same steps apply once Garmin is done.
- **Polar:** doesn't let other apps send workouts to its watches.
- **Suunto:** not confirmed yet.
