# Writing programmes

Running programmes are written in `programmes/Kinetix Programmes.xlsx` and turned into the
file the app reads (`Packages/TrainingEngine/Sources/TrainingEngine/Resources/programmes.json`)
by a script. A goal with a programme uses it; goals without one keep the older rule-based
planner until theirs is written.

## Writing one

1. **Programmes tab:** length, runs per week (min/max), long-run cap, weekly volume cap,
   race-ready volume per level, taper weeks, what happens after the last week, and
   **Available to** (which running levels see the goal in onboarding; First 5K is beginners
   only).
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

- **Race-ready volume** (Programmes tab, by level) is what 100% means in Run weeks.
- **Where they start:** their answer to "How far do you run in a typical week?" (pre-filled
  from the last four weeks of runs in Kinetix, Strava and Apple Health when there are any),
  kept between the Rules tab's minimum and maximum for their level (or the default if they
  skip or don't run yet).
- **Each week** = its % × a base that starts at their current volume and moves towards
  race-ready: up by the max weekly increase after each normal week, or down by the Rules
  tab's ease-down rate (15%) each week if they're doing more than the race needs.
- **Easy first week:** only if they say in onboarding (or Settings) that they've raced in the
  last two weeks and want one: easy running at 60% of their current volume, then week 1.
  With a race date it comes out of the time before the race.
- **Safety:** a week is never more than the Rules tab's max increase above the biggest of
  the last three weeks; no run is longer than the Rules' longest run or the programme's
  long-run cap; early long runs stay close to their longest recent run.
- **Long run:** `auto` is the Rules share of the week.
- **Rep sessions** keep their rep lengths. Lower-volume runners get fewer reps so hard
  running stays a sensible share of the week (Rules tab: fast reps ≤ 10% of the week,
  threshold ≤ 15%, steady/HM/M ≤ 25%, each with a floor). An easy warm-up and cool-down are
  added (6% of the week each, 1.5–2.5 km). All of these are editable on the Rules tab.
- **Other runs** share what's left: easy 1, recovery 0.75, shakeout 0.6, progression 1.15.
  A run that would be shorter than the Rules' shortest run is left out. Recovery runs are at
  most 60% of the long run, easy runs 85%, shakeouts 15% of the week; spare volume adds an
  easy run when there's a free day.
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
  10K, 5K, I, R. EASY works as E, TEMPO as T, and 3K uses I pace (there's no 3K zone).
  `@ … effort` shows the pace as a guide only (no off-pace warnings); hills have no pace.

## Gym splits

The workbook's gym tabs hold every split (Full body ×1/×2/×3, Upper / Lower, Push / Pull /
Legs, PPL ×6, Upper / Lower / Full, PPL + Upper / Lower): each day's exercises, with
optional sets, reps, rest and a note per row (blank = the goal's default from the
sets/reps table). In onboarding (and Settings) the runner picks how many gym sessions a week
(0–6) and a split with that many days; the goal's default split is marked "Suggested". If
their runs and gym sessions don't fit their training days and doubles, they're told and the
plan keeps the runs the goal needs first. A named exercise their equipment can't do is swapped
for one with the same movement pattern.


## Hyrox

- **Goal:** Hyrox (all levels), with a division asked in onboarding (Open or Pro, women's or
  men's). The division sets station weights in gym sessions; change it in Settings → Training
  profile.
- **Running:** the Hyrox programme (12 weeks, a draft to edit). "Compromised" sessions are runs
  with station work between the reps: write them like any reps, with `station` in the recovery,
  e.g. `6 x 1 km @ HM, 2 min station between`. The station break has no pace target. The race is
  the 8 km of running, at half-marathon pace.
- **Stations:** SkiErg, Sled Push, Sled Pull, Burpee Broad Jumps, Rowing, Farmers Carry, Sandbag
  Lunges and Wall Balls are in the exercise list ("Any Hyrox station" picks one the user's
  equipment allows). For the distance stations, reps are metres. Starting weights are the race
  weights for the division (please check them against the current Hyrox rulebook):

  | Station | Open women | Open men | Pro women | Pro men |
  | --- | --- | --- | --- | --- |
  | Sled push (incl. sled) | 102 kg | 152 kg | 152 kg | 202 kg |
  | Sled pull (incl. sled) | 78 kg | 103 kg | 103 kg | 153 kg |
  | Farmers carry (per hand) | 16 kg | 24 kg | 24 kg | 32 kg |
  | Sandbag lunges | 10 kg | 20 kg | 20 kg | 30 kg |
  | Wall ball | 4 kg | 6 kg | 6 kg | 9 kg |

- **Gym splits:** "Hyrox: stations ×2" (Stations A, Stations B) and "Hyrox: strength + stations"
  (Strength A, Stations, Strength B, suggested for the goal).
- Rebuilding the workbook keeps the coach's own split days, "who it suits" text and sets/reps;
  the Hyrox drafts are only added when the copy doesn't have them yet.
