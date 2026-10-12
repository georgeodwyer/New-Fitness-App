# Submitting Kinetix to the App Store

What's already built in, and what you need to do in App Store Connect. Do this once the
app has been on TestFlight for a while and you're happy with it.

## Already done in the app

| Requirement | Where |
|---|---|
| Privacy manifest (no tracking; data declared) | `Kinetix/Resources/PrivacyInfo.xcprivacy` |
| Privacy policy inside the app | Settings → About → Privacy policy |
| Account deletion inside the app (guideline 5.1.1(v)) | Settings → Delete account and data |
| Sign in with Apple offered alongside email (4.8) | Account screens |
| Health & safety notice, acknowledged before the first plan (1.4.1) | Onboarding → last step; Settings → Health & safety |
| Clear permission messages (location, Health, Bluetooth) | `project.yml` → Info.plist |
| Works without an account and offline | – |
| Export compliance (standard encryption only) | `ITSAppUsesNonExemptEncryption = NO` |
| Data export | Settings → Export my data |

## Your checklist

### 1. Publish the privacy policy
App Store Connect needs a public web link. Easiest options:
- **Google Docs:** paste in `docs/privacy-policy.md`, then File → Share → Publish to web and copy the link.
- **Notion:** a public page works too.

Before publishing, replace the "[add your support email here]" line with a support email
address. You'll also need a **Support URL** (any web page with a way to contact you; the
same document is fine).

### 2. Create the app in App Store Connect
<https://appstoreconnect.apple.com> → Apps → **+** → New App (if TestFlight hasn't already created it).
- Name **Kinetix** (if it's taken, try "Kinetix: Run & Lift"), bundle ID `com.georgeodwyer.kinetix`, SKU anything.
- Category: **Health & Fitness**.
- Age rating questionnaire: answer "None" throughout → 4+. (Kinetix gives no medical treatment advice.)

### 3. App Privacy ("nutrition label")
App Store Connect → your app → App Privacy → Get started. Answer **Yes, we collect data**, then tick:

| Data type | Linked to user | Tracking | Purpose |
|---|---|---|---|
| Contact info → Email address | Yes | No | App functionality |
| Identifiers → User ID | Yes | No | App functionality |
| Health & fitness → Health | Yes | No | App functionality |
| Health & fitness → Fitness | Yes | No | App functionality |
| Location → Precise location | Yes | No | App functionality |

(These match the privacy manifest. They're "collected" only because accounts back data up
to Supabase; without an account nothing leaves the phone.)

### 4. Screenshots
Apple needs at least one set for the **6.9-inch iPhone** (1320 × 2868). The `screenshots`
download from each GitHub CI run has them, taken on the simulator. Pick 3–10, e.g.
dashboard, plan, a live run, strength workout, progress. They must not show the "Testing"
or "Developer" settings.

### 5. Description and review notes
- **Promotional text / description:** write in your own words. Mention running + lifting
  balanced together, audio pace coaching, progression, Apple Health and Strava.
- **Keywords:** e.g. `hybrid,running,strength,training plan,marathon,gym,lifting,coach,pace`.
- **Review notes** (important, so the reviewer can test without going outside):
  > No account is needed. To test a run without walking outside: Settings → Testing →
  > turn on "Simulated GPS for runs", then start any run from the Today tab. Apple Health,
  > Bluetooth heart rate straps and Strava are optional (Settings → Integrations).
  > Kinetix gives general training guidance and is not a medical device.
- Turn **off** "Sign-in required".

### 6. Strava (if Strava is included in the release)
- Strava requires their **official "Connect with Strava" button** and the **"Compatible with
  Strava"** logo. Download both from <https://developers.strava.com/guidelines/> and add
  them to Xcode's asset catalogue (`Kinetix/Resources/Assets.xcassets`) named exactly
  `StravaConnectButton` and `StravaCompatible` (drag the PNGs in, then rename). The app
  uses them automatically.
- Request Strava's app review (strava.com/settings/api) so more than one athlete can
  connect. Allow a few weeks.

### 7. Submit
Pick the TestFlight build under "Build", answer the export compliance question (it's
pre-answered: no non-exempt encryption), and **Add for Review**. First reviews usually
take 1–3 days. If Apple rejects something, paste their message to Claude.

## Version numbers
The version is set in `project.yml` (`MARKETING_VERSION`, now 1.0.0). Bump it for each App
Store release (1.0.1 for fixes, 1.1.0 for features). TestFlight build numbers increase
automatically.
