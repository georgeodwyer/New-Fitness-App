# Editing Kinetix's training rules

Kinetix's training logic reads its numbers from five JSON files. You can change them on
the GitHub website. No Xcode or coding needed.

All five live in
[`Packages/TrainingEngine/Sources/TrainingEngine/Resources/`](../Packages/TrainingEngine/Sources/TrainingEngine/Resources/).

| File | Controls |
|---|---|
| `plan_rules.json` | Weekly running volume, how fast it grows, recovery weeks, taper, run/lift mix per goal |
| `balance_rules.json` | Running-vs-lifting interference rules, load-ratio zones, recovery triggers, how the plan is eased |
| `strength_programmes.json` | Lifting sessions, sets × reps per goal, progression and deloads |
| `run_workouts.json` | The tempo / interval / long-run workout library |
| `exercises.json` | The exercise library and starting weights |

## How to make a change

1. On GitHub, open the file (switch to branch `claude/hybrid-running-strength-app-8rsowc`
   first), then click the **pencil ✏️** to edit.
2. Change only the **numbers** (or `true`/`false`). Keep the quotes, commas and brackets
   exactly as they are.
3. Click **Commit changes…**, add a short note ("Allow 12% weekly increase"), commit.
4. Wait for the **green tick** next to your commit (about 15–20 minutes). That means the
   app built and every check passed.
   - **Red cross** on "Training engine tests": a typo or out-of-range value (the log says
     which). Some tests also check the designed behaviour with the old numbers. If you
     changed something on purpose and a test fails, ask Claude to update the test.
5. In GitHub Desktop: **Fetch** → **Pull**, then **⌘R** in Xcode. Changes apply to plans
   built or extended after that (Settings → Regenerate my plan rebuilds immediately).

Tip: change one thing at a time so you can see its effect.

---

## `balance_rules.json`

### `scheduling`: keeping running and lifting from undermining each other
| Setting | Default | What it does |
|---|---|---|
| `noLowerBodyLiftDayBeforeHardRun` | `true` | No leg-heavy lifting the day before a tempo, interval or long run. |
| `noLowerBodyLiftOnLongRunDay` | `true` | No leg-heavy lifting on long-run day. |
| `pairLowerBodyLiftsWithHardRuns` | `true` | "Hard days hard, easy days easy": prefer putting leg sessions on the same day as a quality run (when double days are allowed), keeping other days easy. |

### `load`: the acute:chronic training-load ratio
Load = minutes × effort for every session. The ratio compares the last 7 days with your
average week over the last 28.

| Setting | Default | Safe range | What it does |
|---|---|---|---|
| `optimalRatioLow` | 0.8 | 0.7–0.9 | Below this you show as "undertrained". |
| `optimalRatioHigh` | 1.3 | 1.2–1.5 | Above this you show as "high" and the plan is eased. Lower = more cautious. |
| `minimumHistoryDays` | 14 | 7–28 | Days of history needed before a ratio is shown. |

### `recovery`: when a check-in counts as "not recovered"
Readiness is 0–1 from sleep, soreness and energy (all answers in the middle ≈ 0.5).

| Setting | Default | What it does |
|---|---|---|
| `poorReadinessBelow` | 0.42 | Readiness below this is poor recovery. Raise to ease the plan more often. |
| `verySoreAtOrAbove` | 5 | Soreness at this level (1–5) is poor recovery on its own. |
| `restingHeartRateElevatedBpm` | 7 | Resting HR this far above your usual counts as raised. |
| `restingHeartRateMinimumReadings` | 7 | Days of readings needed before "usual" means anything. |
| `bodySignalCountsWhenReadinessBelow` | 0.6 | A raised resting HR (or low HRV) only counts if readiness is also below this, because one odd reading on a good day is often noise. Set to 1 to always count it. |

