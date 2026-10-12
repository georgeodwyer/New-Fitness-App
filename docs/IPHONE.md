# Running Kinetix on your iPhone

You can install the app on your own iPhone straight from Xcode with a USB cable. It works
with a **free Apple ID** today; joining the Apple Developer Program (US$99 a year, or the local equivalent) removes
the limits below and is needed for TestFlight and the App Store.

| | Free Apple ID | Apple Developer Program |
|---|---|---|
| Install from Xcode | ✅ | ✅ |
| App keeps working | 7 days, then press Run again | 1 year |
| Sign in with Apple | ❌ (email sign-in works) | ✅ |
| TestFlight / App Store | ❌ | ✅ |

You need: the Mac with Xcode 26, your iPhone (iOS 17 or later) and its cable.

## One-time setup

1. **Add your Apple ID to Xcode.** Xcode → Settings… → Accounts → **+** → Apple ID → sign in.
   You'll see a team called "*Your Name* (Personal Team)", or your paid team once you've joined.
2. **Plug in the iPhone and unlock it.** Tap **Trust** when it asks "Trust This Computer?"
   and enter your passcode.
3. **Turn on Developer Mode on the iPhone.** Settings → Privacy & Security → scroll right
   down → **Developer Mode** → on → **Restart**. After it restarts, tap **Turn On**.
   (The option only appears after the iPhone has been connected to Xcode, so do step 2 first.)
4. **Choose your team in Xcode.**
   - Open `Kinetix.xcodeproj`. In the left sidebar click the blue **Kinetix** project icon
     at the very top.
   - Under TARGETS select **Kinetix**, then open the **Signing & Capabilities** tab.
   - Leave "Automatically manage signing" ticked and pick your **Team**.
   - **Free Apple ID only:** Xcode shows an error about "Sign in with Apple". Scroll down to
     the **Sign in with Apple** box on the same tab and click the **🗑 / ×** next to it.
     (If it also complains about HealthKit, remove that box the same way: Apple Health then
     stays off.)
   - If it says the bundle identifier "is not available", change **Bundle Identifier** to
     something unique, e.g. `com.yourname.kinetix`.
5. **Pick the iPhone as the destination.** In the bar at the top of Xcode, click the device
   name and choose your iPhone (under "iOS Device"). The first time, Xcode spends a few
   minutes "Preparing iPhone": wait for it to finish.

## Run it

1. Press **⌘R** (or the ▶ button). Xcode builds and installs Kinetix on the iPhone.
2. **Free Apple ID, first time only:** the iPhone says "Untrusted Developer". On the iPhone
   go to Settings → General → **VPN & Device Management** → your Apple ID → **Trust**. Then
   tap the Kinetix icon.
3. Kinetix stays on the phone after you unplug it. With a free Apple ID it stops opening
   after 7 days: plug in and press ⌘R again (your data is kept).

**No cable after the first time:** Xcode → Window → Devices and Simulators → select your
iPhone → tick **Connect via network**. While the Mac and iPhone are on the same Wi-Fi, the
iPhone appears in the destination list wirelessly.

## What to try on the phone (things the simulator can't do)

- **A real GPS run:** turn *off* Settings → Testing → Simulated GPS, go outside and start a
  run. Allow location "While Using", then lock the phone: pace cues and splits keep coming
  through your headphones.
- **Apple Health:** Settings → Integrations → Apple Health → Connect. Finish a run or lift
  and it appears in the Health app (Browse → Activity → Workouts). Resting heart rate
  shows on the dashboard check-in when Health has a week of readings (from an Apple Watch).
- **Heart rate strap:** put the strap on, then Settings → Integrations → Heart rate strap →
  Find a strap → Pair. Live heart rate appears on the run screen.
- **Apple Watch heart rate:** start an Outdoor Run in the Watch's Workout app at the same
  time as the Kinetix run; heart rate flows to the run screen through Apple Health.
- **Strava:** needs the setup in `docs/STRAVA.md` first.

## Getting updates

When you pull new changes in GitHub Desktop, it may say you have changes to
`Kinetix.xcodeproj` or `Kinetix.entitlements` (from picking your team in step 4). Click
**Repository → Discard All Changes**, pull, then pick your team again (step 4).

To avoid redoing step 4: once you've joined the Developer Program, find your **Team ID**
at <https://developer.apple.com/account> → Membership details, and send it to Claude. It's
not secret, so it can be built into the project and you won't have to choose a team again.

## If something goes wrong

| Message | Fix |
|---|---|
| "iPhone is not available… Developer Mode disabled" | Step 3. |
| "The iOS version on this iPhone is not supported" | Update Xcode, or install the "iOS platform" Xcode offers. |
| "Failed to register bundle identifier" | Change the Bundle Identifier (step 4). |
| "Could not launch… security" / "Untrusted Developer" | Run step 2 again. |
| "Maximum number of apps for free development profiles" | Delete another app you installed from Xcode. |
