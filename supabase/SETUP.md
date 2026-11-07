# RCZ - KANYAMA Supabase setup

## Create the project

1. Open [supabase.com](https://supabase.com) and create an account or sign in.
2. Select **New project**.
3. Name it `rcz-kanyama`.
4. Choose a strong database password and keep it somewhere safe.
5. Select the nearest region and create the project.
6. Wait until the project is ready.

## Run the database script

1. Open the project dashboard.
2. Select **SQL Editor**.
3. Choose **New query**.
4. Copy everything from [`schema.sql`](./schema.sql) into the editor.
5. Select **Run**.

This creates the member list, sermon list, notices, Secretariat access table, and the
public `notice-photos` storage bucket. Notice photos are uploaded with an expiry
timestamp and the Secretariat dashboard removes expired files when it is opened.

After a Secretariat member registers in the app, an administrator must approve
that account in **Table Editor > secretariat_accounts** by setting `role` to
`SEC` or `VSEC` and `is_active` to `true`. The account's `user_id` is the
matching user ID from **Authentication > Users**.

The public notices page only reads published notices. Only active Secretariat
accounts can create, edit, delete notices, or upload/delete notice photos.

## Automatic YouTube sermon syncing

The project includes [`functions/sync-youtube-sermons/index.ts`](./functions/sync-youtube-sermons/index.ts).
It reads the public RCZ Kanyama channel videos page and upserts the latest ten videos into
`public.sermons`. The app invokes this function whenever the Sermons page
refreshes and every ten minutes while the app is open.

Deploy it from the Supabase CLI:

```text
supabase functions deploy sync-youtube-sermons
```

The function uses Supabase's built-in `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` secrets automatically. After deployment, opening
the Sermons tab will immediately sync the channel before loading the list.

## Values needed for the app

Open **Project Settings > API** and copy only:

- **Project URL**
- **Publishable key** (or the legacy `anon` key if that is what the dashboard shows)

Never share the `service_role` key. Do not put it in the Flutter app.

The next app step is wiring these two public values into a local configuration file, then adding the registration upload and sermon list. Supabase login details should stay in your browser; only the public URL and publishable key are needed for development.
