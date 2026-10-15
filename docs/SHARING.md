# Sharing runs and workouts

Every run and strength session has a **Share** button (Progress → open a session → share
icon, or "Share run" straight after a run). Pick a style, then:

- **Share…**: the normal iPhone share sheet: Instagram (post or story), WhatsApp,
  Messages, X, Facebook, Mail and more. Works with no setup.
- **Save**: saves the image to Photos.
- **Stories**: opens Instagram's story editor with the transparent stats sticker placed on
  top, ready to move and resize (like Strava). Needs the one-off setup below; until then
  the button is hidden.

Styles: **Map** (route map + stats), **Photo** (your photo with the stats over it) and
**Sticker** (transparent, for laying over your own photo). "Hide start and finish" (on by
default) leaves the first and last 200 m off any map or route so it doesn't show where you
live.

## Setting up the Instagram Stories button (about 10 minutes, in a browser)

Instagram only accepts direct Stories shares from apps with a Meta (Facebook) App ID. It's
free and isn't secret.

1. Go to <https://developers.facebook.com>, log in with your Facebook account and accept the
   developer terms if asked.
2. **My Apps → Create app**. Name it "Kinetix", add your email. When asked for a use case
   choose **Other**, then app type **Consumer** (or "None" if offered). Create it.
3. On the app's dashboard (or **App settings → Basic**) copy the **App ID** (a long number).
4. Add it to GitHub so TestFlight builds include it: repository → Settings → Secrets and
   variables → Actions → **New repository secret** → name `INSTAGRAM_APP_ID`, value the App ID.
   (For builds from Xcode, also add `INSTAGRAM_APP_ID = <number>` to `Config/Secrets.xcconfig`.)
5. Tell Claude: the next TestFlight build will show the **Stories** button.

You don't need to submit the Meta app for review for Stories sharing.
