# Handover notes (for a new Claude Code session)

Read this, then `docs/PLAN.md`, before doing anything. Work on branch
`claude/hybrid-running-strength-app-8rsowc`; commit and push after each logical step.

## Status

Milestones 1–7 are done and green on CI. **Next: Milestone 8** (HealthKit, Bluetooth HR,
Strava), then Milestone 9 (polish, accessibility, App Store requirements).

| # | Milestone | State |
|---|---|---|
| 1 | Setup, design system, data model, navigation | ✅ |
| 2 | Onboarding + plan generation engine | ✅ |
| 3 | Strength trainer, logging, double progression, PRs | ✅ |
| 4 | Running trainer, background GPS, audio pace cues, simulated GPS | ✅ |
| 5 | Dashboard, sRPE load / ACWR, skip/swap/rebalancing | ✅ |
| 6 | Settings (coaching, training profile, units, export, delete) | ✅ |
| 7 | Supabase accounts + sync (REST, LWW, RLS) | ✅ code done; owner still has to create the Supabase project (docs/SUPABASE.md) |
| 8 | HealthKit (read HR, resting HR, workouts; write runs + lifts), live HR from Apple Watch via HealthKit and BLE chest straps (Heart Rate service 0x180D), Strava OAuth + auto-upload of runs | ⏭ next |
| 9 | Polish: empty states, errors, Dynamic Type/VoiceOver pass, privacy manifest, permission strings, health disclaimer in onboarding | |

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
  - `ios` job (macos-latest): XcodeGen → build-for-testing → app unit tests → UI screenshot
    walk-through (`KinetixUITests/ScreenshotTests.swift`) → uploads `screenshots` artifact
    (PNGs + `walkthrough.mp4`). ~15–18 min.
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

## Milestone 8 notes (planned approach)

- HealthKit: add entitlement + capability in `Kinetix.entitlements`/project.yml; usage strings
  already in Info.plist. Request read (heartRate, restingHeartRate, workouts) and share
  (workouts, distanceWalkingRunning, activeEnergyBurned, workout routes) at end of onboarding
  and in Settings → Integrations. Save finished runs (HKWorkoutBuilder + HKWorkoutRouteBuilder)
  and strength sessions; store `healthKitWorkoutId` on logs. Use resting HR in recovery.
- Live HR during runs: `RunEngine.addHeartRate` already exists. Sources: HealthKit anchored
  query for heart rate (Apple Watch) and CoreBluetooth Heart Rate Measurement (0x2A37, flags
  bit 0 → UInt8/UInt16). Put the BLE byte parsing in the package so it's unit-tested.
- Strava: owner registers an API app (docs needed). OAuth via ASWebAuthenticationSession;
  token exchange needs the client secret — do it through a Supabase Edge Function (don't ship
  the secret in the app). Upload a GPX/TCX built from the run route (builder in the package,
  tested), store `stravaActivityId`.
- Keep simulator/CI working without HealthKit/Bluetooth/Strava (feature-detect, mock in tests).
