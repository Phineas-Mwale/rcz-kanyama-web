
-- RCZ Kanyama — Secretariat registration application support
--
-- Creates a pending Secretariat application when a new Auth user
-- registers with requested_role SEC or VSEC.
--
-- Prerequisite: add_admin_dashboard.sql has already been executed.
-- Does not modify the Media Team trigger.
--
-- This is a one-time migration. Check existing objects before execution.

begin;

-- Fail safely if either object already exists.
do $$
begin
  if to_regprocedure('public.create_secretariat_account()') is not null then
    raise exception
      'public.create_secretariat_account() already exists. Inspect it before proceeding.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where t.tgname = 'on_auth_user_created_secretariat'
      and n.nspname = 'auth'
      and c.relname = 'users'
      and not t.tgisinternal
  ) then
    raise exception
      'Secretariat Auth trigger already exists. Inspect it before proceeding.';
  end if;
end;
$$;

create function public.create_secretariat_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  req_role text;
begin
  req_role := upper(
    coalesce(new.raw_user_meta_data ->> 'requested_role', '')
  );

  if req_role in ('SEC', 'VSEC') then
    insert into public.secretariat_accounts (
      user_id,
      display_name,
      role,
      email,
      phone,
      status,
      is_active
    )
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
        split_part(coalesce(new.email, 'Secretariat member'), '@', 1)
      ),
      req_role,
      new.email,
      nullif(trim(new.raw_user_meta_data ->> 'contact_phone'), ''),
      'pending',
      false
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created_secretariat
after insert on auth.users
for each row
execute function public.create_secretariat_account();

notify pgrst, 'reload schema';

commit;
