# Handover notes (for a new Claude Code session)

Read this, then `docs/PLAN.md`, before doing anything. Work on branch
`claude/hybrid-running-strength-app-8rsowc`; commit and push after each logical step.

## Status

All nine milestones are done. The app is on the owner's iPhone for testing. **Next:** the
owner's feedback and feature requests (they've mentioned wanting a more visual view of the
training logic), then App Store submission (docs/APP_STORE.md).

| # | Milestone | State |
|---|---|---|
| 1 | Setup, design system, data model, navigation | ✅ |
| 2 | Onboarding + plan generation engine | ✅ |
| 3 | Strength trainer, logging, double progression, PRs | ✅ |
| 4 | Running trainer, background GPS, audio pace cues, simulated GPS | ✅ |
| 5 | Dashboard, sRPE load / ACWR, skip/swap/rebalancing | ✅ |
| 6 | Settings (coaching, training profile, units, export, delete) | ✅ |
| 7 | Supabase accounts + sync (REST, LWW, RLS) | ✅ code done; owner still has to create the Supabase project (docs/SUPABASE.md) |
| 8 | HealthKit (read HR, resting HR, workouts; write runs + lifts), live HR from Apple Watch via HealthKit and BLE chest straps (Heart Rate service 0x180D), Strava OAuth + auto-upload of runs | ✅ owner still has to register the Strava app (docs/STRAVA.md) |
| 9 | Polish: empty states, errors, Dynamic Type/VoiceOver pass, privacy manifest, permission strings, health disclaimer in onboarding | ✅ |

## About the owner

- Not a professional developer: explain decisions briefly in plain English, and say clearly
  when they need to do something (accounts, keys, settings) with step-by-step instructions.
- Has an **Intel Mac**: newest Xcode needs Apple silicon, so they should use **Xcode 26** from
  developer.apple.com/download/all (needs macOS 15.6+). Otherwise they test via the CI
  screenshots/video or TestFlight. Joining the Apple Developer Program (in progress).
- Wants things visual; liked the Stitch-based design (screens in `Designs/`).

## How to work in this environment

- The cloud container is **Linux with no Swift toolchain** (download.swift.org is blocked).
  You can't compile locally. **GitHub Actions is the compiler**:
  - `engine-linux` job: `swift test` for the package (TrainingEngine + KinetixSync), ~1 min.
  - `ios` job (macos-latest): XcodeGen → build-for-testing → app unit tests, ~12 min.
    The UI screenshot walk-through (`KinetixUITests/ScreenshotTests.swift`) is **off by default
    at the owner's request** (they test each build themselves via TestFlight). Run it only on
    request: workflow_dispatch with input `screenshots: true`. Keep its steps compiling.
  - The macOS runner is sometimes not assigned (job cancelled after 15 min with no steps):
    that's GitHub capacity / Actions minutes, not the code. Re-run once.
- Check CI with the GitHub MCP tools (`actions_list` list_workflow_runs/list_workflow_jobs,
  `get_job_logs` with failed_only or job_id + tail_lines). Compiler errors appear as
  `error:` lines just before "---- last 80 lines of build.log ----". A new push cancels the
  in-progress run (concurrency), so batch changes. Docs-only changes skip CI.
- Wait for CI with a background `sleep N` (foreground sleep is blocked).
- CI commits the generated `Kinetix.xcodeproj` + `Kinetix/Info.plist` back to the branch
  (so the owner can open the project without XcodeGen/Homebrew, which their Intel Mac can't
  run). Always `git pull --rebase` before pushing. Never hand-edit the project: change
  `project.yml`.
- Artifacts can't be downloaded from here (blob storage blocked) — read file lists from logs.

## Architecture (short)

- `Packages/TrainingEngine` (Swift package, Foundation only):
  - `TrainingEngine`: domain types, pace zones (VDOT), JSON templates in `Resources/`,
    PlanGenerator/OutlineBuilder/MixBuilder/WeekScheduler (interference rules), RunBuilder,
    StrengthBuilder, Progression (double progression), Records, RunEngine + PaceSmoother +
    Announcer + SimulatedRunner, LoadModel (sRPE, ACWR), Rebalancer (skip/swap/adjust).
  - `KinetixSync`: SupabaseClient (actor, REST), SyncRecord/JSONValue/SyncMerge.
  - Make new public structs' initialisers `public` if the app constructs them.
