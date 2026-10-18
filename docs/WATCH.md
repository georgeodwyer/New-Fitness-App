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

## Things to check on a real watch (the simulator can't)

- GPS distance and pace feel right compared with a known route.
- Wrist taps when you go off pace, and at each new step.
- Voice cues through AirPods.
- The run keeps recording with your wrist down, and battery use over an hour is reasonable.
- After a run, it shows up on the iPhone within a minute or two of being together.

## If the first TestFlight upload fails

Apple may need the watch app's ID set up by hand, as with the widgets. At
<https://developer.apple.com/account/resources/identifiers>: find
`com.georgeodwyer.kinetix.watchkitapp` (create it if missing: App IDs → App), tick
**HealthKit**, save, then ask for a new build.