### `rebalancing`: how the plan is eased
| Setting | Default | What it does |
|---|---|---|
| `easeHardSessionWithinDays` | 3 | Look this many days ahead for the next non-key hard session to ease. |
| `highLoadEasyRunFactor` | 0.8 | On a load spike, easy runs for the rest of the week are cut to this share (0.8 = 20% shorter). |
| `minimumEasyRunMinutes` | 20 | Never shorten a run below this. |
| `reducedLiftSetsFactor` | 0.6 | A "reduced" lift keeps this share of its sets. |
| `easedLongRunFactor` | 0.6 | An eased long run becomes this share of its length, at easy pace. |
| `easedRunMaxMinutes` | 45 | Eased runs and cross-training swaps are capped at this length. |

---

## `plan_rules.json`

### `goals`: one block per goal
| Setting | Example (balanced hybrid) | What it does |
|---|---|---|
| `runShare` | 0.55 | Share of weekly sessions that are runs (the rest are lifts). |
| `minLifts` / `maxLifts` | 2 / 3 | Lifting sessions per week. |
| `maxQuality` | 2 | Most hard runs (tempo/intervals) in a week. |
| `qualityOrder` | `["tempo","intervals"]` | Which hard run is added first. |
| `taperWeeks` | 1 | Weeks of taper before an event. |
| `longRunCapMeters` | 16000 | Longest long run, in metres. |
| `longRunShare` | 0.3 | Long run as a share of the week's running distance. |

### Volume and progression (distances in metres)
| Setting | Default | What it does |
|---|---|---|
| `startVolumeMeters` | 10 / 22 / 38 km | Starting weekly distance by experience. |
| `peakVolumeMeters` | by goal and level | Peak weekly distance. |
| `weeklyIncrease` | base 5%, build 8% | Planned growth per week in each phase. |
| `maxWeeklyIncrease` | 0.10 | Hard cap on growth over the previous full week (the "10% rule"). |
| `recoveryWeekEvery` | 4 | Every Nth week is a recovery week… |
| `recoveryWeekFactor` | 0.8 | …at this share of volume. |
| `taperFactors` | 0.75, 0.6, 0.45 | Volume in the final weeks before an event, last week last. |
| `maxRunMeters` / `minRunMeters` | | Limits for a single non-long run. |
| `quality` | by level and phase | Number of hard runs per week. |
| `plannedEffort` | easy 3 … intervals 8 | Planned effort (1–10) per session type, used for planned load. |
| `rollingHorizonWeeks` | 12 | Length of a plan with no event date. |

## `strength_programmes.json`
- `prescriptions`: sets, rep range and rest for **main** and **accessory** lifts per goal.
- `progression.increments`: kg added when every set hits the top of the rep range
  (barbell lower 5, upper 2.5; dumbbell 2…).
- `progression.maxRPEForIncrease` (9): only add weight if the average effort was at most this.
- `progression.stallsBeforeDeload` (3) and `deloadFraction` (0.1): after 3 stalled
  sessions, drop the weight by 10%.
- `splits`: which sessions are used for 1–4 lifting days a week. `sessions` lists each
  session's movement slots.
- `taperSetMultiplier` (0.6): share of sets kept in taper weeks.

## `run_workouts.json`
Each workout has a `type` (tempo, intervals, …), a `level`, warm-up/cool-down minutes and
`blocks` of repeats with a work and recovery step. Each step has a duration or distance and a
pace `zone` (easy, marathon, threshold, interval, repetition). Within a type and level,
workouts are in order: the plan moves one step along the list each week. To add one, copy an
existing workout, give it a new unique `id`, and edit.

## `exercises.json`
Each exercise has a `pattern` (squat, hinge, horizontalPush…), the minimum equipment it
`requires`, how it's `loading` (barbell, dumbbell, machine, bodyweight), body `region`, and
starting weights by level. For each pattern the plan picks the first exercise your equipment
allows, so order matters. Exercises marked `"libraryOnly": true` (pattern `library`) are only offered in the
gym tracker's exercise picker, grouped by `muscle` (chest, back, shoulders, arms, legs, glutes,
core, fullBody); add more the same way.