- `Kinetix/` app (SwiftUI, SwiftData, iOS 17, Swift 5 mode). `project.yml` → XcodeGen.
  - Design system: `DesignSystem/` (KXColor tokens incl. validated chart colours
    run=orange/lift=teal, status colours always icon+label; KXFont, KXSpacing, components).
  - Persistence: `Persistence/Models/*` (@Model, all `SyncTracked`: id/updatedAt/deletedAt/
    needsSync), `SyncMapping.swift` (each model ↔ JSON payload; add new fields there too).
  - Services: PlanService, StrengthService, RunService, BalanceService, DashboardService,
    AccountService (export/delete/units), AuthService (+Keychain), SyncService,
    LocationService (GPS + simulated), VoiceCoach (ducking speech).
  - Features: Onboarding, Home (dashboard), Plan, Strength, Run, Progress, Settings, Account.
- Secrets: `Config/Secrets.xcconfig` (git-ignored) → Info.plist keys SupabaseURL,
  SupabaseAnonKey, StravaClientID. TestFlight workflow writes it from repo secrets.
- Launch args for UI tests: `-ui-testing` (in-memory DB), `-seed-sample`, `-seed-history`,
  `-dark`, `-simulate-gps <speed>`.

## Milestone 8 (as built)

- Package: `HeartRateMeasurement.parse` (BLE 0x2A37), `GPXBuilder`, `RestingHeartRateSignal`
  (median baseline, +7 bpm = elevated; feeds `RecoveryCheckIn.isPoor` only when readiness < 0.6),
  `ExternalWorkouts.loadEntries` (other apps' workouts → load, skipping ≥50% overlap with Kinetix
  logs), `RunSummary.heartRateSamples` (≤ 1 per 5 s). `KinetixSync/Strava.swift`: `StravaClient`
  (OAuth URL/callback parsing, token exchange via Edge Function, GPX upload + polling, duplicate
  detection, manual activities, refresh on expiry/401, disconnect on revoked refresh).
- App `Kinetix/Services/Integrations/`: `IntegrationSettings` (per-device, UserDefaults),
  `HealthService`, `HeartRateMonitor` (CoreBluetooth, lazy central so no early prompt),
  `StravaService` (tokens in Keychain), `ActivityExportService` (on finish + retry on launch for 7 days;
  only sessions finished after connecting; never simulated runs).
- Settings → Integrations: `IntegrationsViews.swift`. Strava OAuth uses SwiftUI
  `webAuthenticationSession` (ephemeral), redirect `kinetix://localhost/strava`.
- Edge Function: `supabase/functions/strava-token/index.ts` (secrets STRAVA_CLIENT_ID/SECRET, JWT off).
- Watch HR = HealthKit anchored query (only arrives while the Watch records a workout; a watchOS
  companion app would be the proper fix later). Strap HR wins when both are present.
- Not done: writing HR samples to Health (avoids duplicating Watch data); pause events in Health workouts.
- Owner docs: `docs/IPHONE.md` (install on device, free Apple ID OK), `docs/STRAVA.md`.


## Milestone 9 (as built)

- Onboarding finish step: required health & safety acknowledgement (`acceptedHealthNotice`),
  "Connect Apple Health" button. UI test taps `onboarding.healthNotice`.
- `Kinetix/Resources/PrivacyInfo.xcprivacy`; `PrivacyPolicyView` (Settings → About) mirrored in
  `docs/privacy-policy.md` (owner must add a contact email and publish it).
- Dashboard bell → `PlanUpdatesSheet`. Progress: recent runs, `KXEmptyState`.
- Strava: uses asset images `StravaConnectButton` / `StravaCompatible` if the owner adds them;
  "View on Strava" links (summary + progress).
- Version 1.0.0. App Store steps for the owner: `docs/APP_STORE.md`.
- Owner runs on device with "Debug executable" unticked (Xcode couldn't extract the iOS 26.6
  shared cache with Xcode 26.3).

## Feature round 2 (owner-approved plan, milestones 10–13)

Decisions: change-history screen only (option C); rules editable via JSON on GitHub (remote
rules later); Record button centre tab, nothing paywalled; run types Free/Easy/Recovery/Long/
Tempo/Intervals/Progression/Fartlek, single pace with optional range, templates saved + synced;
gym tracker with custom exercises, templates, pre-fill from last session; ask "Is this your
planned session?" (yes / extra / pick another); recorded sessions → load, Health, Strava;
appearance per phone; Health dashboard (steps, RHR, HRV, sleep, VO2max, active energy,
respiratory rate; 7/30-day trends) with HRV feeding recovery; dashboard reorder/hide synced.
After M13: owner's list of faults.

