# Getting Kinetix onto your iPhone with TestFlight

TestFlight is Apple's app for installing test versions. Once this is set up, you
press one button on GitHub (or ask Claude to) and the latest Kinetix arrives on
your phone 15–30 minutes later. You do this setup once, in a web browser — no Mac needed.

## 1. Join the Apple Developer Program (US$99/year)

1. Go to https://developer.apple.com/programs/enroll/ and sign in with your Apple ID.
2. Enrol as an **Individual** (simplest; an organisation needs a D-U-N-S number).
3. Approval usually takes from a few hours to two days. You'll get an email.

## 2. Register the app's ID

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click **+** → **App IDs** → **App** → Continue.
3. Description: `Kinetix`. Bundle ID: choose **Explicit** and enter `com.georgeodwyer.kinetix`
4. Under Capabilities tick **HealthKit** and **Sign In with Apple** (needed later). Continue → Register.

## 3. Create the app in App Store Connect

1. Go to https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
2. Platform: iOS. Name: `Kinetix` (if the name is taken, try e.g. `Kinetix Hybrid Training`;
   the name on your home screen stays "Kinetix"). Language: English (UK).
   Bundle ID: pick `com.georgeodwyer.kinetix`. SKU: `kinetix-001`. Access: Full Access.
3. Click **Create**.

## 4. Create an API key (lets GitHub upload builds for you)

1. In App Store Connect go to **Users and Access** → **Integrations** → **App Store Connect API**
   (under "Team Keys"). If asked, click **Request Access** first.
2. Click **+** (Generate API Key). Name: `GitHub TestFlight`. Access: **Admin**
   (Admin is needed for automatic code signing). Click **Generate**.
3. Note the **Issuer ID** (shown above the list of keys) and the **Key ID** of your new key.
4. Click **Download API Key**. You can only download it once — keep the `.p8` file safe.

## 5. Find your Team ID

Go to https://developer.apple.com/account → **Membership details** → **Team ID**
(10 characters, e.g. `A1B2C3D4E5`).

## 6. Add four secrets to GitHub

Secrets are stored encrypted by GitHub; they never appear in the code and Claude can't read them.

1. Open https://github.com/georgeodwyer/New-Fitness-App/settings/secrets/actions
2. Click **New repository secret** for each of these:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Your Team ID from step 5 |
| `ASC_KEY_ID` | The Key ID from step 4 |
| `ASC_ISSUER_ID` | The Issuer ID from step 4 |
| `ASC_KEY_P8` | Open the downloaded `.p8` file in TextEdit and paste **everything**, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

## 7. Upload a build

1. Open https://github.com/georgeodwyer/New-Fitness-App/actions/workflows/testflight.yml
2. Click **Run workflow** → choose the branch `claude/hybrid-running-strength-app-8rsowc` → **Run workflow**.
3. After it finishes (about 10 minutes) Apple processes the build for another 5–20 minutes.
   You'll get an email when it's ready.

## 8. Install on your iPhone

1. In App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** to create a group
   (e.g. "Me"), and add yourself as a tester.
2. Install the **TestFlight** app from the App Store on your iPhone and sign in with the same Apple ID.
3. Kinetix appears in TestFlight → **Install**. New builds show up there automatically.

The first build may ask about "export compliance" — the app already declares it uses no
special encryption, so this should be skipped automatically.

If the workflow fails, tell Claude — the logs are attached to the run and show what to fix.
