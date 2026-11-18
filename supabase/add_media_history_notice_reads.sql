-- RCZ Kanyama — corrective migration
--
-- The original Media Team / congregation-history migration reports as missing
-- in the live Supabase project (PostgREST returns PGRST205 for
-- media_team_accounts, church_history_entries and church_history_photos).
-- This script is intentionally idempotent: it creates only what is absent,
-- adds only missing columns, and never drops a table or deletes data.
--
-- Run this in Supabase Dashboard > SQL Editor, then reload the API schema.
-- It also adds the notice_reads table/RPCs and two safe sermon columns.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Media Team accounts
-- ---------------------------------------------------------------------------
create table if not exists public.media_team_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  email text,
  phone text,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.media_team_accounts
  add column if not exists display_name text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists is_active boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- New Media Team registrations. Secretariat registrations are untouched.
create or replace function public.create_media_team_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.raw_user_meta_data ->> 'requested_role', '')) = 'media' then
    insert into public.media_team_accounts (
      user_id,
      display_name,
      email,
      phone
    )
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
        split_part(coalesce(new.email, 'Media Team member'), '@', 1)
      ),
      new.email,
      nullif(trim(new.raw_user_meta_data ->> 'contact_phone'), '')
    )
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_media_team on auth.users;
create trigger on_auth_user_created_media_team
after insert on auth.users
for each row execute function public.create_media_team_account();

-- ---------------------------------------------------------------------------
-- 2. Congregation history
-- ---------------------------------------------------------------------------
create table if not exists public.church_history_entries (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'Milestones',
  person_name text,
  position text,
  start_year integer,
  end_year integer,
  biography text,
  cover_photo_path text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  published_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.church_history_entries
  add column if not exists title text,
  add column if not exists category text not null default 'Milestones',
  add column if not exists person_name text,
  add column if not exists position text,
  add column if not exists start_year integer,
  add column if not exists end_year integer,
  add column if not exists biography text,
  add column if not exists cover_photo_path text,
  add column if not exists display_order integer not null default 0,
  add column if not exists is_published boolean not null default false,
  add column if not exists published_at timestamptz,
  add column if not exists created_by uuid references auth.users (id) on delete set null,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.church_history_photos (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.church_history_entries (id) on delete cascade,
  storage_path text not null,
  caption text,
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.church_history_photos
  add column if not exists entry_id uuid references public.church_history_entries (id) on delete cascade,
  add column if not exists storage_path text,
  add column if not exists caption text,
  add column if not exists display_order integer not null default 0,
  add column if not exists created_at timestamptz not null default now();

create index if not exists church_history_entries_published_idx
  on public.church_history_entries (is_published, display_order, start_year);
create index if not exists church_history_photos_entry_idx
  on public.church_history_photos (entry_id, display_order);

create or replace function public.touch_church_history_entry()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists church_history_entries_touch on public.church_history_entries;
create trigger church_history_entries_touch
before update on public.church_history_entries
for each row execute function public.touch_church_history_entry();

-- Single authorisation helper used by table and storage policies.
create or replace function public.is_active_media_team()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.media_team_accounts
    where user_id = auth.uid() and is_active = true
  );
$$;

-- Compatibility alias kept for any policy or client created against the earlier
-- migration, which used this name. Both names now resolve identically.
create or replace function public.is_active_media_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_media_team();
$$;

alter table public.media_team_accounts enable row level security;
alter table public.church_history_entries enable row level security;
alter table public.church_history_photos enable row level security;

drop policy if exists "Media Team may read their account" on public.media_team_accounts;
create policy "Media Team may read their account"
on public.media_team_accounts
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Published history is public" on public.church_history_entries;
create policy "Published history is public"
on public.church_history_entries
for select
to anon, authenticated
using (is_published = true);

drop policy if exists "Media Team may read every history entry" on public.church_history_entries;
create policy "Media Team may read every history entry"
on public.church_history_entries
for select
to authenticated
using (public.is_active_media_team());

drop policy if exists "Media Team may create history entries" on public.church_history_entries;
create policy "Media Team may create history entries"
on public.church_history_entries
for insert
to authenticated
with check (public.is_active_media_team());

drop policy if exists "Media Team may update history entries" on public.church_history_entries;
create policy "Media Team may update history entries"
on public.church_history_entries
for update
to authenticated
using (public.is_active_media_team())
with check (public.is_active_media_team());

drop policy if exists "Media Team may delete history entries" on public.church_history_entries;
create policy "Media Team may delete history entries"
on public.church_history_entries
for delete
to authenticated
using (public.is_active_media_team());

drop policy if exists "Photos of published history are public" on public.church_history_photos;
create policy "Photos of published history are public"
on public.church_history_photos
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.church_history_entries e
    where e.id = entry_id and e.is_published = true
  )
);

drop policy if exists "Media Team may read every history photo" on public.church_history_photos;
create policy "Media Team may read every history photo"
on public.church_history_photos
for select
to authenticated
using (public.is_active_media_team());

drop policy if exists "Media Team may create history photos" on public.church_history_photos;
create policy "Media Team may create history photos"
on public.church_history_photos
for insert
to authenticated
with check (public.is_active_media_team());

