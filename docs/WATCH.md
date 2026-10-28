# Kinetix on Apple Watch

The watch app comes inside the same TestFlight build as the iPhone app.

## Installing

1. Install the latest Kinetix build from TestFlight on your iPhone.
2. The watch app usually installs by itself. If it doesn't: open the **Watch** app on the
   iPhone → scroll to **Kinetix** → **Install** (or Settings → App Store on the watch →
   Automatic Downloads on).
3. Open Kinetix on the **iPhone** once, so it sends your plan to the watch. After that the
   plan is refreshed whenever you open the iPhone app.
4. Open Kinetix on the watch. The first time, allow Health (heart rate, saving workouts)
   and location.

## Running with the watch

- Pick **Today's** planned run, a **Free run**, one of **My workouts** (saved on the Record
  tab), or a run from **Coming up**. Check the steps and tap **Start**.
- **Main page:** time, pace (green on target, amber off), distance and heart rate.
  Swipe left for the current step and what's next; swipe right for Pause, End, Next step
  and Voice on/off.
- Off pace: a tap on the wrist (rising = speed up, falling = ease off) and, if voice is on,
  the same spoken cue as the iPhone (through AirPods if connected).
- **End** → summary → turn the Digital Crown for "How hard was that?" → **Save**.
- The run is saved to Apple Health on the watch straight away. It appears in Kinetix (history,
  load, plan ticked off, Strava if connected) next time the watch and iPhone are near each other.
  The list shows "runs waiting for your iPhone" until then.

You can leave the iPhone at home: the watch uses its own GPS and heart rate. (Cellular isn't
needed.)

## Starting a run on the iPhone (the watch mirrors it)

With **Settings → Integrations → Apple Watch → Open on Apple Watch when I start a run** on (the
default), starting a run on the iPhone opens Kinetix on the watch and shows the run there:

- The same pages as a watch run: the current rep (pace against target, distance left) and the
  whole run (time, distance, average pace), with heart rate.
- Wrist taps for pace, each new step, splits and the end of the session.
- **Pause**, **Next step** and **Finish** on the watch control the iPhone's run. Finish ends it on
  the iPhone, which then asks "How hard was that?". The watch goes back to its list.
- The iPhone records (GPS, voice cues through your earphones) and saves the run once: to Kinetix,
  Apple Health and Strava. The watch doesn't save a copy. Keep the iPhone with you.
- The watch sends its heart rate live. If you also have a chest strap paired, the iPhone asks
  "Heart rate from?" before the run starts (last answer first).
- If the watch is locked, off your wrist or out of range, the iPhone carries on as normal. Open
  Kinetix on the watch during the run and it joins in. "Waiting for iPhone…" means no update for
  15 seconds.

Starting a run on the watch is unchanged: it records on its own, as if the iPhone is at home.

## Things to check on a real watch (the simulator can't)

- GPS distance and pace feel right compared with a known route.
- Wrist taps when you go off pace, and at each new step.
- Voice cues through AirPods.
- The run keeps recording with your wrist down, and battery use over an hour is reasonable.
- After a run, it shows up on the iPhone within a minute or two of being together.
- Starting a run on the iPhone opens the watch app within a few seconds, numbers match the
  iPhone, Pause/Next step/Finish on the watch work, and only one workout appears in Apple Health.
- With a strap paired, the "Heart rate from?" question appears and the chosen source is used.

## If the first TestFlight upload fails

Apple may need the watch app's ID set up by hand, as with the widgets. At
<https://developer.apple.com/account/resources/identifiers>: find
`com.georgeodwyer.kinetix.watchkitapp` (create it if missing: App IDs → App), tick
**HealthKit**, save, then ask for a new build.

## Custom run screens

On the iPhone, Settings → Integrations → Apple Watch → Watch screens. Each screen has a
layout (1 big, 1 big + 2, 1 big + 4, 3 rows, 6 small) and a metric per slot, from pace,
heart rate, workout and extras (cadence, climb, calories, exertion so far, time of day).
Turn screens on or off and drag to reorder; they're sent to the watch with the plan
(`WatchPlan.screens`, along with the heart-rate zones for zone colours and exertion).
During a run the watch shows the controls, then (structured runs) the current rep, then
the screens in order. Standard set: Pace & distance and Heart rate on; Laps and Everything
off. The definitions and how each value is worked out are in the engine
(`Watch/WatchScreens.swift`, tested by `WatchScreensTests`). Cadence, climb and calories
are measured on the watch (`RunExtras`).
