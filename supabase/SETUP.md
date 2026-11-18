# RCZ - KANYAMA Supabase setup

## Create the project

1. Open [supabase.com](https://supabase.com) and create an account or sign in.
2. Select **New project**.
3. Name it `rcz-kanyama`.
4. Choose a strong database password and keep it somewhere safe.
5. Select the nearest region and create the project.
6. Wait until the project is ready.

## Run the database scripts

For a brand-new project:

1. Open the project dashboard.
2. Select **SQL Editor**.
3. Choose **New query**.
4. Copy everything from [`schema.sql`](./schema.sql) into the editor.
5. Select **Run**.
6. Run [`add_media_history_notice_reads.sql`](./add_media_history_notice_reads.sql)
   the same way.

For the existing live project, run only
[`add_media_history_notice_reads.sql`](./add_media_history_notice_reads.sql).
The original Media Team / congregation-history migration reported as applied,
but the live API returned `PGRST205` for `media_team_accounts`,
`church_history_entries` and `church_history_photos`. The corrective script is
idempotent: it creates missing objects, adds missing columns, and never drops a
table or deletes archive data. It also creates the private `church-history`
bucket, notice read receipts and two additive sermon columns.

`schema.sql` describes `church_notices.id` as `bigint`, but the live table uses
UUID ids. Notice receipts therefore store the id as text, and the RPCs validate
the notice instead of relying on a foreign key.

The base script creates the member list, sermon list, notices, Secretariat
access table, and the public `notice-photos` storage bucket. Notice photos are
uploaded with an expiry timestamp and the Secretariat dashboard removes expired
files when it is opened.

## Secretariat approval

After a Secretariat member registers in the app, an administrator must approve
that account in **Table Editor > secretariat_accounts** by setting `role` to
`SEC` or `VSEC` and `is_active` to `true`. The account's `user_id` is the
matching user ID from **Authentication > Users**.

The public notices page only reads published notices. Only active Secretariat
accounts can create, edit, delete notices, or upload/delete notice photos.

## Media Team approval

Media Team registration sets `requested_role = MEDIA` in the user's metadata.
The `create_media_team_account` trigger creates a row in
`media_team_accounts` with `is_active = false`. Authorisation always uses that
active row, never the person's name.

After registration, approve the account in **Table Editor >
media_team_accounts** by setting `is_active` to `true`. Until then, the app
shows a pending-approval message and signs the user out.

Approved Media Team members can manage the separate Kanyama Congregation
History archive: create, edit, delete, publish, unpublish and preview records,
upload a cover photograph and up to 20 ordered gallery photographs with
captions. The `church-history` bucket is private, so members see short-lived
signed URLs. Drafts and draft photographs are never visible to ordinary
members.

## Notice read receipts

Read state is stored immediately on each device with SharedPreferences, so the
unread badge works offline and survives restarts. A best-effort receipt is also
sent with the existing member `device_id`. The receipt is optional: if the RPC
is unavailable, the local badge still works and the app does not claim the
receipt was saved remotely.

## Secretariat registration trigger

The Secretariat access section now relies on a database trigger to create a
pending application row when a new Auth user registers with `requested_role`
of `SEC` or `VSEC`. Run `add_secretariat_registration.sql` after the admin
migration to enable this. Until then, Secretariat registrations will not
create an application record and login will report "No membership
application was found".

The project includes
[`functions/sync-youtube-sermons/index.ts`](./functions/sync-youtube-sermons/index.ts).
It resolves the public channel id, reads YouTube's Atom RSS feed for real
publication timestamps, and best-effort reads the channel streams page for live
and upcoming services. It upserts up to 25 videos into `public.sermons`.

Deploy it from the Supabase CLI:

```text
supabase functions deploy sync-youtube-sermons
```

The function uses Supabase's built-in `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` secrets automatically. After deployment, opening
the Sermons tab syncs the channel before loading the list, and the app refreshes
every ten minutes while it is open.

Until the updated function is deployed, existing rows keep their previous
`published_at` values (currently null), so the repaired ordering is not visible
yet. The app still sorts null dates safely and never treats database creation
time as a real YouTube publication date when dated rows exist.

## Values needed for the app

Open **Project Settings > API** and copy only:

- **Project URL**
- **Publishable key** (or the legacy `anon` key if that is what the dashboard shows)

Never share the `service_role` key. Do not put it in the Flutter app.