drop policy if exists "Media Team may update history photos" on public.church_history_photos;
create policy "Media Team may update history photos"
on public.church_history_photos
for update
to authenticated
using (public.is_active_media_team())
with check (public.is_active_media_team());

drop policy if exists "Media Team may delete history photos" on public.church_history_photos;
create policy "Media Team may delete history photos"
on public.church_history_photos
for delete
to authenticated
using (public.is_active_media_team());

-- ---------------------------------------------------------------------------
-- 3. Private church-history bucket and storage policies
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('church-history', 'church-history', false)
on conflict (id) do nothing;

-- The archive is served through short-lived signed URLs so draft images are
-- never exposed by a public bucket URL.
update storage.buckets set public = false where id = 'church-history';

drop policy if exists "Published history photos may be read" on storage.objects;
create policy "Published history photos may be read"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'church-history'
  and (
    public.is_active_media_team()
    or exists (
      select 1
      from public.church_history_entries e
      where e.cover_photo_path = storage.objects.name
        and e.is_published = true
    )
    or exists (
      select 1
      from public.church_history_photos p
      join public.church_history_entries e on e.id = p.entry_id
      where p.storage_path = storage.objects.name
        and e.is_published = true
    )
  )
);

drop policy if exists "Media Team may upload history photos" on storage.objects;
create policy "Media Team may upload history photos"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'church-history'
  and public.is_active_media_team()
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Media Team may replace history photos" on storage.objects;
create policy "Media Team may replace history photos"
on storage.objects
for update
to authenticated
using (bucket_id = 'church-history' and public.is_active_media_team())
with check (bucket_id = 'church-history' and public.is_active_media_team());

drop policy if exists "Media Team may delete history photos" on storage.objects;
create policy "Media Team may delete history photos"
on storage.objects
for delete
to authenticated
using (bucket_id = 'church-history' and public.is_active_media_team());

-- ---------------------------------------------------------------------------
-- 4. Notice read receipts (device identity already used by members)
-- ---------------------------------------------------------------------------
-- The live church_notices.id is a UUID, while the checked-in schema.sql still
-- documents bigint. Receipts therefore store the id as text so this script
-- works with either shape. The RPCs validate that the notice exists and is
-- published, and a cleanup trigger replaces the foreign key's cascade.
create table if not exists public.notice_reads (
  device_id text not null,
  notice_id text not null,
  read_at timestamptz not null default now(),
  primary key (device_id, notice_id)
);

-- Repair an earlier bigint version of this table without losing receipts. The
-- live church_notices table uses UUID ids, so text is the compatible shape.
do $$
declare
  constraint_name text;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notice_reads'
      and column_name = 'notice_id'
      and data_type = 'bigint'
  ) then
    for constraint_name in
      select con.conname
      from pg_constraint con
      where con.conrelid = 'public.notice_reads'::regclass
        and con.contype = 'f'
        and con.confrelid = 'public.church_notices'::regclass
    loop
      execute format(
        'alter table public.notice_reads drop constraint %I',
        constraint_name
      );
    end loop;
    alter table public.notice_reads
      alter column notice_id type text using notice_id::text;
  end if;
end;
$$;

create index if not exists notice_reads_device_idx
  on public.notice_reads (device_id);

alter table public.notice_reads enable row level security;
-- Deliberately no direct table policies. Access is through the RPCs below so
-- a reader can only use an already registered device id.

create or replace function public.clear_notice_reads()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.notice_reads where notice_id = old.id::text;
  return old;
end;
$$;

drop trigger if exists church_notices_clear_reads on public.church_notices;
create trigger church_notices_clear_reads
after delete on public.church_notices
for each row execute function public.clear_notice_reads();

create or replace function public.mark_notice_read(
  p_device_id text,
  p_notice_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.members where device_id = p_device_id
  ) then
    raise exception 'Unknown member device';
  end if;
  if not exists (
    select 1 from public.church_notices
    where id::text = p_notice_id and is_published = true
  ) then
    raise exception 'Notice is not available';
  end if;
  insert into public.notice_reads (device_id, notice_id)
  values (p_device_id, p_notice_id)
  on conflict (device_id, notice_id) do nothing;
end;
$$;

create or replace function public.get_notice_reads(p_device_id text)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.members where device_id = p_device_id
  ) then
    return;
  end if;
  return query
    select notice_id from public.notice_reads where device_id = p_device_id;
end;
$$;

revoke all on function public.mark_notice_read(text, text) from public;
revoke all on function public.get_notice_reads(text) from public;
grant execute on function public.mark_notice_read(text, text) to anon, authenticated;
grant execute on function public.get_notice_reads(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Sermon live/upcoming support (safe additive columns)
-- ---------------------------------------------------------------------------
alter table public.sermons
  add column if not exists is_live boolean not null default false,
  add column if not exists scheduled_start timestamptz;

create index if not exists sermons_published_idx
  on public.sermons (published_at desc nulls last);
create index if not exists sermons_live_idx
  on public.sermons (is_live, scheduled_start);

-- Ask PostgREST to pick up the new tables immediately.
notify pgrst, 'reload schema';
