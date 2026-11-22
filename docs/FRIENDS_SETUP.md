# Friends: setting up

Friends in Kinetix (usernames, invites, the weekly leaderboard, head-to-head, challenges and
friends' sessions) run on the same Supabase project as accounts and sync. There's one step.

## 1. Add the friends tables (once)

1. Open your Supabase project → **SQL Editor** → **New query**.
2. Paste the whole of `supabase/friends.sql` and press **Run**.

It's safe to run again (after an update, for example). Nothing else needs setting up: no keys,
no new services.

## How it works

- **Usernames.** Friends features start when someone chooses a username (Activity →
  Achievements → Friends). Until then nothing is shared.
- **Adding friends.** By username search, by 8-character friend code, or with an invite link /
  QR code (`kinetix://friend/CODE`), which opens Kinetix straight to the person to add.
  The other person accepts the request.
- **What friends see.** Sessions from the last 60 days with maps (the first and last 200 m of
  every run are removed on the iPhone before upload, including anywhere the run passes back
  near the start), weekly points and challenge progress. Never heart rate or Health data.
  Each session can be set to **Only me** (the lock/people button on the session), and
  **Friends see my sessions** can be turned off.
- **Points.** Worked out on the iPhone (planned sessions +20, full week +50, +5 per week in a
  row up to 50, 1 per 10 load up to 60 a day) and uploaded after each sync.
- **Block and report.** Blocking unfriends and hides both people from each other's search,
  feed, leaderboard and challenges. Reports land in the `reports` table (Table Editor →
  reports) for you to review.
- **Deleting an account** deletes all of their friends data.

## Security

Every table has row level security. People can only read and write their own rows directly;
everything about other people goes through database functions that check you're friends and
that nobody is blocked. Checked on a test database with three users before release.

## Not included yet

- Push notifications for friend requests and challenge invites (they show next time the app
  opens the Friends screen).
- Invite links are `kinetix://` links: they open Kinetix when it's installed. A web link that
  sends people without the app to the App Store needs a website domain (later).
