# Kinetix on Garmin

The Kinetix Garmin app (`garmin/`, Connect IQ, written in Monkey C) runs your planned
runs on the watch: each step with its pace target, a buzz at every step, pace green on
target and amber off it, Back/Lap to skip a step. Runs are recorded as normal Garmin
runs (saved to Garmin Connect) and sent back to Kinetix on the iPhone, which ticks off
the plan and shows planned vs actual. First watch: Forerunner 965.

## How the pieces talk

iPhone Kinetix ⇄ Garmin Connect app (Connect IQ link) ⇄ Kinetix app on the watch.
No Kinetix server is needed. Message format: `GarminSync.swift` in TrainingEngine.

- The phone sends the next 7 days of runs whenever Kinetix opens, the plan changes, or the
  watch app opens and says hello. The watch keeps them, so it works without the phone.
- Saved runs are queued on the watch and re-sent until the phone confirms them.
- Kinetix doesn't upload Garmin runs to Strava or Apple Health: link those in Garmin
  Connect instead.

## One-off setup (owner)

1. **Garmin login for the build.** In GitHub → Settings → Secrets and variables → Actions,
   add `GARMIN_USERNAME` and `GARMIN_PASSWORD` (your Garmin account; two-step
   verification must be off for it, or use a separate Garmin account). The build needs
   them to download Garmin's watch definitions. Without them the Garmin build is skipped.
2. **Optional: a permanent developer key** (`CIQ_DEVELOPER_KEY`, base64 of a `.der`
   key). Not needed for testing; the store needs the same key every time.
3. **Optional: let this dev environment reach Garmin.** Add `developer.garmin.com` to the
   environment's allowed domains so the docs and SDK can be read here too.

## Installing a test build on the Forerunner 965

1. Open the latest **Garmin watch app** run in GitHub Actions and download the
   `kinetix-garmin` artifact (a zip with `Kinetix-fr965.prg`).
2. Connect the watch to a computer with its USB cable. On a Mac use the free
   *OpenMTP* app (Garmin watches use MTP); on Windows it shows as a drive.
3. Copy `Kinetix-fr965.prg` into `GARMIN/APPS` on the watch, then unplug.
4. Kinetix appears in the watch's activity/app list.
5. On the iPhone: Kinetix → Settings → Garmin → Connect a Garmin watch, choose the watch
   in Garmin Connect, and you're returned to Kinetix.

## Later

- More watches: add products to `garmin/manifest.xml` (screen layouts scale with size).
- Gym sessions on the watch.
- Connect IQ Store listing (needs a developer account, the permanent key and store review).
