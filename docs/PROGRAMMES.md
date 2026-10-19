# Writing programmes

Running programmes are written in `programmes/Kinetix Programmes.xlsx` and turned into the
file the app reads (`Packages/TrainingEngine/Sources/TrainingEngine/Resources/programmes.json`)
by a script. A goal with a programme uses it; goals without one keep the older rule-based
planner until theirs is written.

## Writing one

1. **Programmes tab:** length, runs per week (min/max), long-run cap, weekly volume cap,
   taper weeks, what happens after the last week.
2. **Run weeks:** one row per week: phase (Base, Build, Peak, Deload, Taper, Race week),
   volume as a % of the runner's starting volume, long run (`auto`, a %, km or `Race`),
   strength emphasis (Normal, Heavy, Light, None) and a note shown to the runner.
3. **Run sessions:** the runs in each week, with a session type and the workout in words.
   See "Writing a workout" on the Start here tab. Write distances for a mid-level runner
   (about 30 km a week); they set the shape of a run, not its size.

## Turning it into the app's file

```
python3 scripts/import_programmes.py
```

It lists anything it can't read (tab, row and the workout text) and writes nothing until
it's all fixed. Then run the engine tests: `ProgrammePlannerTests` checks the half
marathon for three example runners and prints a week-by-week preview (lines starting
`PREVIEW`).

## What the app does with it

- **Starting volume** = the runner's answer to "How far do you run in a typical week?",
  kept between the Rules tab's minimum and maximum for their level (or the default if they
  skip or don't run yet). Each week = its % × the starting volume.
- **Safety:** a week is never more than the Rules tab's max increase above the biggest of
  the last three weeks; no run is longer than the Rules' longest run or the programme's
  long-run cap; early long runs stay close to their longest recent run.
- **Long run:** `auto` is the Rules share of the week.
- **Rep sessions** keep their rep lengths. Lower-volume runners get fewer reps so hard
  running stays a sensible share of the week (fast reps ≤ 10% of the week, threshold ≤ 15%,
  half-marathon/steady ≤ 25%, each with a floor). An easy warm-up and cool-down are added
  (8% of the week each, between 1.5 and 3 km).
- **Other runs** share what's left: easy 1, recovery 0.75, shakeout 0.6, progression 1.15.
  A run that would be shorter than the Rules' shortest run is left out.
- **Run days:** fewer days than sessions → recovery runs go first, then easy runs, then
  shakeouts; more days → easy runs are added.
- **Race:** its full distance on race day, at race pace, not counted in the week's %. No
  lifting in race week if strength is "None", and never on race day or the day before.
- **Race date:** the programme is lined up so its last week is race week. If the race is
  sooner, the early weeks are skipped; if it's further away, the base weeks are repeated
  first.
- **Afterwards:** an easy recovery week (60% of the starting volume), then the programme
  again, starting from the runner's last four weeks of running.
- **Paces** come from their race time: E, STEADY (marathon pace + 10–20 s/km), M, HM, T,
  10K, 5K, I, R. `@ … effort` shows the pace as a guide only (no off-pace warnings); hills
  have no pace.
