# Kinetix

Hybrid running + strength training for iPhone. See [docs/PLAN.md](docs/PLAN.md)
for the architecture and milestones.

## First-time setup (on your Mac)

1. Install **Xcode** from the Mac App Store and open it once to finish installing components.
2. Install **Homebrew** (https://brew.sh), then XcodeGen:
   ```sh
   brew install xcodegen
   ```
3. Get the code and generate the Xcode project:
   ```sh
   git clone https://github.com/georgeodwyer/New-Fitness-App.git
   cd New-Fitness-App
   git checkout claude/hybrid-running-strength-app-8rsowc
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   xcodegen
   open Kinetix.xcodeproj
   ```
4. In Xcode pick an iPhone simulator at the top and press **⌘R** to run, or **⌘U** to run the tests.

Re-run `xcodegen` whenever you pull changes that add or remove files.

## Layout

- `Packages/TrainingEngine` — the training logic (pure Swift, unit-tested). Run its tests with
  `swift test --package-path Packages/TrainingEngine`.
- `Kinetix/` — the iOS app (SwiftUI + SwiftData).
- `Config/` — build settings; secrets go in `Config/Secrets.xcconfig`, which git ignores.
- `Designs/` — reference screens from Stitch.
