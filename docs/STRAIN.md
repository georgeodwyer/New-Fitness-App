# Exertion, recovery and heart-rate zones

In the app, strain is called **Exertion** and the morning
check-in is called **Your score**. The code still uses `Strain`, `RecoveryScore` and
`RecoveryCheckIn`.

The dashboard's strain card replaces the old load ratio. The ratio (last 7 days against an
average week of the last 4) is still worked out and still eases upcoming sessions after a big
jump; it's shown as "This week vs your usual" (a %) rather than as a number like 1.32.

## Heart-rate zones

- **Max heart rate:** 208 − 0.7 × age (asked in onboarding; editable in Settings → Training
  profile). If their runs in the last year show higher (second-highest run max, so one sensor
  spike can't move it), that's used instead. With neither, 190.
- **Zones** start at 50 / 60 / 70 / 80 / 90% of max. They can set their own max and zone
  starts in Settings → Training profile → Heart rate zones.

## Strain (0–21)

- **Load** = minutes weighted by intensity. With heart rate, each minute counts its zone
  (zone 1 = 1 … zone 5 = 5; below zone 1 = 0.5). With only an average heart rate, the whole
  session counts that zone. Without heart rate: minutes × effort (1–10) ÷ 2, which lands in
  the same place (an easy hour ≈ 120, a hard hour ≈ 240).
- **Other activity** counts too: other apps' workouts from Apple Health and Strava (not ones
  Kinetix recorded), and everyday steps outside runs and walks (3 per 1,000 steps).
- **Strain** = 21 × ln(1 + load/30) ÷ ln(1 + 1000/30): an easy hour ≈ 9.6, a hard hour ≈ 13,
  about four hours of racing = 21. Each point is harder to earn than the last.

## Recovery (0–100)

HRV (45%), resting heart rate (25%), sleep (20%) and Your score (10%), so the score leans on
HRV and the check-in only nudges it. Each reading scores 0–100, with a normal day for them at 50:

- **HRV:** last night against their usual (median of the last 30 days); ±30% spans 0–100
  (about 1.7 points per 1%). Last night alone, not an average, so a dip after drinks,
  illness or a big effort shows in full.
- **Resting heart rate:** this morning against usual; 5 points per beat.
- **Sleep:** last night against their need (their usual night, kept between 7 and 9 hours);
  12.5 points per 30 minutes. Until there are 5 nights: 4 h = 0, 6 h = 50, 8 h = 100.
- **Your score:** sleep, soreness and energy ratings; all 3s = 50.

Missing parts are left out and the rest re-weighted. Tap "What's behind it" on the card for
each reading, its score and the points it adds.

### Display scale

Those 0–100 figures are "vs usual" (50 = a normal day). They're shown on a friendlier scale:

| vs usual | 0 | 25 | 50 | 75 | 100 |
|---|---|---|---|---|---|
| Shown | 20 | 50 | 72 | 87 | 98 |

(straight lines between). The total is the weighted average of the shown readings. Labels:
under 50 Low, 50–69 Fair, 70–84 Good, 85+ Great. Decisions use the vs-usual total, so the
display scale changes nothing: below 34 eases today's exertion target by 30%, 67 and over
raises it by 10%.

### Waiting for last night

Health readings are only used once Health has been read today. If they normally record sleep
(a night in the last week), there's no recovery score until last night's sleep has arrived: the card
says "Waiting for last night's sleep", and Health readings can't ease the plan. Their own
score still can. The plan check runs once per day for each state of the data ("waiting",
"body" or "none"), so it runs again when the sleep arrives. Pull down on Today to refresh.

## Today's target

Today's planned sessions (minutes × planned effort ÷ 2) plus their usual everyday activity,
shown as a band ±1.5 strain. High recovery adds 10% to the load; low recovery takes 30% off.
Without a plan, their usual day over the last four weeks.

## Legs

Leg load: runs count fully, gym sessions by their share of lower-body sets, cycling 60%,
walking 50%. It halves every 36 hours. Compared with their usual (median of the last four
weeks): under 80% fresh, up to 130% OK, above that tired. With under two weeks of history,
fixed levels are used.