- **M10 ✅** `balance_rules.json` + `BalanceRules` (scheduling flags, load zones, recovery,
  rebalancing); `ChangeCause` on `Adjustment`; `SessionSnapshot`/`PlanChangeDiff`/`ChangeTrigger`;
  `PlanChangeModel` stores cause/before/after/triggers (synced); `PlanChangesView`;
  Settings → Appearance (`AppearanceChoice`, @AppStorage "appearance"); `docs/RULES.md`.
- **M11 ✅** Engine `Recording/CustomRun.swift`: `RecordRunType`, `PaceTarget` (single/range),
  `WorkoutStep`, `RunBlock` (repeats; note `WorkoutBlock` is the template library's type),
  `CustomRunWorkout` (structure/estimate/summary/starters). App: `RunTemplateModel` (synced
  "runTemplate"), Record tab (`Features/Record/`: `RecordView`, `RunSetupView`, `WorkoutBuilderView`,
  `StepEditorView`, `PacePicker`), `ActiveSession.custom/linkedPlannedId`, `RunWorkoutModel(custom:)`.
- **Progress rework ✅** (owner request before M12): Progress tab = Running | Strength | Overall
  (`ProgressScreen`, `RunningProgressView` + `WeeklyBarChart`, `RunDetailView` + `RunLineChart` +
  `EditSessionSheet`, `StrengthProgressView` + `StrengthSessionDetailView`). Engine
  `Running/RunAnalysis.swift`: best efforts (sliding window, interpolated), pace/HR series,
  `TrainingHistory` totals/weekly. `RunLogModel.runTypeRaw/recordTypeRaw` (synced);
  `RunService/StrengthService.update/delete`, `PlanService.reopen`. Simulated runs listed but
  excluded from totals/bests. Sample history runs now have routes + HR.
- **No-onboarding start ✅**: `RootView` always shows tabs (+ `LaunchSplashView`, launch colour
  `LaunchBackground`); onboarding opens from Plan tab `PlanIntroCard` (fullScreenCover, closes when a
  profile appears). `UnitPreference` (units before a plan), `HealthNotice` (accepted in plan set-up or
  via `HealthNoticeSheet` before the first Record run), `AppBootstrap.ensureDefaults` (coaching settings).
- **Lock screen, widgets, sharing ✅**: `KinetixWidgets` app-extension target (WidgetKit +
  ActivityKit) with `Shared/WorkoutActivity.swift` (attributes, `ToggleWorkoutPauseIntent`,
  `WidgetSnapshot`, `AppGroup`; `WIDGET_EXTENSION` flag in the extension). App:
  `WorkoutActivityController`, `ActiveWorkout`, `WidgetSnapshotService`; links `kinetix://tab/…`.
  App Group `group.com.georgeodwyer.kinetix` (owner enabled it on both App IDs). Sharing:
  `Features/Share/` (`ShareCardView` map/photo/sticker, `ShareService` render/map snapshot/
  Instagram Stories via `InstagramAppID` = `INSTAGRAM_APP_ID` xcconfig/secret, docs/SHARING.md),
  `RunAnalysis.privacyTrimmed`.
- **M12 ✅ Gym tracker**: engine `Recording/GymWorkout.swift` (`MuscleGroup`, `ExerciseSearch`,
  `GymTemplateItem`, `GymTemplate.summary`, `GymPrefill` set-by-set from last time + "Last time" text).
  `exercises.json` gained 41 `libraryOnly` exercises with a `muscle` (never picked for plans).
  App: `GymTemplateModel` ("gymTemplate"), `CustomExerciseModel` ("customExercise", id
  `custom-<uuid>`), `StrengthLogModel.isRecorded` (synced); `GymService` (library, previous sets,
  start/add/remove/items); `Features/Record/GymSetupView` (+ `gymStartFlow`: health notice +
  planned-session question), `GymTemplateEditorView`, `ExercisePickerView`. Recorded sets use
  progression key `<id>.free`, and `StrengthService.finish` skips plan progression for recorded
  logs (PRs, load, Health/Strava still apply). `ActiveSession.strengthLogId` opens/resumes them.
- **Route planner ✅** (owner: yes to road-following taps, loop generator, turn-by-turn + off-route
  voice, saved/synced + GPX import/export). Engine `Routes/PlannedRoute.swift`: `RouteCoordinate`,
  `RouteInstruction`, `PlannedRoute`, `RouteGeometry` (projection, simplify, turn detection),
  `LoopGenerator` (circle waypoints + road factor), `RouteGuide` (windowed progress so out-and-backs
  don't jump, off-route after 4 fixes > 40 m, "In 100 metres…" then "Turn left"), `GPXRoute`
  (parse trk/rte/wpt, write). `SimulatedRunner.path` makes simulated GPS follow the route.
  App: `RouteModel` (synced "route"), `RouteService` (MKDirections walking legs, cached; straight-line
  fallback; loops retried up to 3× to land within 10%; GPX file), `RoutePlannerView` (+ `GPXFile`
  Transferable, `UTType.gpx`), Record tab "My routes" + GPX import, `RunSetupView` route card,
  `ActiveSession.route`, `RunWorkoutModel.plannedRoute/routeStatus`, run screen route card + planned
  line on `RouteMap(planned:)`.
- **M13 ✅ Health dashboard + layout** (owner: metrics on the dashboard AND a Progress tab; HRV acts like
  resting HR, i.e. only with a so-so check-in; Health sleep suggests the check-in sleep score; Edit
  dashboard screen). Engine `Health/HealthMetrics.swift`: `HealthMetric` (7 metrics, units, format,
  explanation), `HealthDay`, `HealthTrend` (latest vs 30-day median "usual", 7/30-day averages),
  `HealthSeries.window`, `HRVSignal` (rules `hrvSuppressedPercent`/`hrvMinimumReadings`, optional in
  the JSON), `SleepScore`, `DashboardCard` + `DashboardLayout` (raw strings, forward-compatible).
  `RecoveryCheckIn.hrvSuppressed` / `hasBodyWarning`. App: `HealthService` reads daily stats
  (HKStatisticsCollectionQuery; sleep = asleep stages per wake day, longest source wins), `hrv`,
  `lastNightSleepHours`, `needsPermission` (asks again for newly added types), `loadSample()` for
  screenshot runs (`-seed-history`). Health readings are never stored or synced. UI:
  `Features/Health/HealthViews.swift` (`BodyCard`, `HealthTile`, `TrendBadge`, `HealthMetricDetailView`,
  `HealthChart`, `HealthProgressView`), Progress "Health" tab, `CheckInCard` HRV line + sleep
  suggestion, `EditDashboardView`; layout stored on `CoachingSettingsModel.dashboardLayoutData` (synced).
  HomeView is now in a NavigationStack (bar hidden) so tiles can push detail screens.

- **Strava, done properly + load chart period ✅** (owner: upload + import; NO server for now, so the
  client secret is a GitHub secret baked into TestFlight builds only while `SUPABASE_URL` is unset;
  runs auto-upload, gym sessions get an "Upload to Strava" button unless auto is on; load chart
  Week = last 7 days / Month = last 30 days). KinetixSync `Strava.swift`: `StravaConfig.direct`
  (form-encoded exchange to strava.com/oauth/token), scope `read,activity:read_all,activity:write`,
  `StravaTokens.scopes/canReadActivities`, `activities(after:page:perPage:)`, `StravaActivity`
  (+ `category`, `isFromKinetix`), `Polyline.decode`. App: `StravaService.importRecent` (90 days first
  time, then since last check − 1 day, every app open, ≥15 min apart) → runs become `RunLogModel` with
  `importSourceRaw = "strava"` (synced; "From Strava" tag; excluded from best efforts/pace chart and
  from Health/Strava export), others → `IntegrationSettings.stravaWorkouts` (28 days) merged with
  Health's via `ExternalWorkouts.merged` into `loadWorkouts`. `StravaImport.plan` dedupes (own uploads,
  known ids, ≥50% overlap with Kinetix sessions). `LoadReport.daily` is now 30 days; `DailyLoadChart`
  has a Week/Month picker (@AppStorage "dashboard.loadRange"). **Before App Store release: move the
  secret to Supabase (docs/STRAVA.md) and reset it on Strava.**

## Getting builds to the owner's phone (default)

The owner installs via **TestFlight**. After each milestone or fix that's green on CI, trigger
the `testflight.yml` workflow (workflow_dispatch, branch `claude/hybrid-running-strength-app-8rsowc`)
with `mcp__github__actions_run_trigger`, check it succeeds, and tell the owner the build will
appear in TestFlight in ~20–40 min. Build numbers = 100 + run number. Needs the four secrets in
docs/TESTFLIGHT.md (APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8).
