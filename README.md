# Kinetix

Hybrid running + strength training for iPhone. See [docs/PLAN.md](docs/PLAN.md) for the
architecture and milestones, and [docs/HANDOVER.md](docs/HANDOVER.md) for working notes.

## Open the project in Xcode (no Terminal needed)

The Xcode project file is generated automatically and kept in the repository, so you only
need Xcode and GitHub Desktop.

1. **Xcode**: on an Intel Mac, install **Xcode 26** from
   https://developer.apple.com/download/all/ (sign in with your Apple ID, search "Xcode 26").
   Needs macOS 15.6 or later. Open it once to finish installing (include the iOS platform).
2. **GitHub Desktop**: download from https://desktop.github.com (works on Intel Macs),
   open it and sign in to GitHub.
3. **File → Clone Repository…** → find `georgeodwyer/New-Fitness-App` → Clone.
4. At the top, click **Current Branch** and choose `claude/hybrid-running-strength-app-8rsowc`.
5. **Repository → Show in Finder**, then double-click **`Kinetix.xcodeproj`**.
6. In Xcode, choose an iPhone simulator at the top and press **⌘R**.

To get updates: in GitHub Desktop press **Fetch origin**, then **Pull origin**. Xcode picks
up the changes (if it asks, choose "Revert" / reload from disk).

Accounts and sync need Supabase keys in `Config/Secrets.xcconfig` (see
[docs/SUPABASE.md](docs/SUPABASE.md)); without them the app works fully offline.

## Layout

- `Packages/TrainingEngine`: the training logic (`TrainingEngine`) and cloud sync
  (`KinetixSync`), pure Swift with unit tests.
- `Kinetix/`: the iOS app (SwiftUI + SwiftData).
- `project.yml`: the source of the Xcode project (generated with XcodeGen; CI does this).
- `Config/`: build settings; secrets go in `Config/Secrets.xcconfig`, which git ignores.
- `supabase/schema.sql`: database setup for accounts and sync.
- `Designs/`: reference screens from Stitch.
