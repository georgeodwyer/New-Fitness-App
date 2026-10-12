# Setting up accounts and sync (Supabase)

Kinetix stores everything on the iPhone first. With an account, it also backs up to
Supabase and syncs between devices. This is a one-off setup in your web browser
(about 15 minutes). You don't need a Mac.

## 1. Create the Supabase project

1. Go to https://supabase.com and sign up (free).
2. **New project** → name `Kinetix` → choose a strong database password (save it in your
   password manager) → region near you (e.g. *West EU (London)*) → **Create new project**.
3. Wait a minute or two while it sets up.

## 2. Create the database table

1. In the left sidebar open **SQL Editor** → **New query**.
2. Open [`supabase/schema.sql`](../supabase/schema.sql) in this repository, copy **all** of it,
   paste it into the editor and press **Run**. You should see "Success. No rows returned".

This creates one table for your training data, with security rules so each person can
only ever read and change their own records, plus the function the app uses to delete
an account.

## 3. Email sign-in settings

1. **Authentication** → **Sign In / Providers** → make sure **Email** is enabled.
2. "Confirm email" can stay on (recommended): new users get a link to confirm before
   they can sign in. The app explains this when it happens.
3. **Authentication** → **URL Configuration** → set **Site URL** to a page you control
   later (e.g. your website). For now the default is fine.

## 4. Sign in with Apple (after joining the Apple Developer Program)

1. Make sure the App ID `com.georgeodwyer.kinetix` has **Sign In with Apple** ticked
   (see `docs/TESTFLIGHT.md`, step 2).
2. In Supabase: **Authentication** → **Sign In / Providers** → **Apple** → enable it.
3. Under **Client IDs**, enter `com.georgeodwyer.kinetix` and save. (The app signs in
   natively, so you don't need the "Secret Key" fields.)

## 5. Give the app its keys

1. In Supabase: **Project Settings** → **API** (or **Data API**). Copy:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - the **anon / public** key (a long string starting `eyJ…`, or `sb_publishable_…`)
   Don't use the `service_role` / secret key anywhere in the app.
2. Add them as GitHub secrets (Settings → Secrets and variables → Actions → New
   repository secret):

| Name | Value |
|---|---|
| `SUPABASE_URL` | the Project URL |
| `SUPABASE_ANON_KEY` | the anon / public key |

TestFlight builds pick these up automatically. For builds on your own Mac, put the same
values in `Config/Secrets.xcconfig` (this file is never committed):

```
SUPABASE_URL = https:/$()/abcdefgh.supabase.co
SUPABASE_ANON_KEY = eyJ...
```

(The odd `/$()/` is because `//` starts a comment in that file type.)

## How sync works

- Every item (a planned session, a run, a set, a check-in…) is one row in `records`, tagged
  with your user id and the time it was last edited.
- When online, the app uploads what changed on this iPhone and downloads what changed
  elsewhere. If the same item was edited on two devices, **the most recent edit wins**,
  and the database itself refuses older uploads, so a slow device can't overwrite newer data.
- Deleting your account in **Settings → Delete account and data** removes your login and
  every record in the cloud, then everything on the iPhone.
