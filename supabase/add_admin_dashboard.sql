
-- ============================================================================
-- RCZ KANYAMA: OWNER-ONLY ADMIN DASHBOARD
-- Migration: add_admin_dashboard.sql
--
-- Adds:
--   - Secretariat account contact details and status tracking
--   - Media Team status tracking
--   - Owner identity verification
--   - Owner-only account listing and statistics RPCs
--   - Owner-only account approval, rejection, deactivation and reactivation
--
-- SAFETY:
--   - Does not create a Secretariat registration trigger.
--   - Does not modify the existing Media Team registration trigger.
--   - Does not drop existing tables, columns, triggers, policies or functions.
--   - Stops if proposed function, trigger or constraint names already exist.
--   - Existing inactive accounts with unknown history retain NULL status.
--   - New account inserts omitting status default to 'pending'.
--   - Every administrative RPC independently checks the owner UUID.
--
-- OWNER AUTH UUID:
--   8cac4381-f40a-49d9-bdef-bd5854c49525
--
-- Run once, after live-schema verification.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 0. PRE-FLIGHT SAFETY CHECKS
-- ============================================================================

DO $preflight$
DECLARE
  v_role_bypass boolean;
  v_status_type text;
  v_trigger_exists boolean;
BEGIN

  -- Require a privileged migration role.
  SELECT (r.rolsuper OR r.rolbypassrls)
  INTO v_role_bypass
  FROM pg_catalog.pg_roles r
  WHERE r.rolname = current_user;

  IF COALESCE(v_role_bypass, false) = false THEN
    RAISE EXCEPTION
      'Migration stopped: execute as a database role with BYPASSRLS or superuser privileges.';
  END IF;

  -- Required tables.
  IF pg_catalog.to_regclass('public.secretariat_accounts') IS NULL THEN
    RAISE EXCEPTION
      'Migration stopped: public.secretariat_accounts does not exist.';
  END IF;

  IF pg_catalog.to_regclass('public.media_team_accounts') IS NULL THEN
    RAISE EXCEPTION
      'Migration stopped: public.media_team_accounts does not exist.';
  END IF;

  -- Required Secretariat columns.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'secretariat_accounts'
      AND column_name = 'user_id'
      AND data_type = 'uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'secretariat_accounts'
      AND column_name = 'display_name'
      AND data_type = 'text'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'secretariat_accounts'
      AND column_name = 'role'
      AND data_type = 'text'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'secretariat_accounts'
      AND column_name = 'is_active'
      AND data_type = 'boolean'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'secretariat_accounts'
      AND column_name = 'created_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION
      'Migration stopped: Secretariat table does not match the expected schema.';
  END IF;

  -- Required Media Team columns.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'user_id'
      AND data_type = 'uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'display_name'
      AND data_type = 'text'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'is_active'
      AND data_type = 'boolean'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'created_at'
      AND data_type = 'timestamp with time zone'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'updated_at'
      AND data_type = 'timestamp with time zone'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'email'
      AND data_type = 'text'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'media_team_accounts'
      AND column_name = 'phone'
      AND data_type = 'text'
  ) THEN
    RAISE EXCEPTION
      'Migration stopped: Media Team table does not match the expected schema.';
  END IF;

  -- Existing status columns must be nullable text, if present.
  SELECT c.data_type
  INTO v_status_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'secretariat_accounts'
    AND c.column_name = 'status';

  IF v_status_type IS NOT NULL AND v_status_type <> 'text' THEN
    RAISE EXCEPTION
      'Migration stopped: secretariat_accounts.status exists but is not text.';
  END IF;

  SELECT c.data_type
  INTO v_status_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'media_team_accounts'
    AND c.column_name = 'status';

  IF v_status_type IS NOT NULL AND v_status_type <> 'text' THEN
    RAISE EXCEPTION
      'Migration stopped: media_team_accounts.status exists but is not text.';
  END IF;

  -- Existing status columns must not be NOT NULL.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.secretariat_accounts'::regclass
      AND a.attname = 'status'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attnotnull
  ) THEN
    RAISE EXCEPTION
      'Migration stopped: secretariat_accounts.status is already NOT NULL. Inspect existing data first.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.media_team_accounts'::regclass
      AND a.attname = 'status'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attnotnull
  ) THEN
    RAISE EXCEPTION
      'Migration stopped: media_team_accounts.status is already NOT NULL. Inspect existing data first.';
  END IF;

  -- Do not replace proposed functions.
  IF pg_catalog.to_regprocedure(
       'public.rcz_touch_secretariat_account_updated_at()'
     ) IS NOT NULL
     OR pg_catalog.to_regprocedure('public.is_owner_admin()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_list_secretariat()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_list_media_team()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_secretariat_stats()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_media_team_stats()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_approve_secretariat(uuid,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_reject_secretariat(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_deactivate_secretariat(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_reactivate_secretariat(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_approve_media_team(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_reject_media_team(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_deactivate_media_team(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_reactivate_media_team(uuid)') IS NOT NULL
  THEN
    RAISE EXCEPTION
      'Migration stopped: one or more proposed functions already exist. Inspect them before proceeding.';
  END IF;

  -- Do not silently accept pre-existing constraints with these names.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = 'public.secretariat_accounts'::regclass
      AND c.conname = 'secretariat_accounts_status_check'
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = 'public.media_team_accounts'::regclass
      AND c.conname = 'media_team_accounts_status_check'
  ) THEN
    RAISE EXCEPTION
      'Migration stopped: a proposed status constraint already exists. Inspect its definition first.';
  END IF;

  -- Do not replace or reuse an existing trigger with the proposed name.
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'public.secretariat_accounts'::regclass
      AND t.tgname = 'rcz_secretariat_accounts_touch_updated_at'
      AND NOT t.tgisinternal
  )
  INTO v_trigger_exists;

  IF v_trigger_exists THEN
    RAISE EXCEPTION
      'Migration stopped: rcz_secretariat_accounts_touch_updated_at already exists.';
  END IF;

END;
$preflight$;


-- ============================================================================
-- 1. ADD ACCOUNT METADATA COLUMNS
-- ============================================================================

ALTER TABLE public.secretariat_accounts
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS status text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

ALTER TABLE public.media_team_accounts
  ADD COLUMN IF NOT EXISTS status text;

-- Ensure the Secretariat timestamp column is properly initialized.
UPDATE public.secretariat_accounts
SET updated_at = COALESCE(updated_at, created_at, pg_catalog.now())
WHERE updated_at IS NULL;

ALTER TABLE public.secretariat_accounts
  ALTER COLUMN updated_at SET DEFAULT pg_catalog.now(),
  ALTER COLUMN updated_at SET NOT NULL;

-- Future inserts that omit status are pending.
-- Existing NULL values remain NULL.
ALTER TABLE public.secretariat_accounts
  ALTER COLUMN status SET DEFAULT 'pending';

ALTER TABLE public.media_team_accounts
  ALTER COLUMN status SET DEFAULT 'pending';


-- ============================================================================
-- 2. BACKFILL SECRETARIAT CONTACT DETAILS
-- ============================================================================

-- Only fill missing values. Never overwrite existing account contact details.

UPDATE public.secretariat_accounts s
SET
  email = COALESCE(s.email, u.email),
  phone = COALESCE(
    s.phone,
    NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'contact_phone'), '')
  )
FROM auth.users u
WHERE u.id = s.user_id
  AND (s.email IS NULL OR s.phone IS NULL);


-- ============================================================================
-- 3. RECONCILE EXISTING STATUS VALUES
-- ============================================================================

-- Existing active accounts are known to be active.

UPDATE public.secretariat_accounts
SET status = 'active'
WHERE is_active = true
  AND status IS DISTINCT FROM 'active';

UPDATE public.media_team_accounts
SET status = 'active'
WHERE is_active = true
  AND status IS DISTINCT FROM 'active';

-- Existing inactive rows with unknown history remain NULL.
-- An inactive row incorrectly labelled active is reset to NULL.

UPDATE public.secretariat_accounts
SET status = NULL
WHERE is_active = false
  AND status = 'active';

UPDATE public.media_team_accounts
SET status = NULL
WHERE is_active = false
  AND status = 'active';

-- Normalize unexpected historical values to NULL.
-- Do not guess the historical meaning of unknown values.

UPDATE public.secretariat_accounts
SET status = NULL
WHERE status IS NOT NULL
  AND status NOT IN ('pending', 'active', 'rejected', 'inactive');

UPDATE public.media_team_accounts
SET status = NULL
WHERE status IS NOT NULL
  AND status NOT IN ('pending', 'active', 'rejected', 'inactive');


-- ============================================================================
-- 4. ADD STATUS CONSTRAINTS
-- ============================================================================

ALTER TABLE public.secretariat_accounts
  ADD CONSTRAINT secretariat_accounts_status_check
  CHECK (
    status IS NULL
    OR status IN ('pending', 'active', 'rejected', 'inactive')
  );

ALTER TABLE public.media_team_accounts
  ADD CONSTRAINT media_team_accounts_status_check
  CHECK (
    status IS NULL
    OR status IN ('pending', 'active', 'rejected', 'inactive')
  );


-- ============================================================================
-- 5. SECRETARIAT UPDATED_AT TRIGGER
-- ============================================================================

CREATE FUNCTION public.rcz_touch_secretariat_account_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.updated_at = pg_catalog.now();
  RETURN NEW;
END;
$function$;

-- Trigger functions are not RPC endpoints.
-- Do not grant application roles permission to call this directly.

REVOKE ALL ON FUNCTION
  public.rcz_touch_secretariat_account_updated_at()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER rcz_secretariat_accounts_touch_updated_at
BEFORE UPDATE ON public.secretariat_accounts
FOR EACH ROW
EXECUTE FUNCTION public.rcz_touch_secretariat_account_updated_at();


-- ============================================================================
-- 6. OWNER IDENTITY CHECK
-- ============================================================================

CREATE FUNCTION public.is_owner_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT auth.uid() =
    '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid;
$function$;

REVOKE ALL ON FUNCTION public.is_owner_admin()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.is_owner_admin()
TO authenticated;


-- ============================================================================
-- 7. ADMIN ACCOUNT LIST RPCs
-- ============================================================================

CREATE FUNCTION public.admin_list_secretariat()
RETURNS TABLE (
  user_id uuid,
  display_name text,
  email text,
  phone text,
  role text,
  status text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    s.user_id,
    s.display_name,
    s.email,
    s.phone,
    s.role,
    s.status,
    s.is_active,
    s.created_at,
    s.updated_at
  FROM public.secretariat_accounts s
  ORDER BY s.created_at DESC;
END;
$function$;


CREATE FUNCTION public.admin_list_media_team()
RETURNS TABLE (
  user_id uuid,
  display_name text,
  email text,
  phone text,
  status text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    m.user_id,
    m.display_name,
    m.email,
    m.phone,
    m.status,
    m.is_active,
    m.created_at,
    m.updated_at
  FROM public.media_team_accounts m
  ORDER BY m.created_at DESC;
END;
$function$;


-- ============================================================================
-- 8. ADMIN STATISTICS RPCs
-- ============================================================================

CREATE FUNCTION public.admin_secretariat_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  SELECT pg_catalog.jsonb_build_object(
    'pending',  pg_catalog.count(*) FILTER (WHERE s.status = 'pending'),
    'active',   pg_catalog.count(*) FILTER (WHERE s.status = 'active'),
    'inactive', pg_catalog.count(*) FILTER (WHERE s.status = 'inactive'),
    'rejected', pg_catalog.count(*) FILTER (WHERE s.status = 'rejected'),
    'legacy',   pg_catalog.count(*) FILTER (WHERE s.status IS NULL)
  )
  INTO v_result
  FROM public.secretariat_accounts s;

  RETURN v_result;
END;
$function$;


CREATE FUNCTION public.admin_media_team_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  SELECT pg_catalog.jsonb_build_object(
    'pending',  pg_catalog.count(*) FILTER (WHERE m.status = 'pending'),
    'active',   pg_catalog.count(*) FILTER (WHERE m.status = 'active'),
    'inactive', pg_catalog.count(*) FILTER (WHERE m.status = 'inactive'),
    'rejected', pg_catalog.count(*) FILTER (WHERE m.status = 'rejected'),
    'legacy',   pg_catalog.count(*) FILTER (WHERE m.status IS NULL)
  )
  INTO v_result
  FROM public.media_team_accounts m;

  RETURN v_result;
END;
$function$;


-- ============================================================================
-- 9. SECRETARIAT ACCOUNT MANAGEMENT RPCs
-- ============================================================================

CREATE FUNCTION public.admin_approve_secretariat(
  p_user_id uuid,
  p_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('SEC', 'VSEC') THEN
    RAISE EXCEPTION 'Invalid Secretariat role';
  END IF;

  UPDATE public.secretariat_accounts
  SET
    role = p_role,
    is_active = true,
    status = 'active',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_reject_secretariat(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.secretariat_accounts
  SET
    is_active = false,
    status = 'rejected',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_deactivate_secretariat(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.secretariat_accounts
  SET
    is_active = false,
    status = 'inactive',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_reactivate_secretariat(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.secretariat_accounts
  SET
    is_active = true,
    status = 'active',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


-- ============================================================================
-- 10. MEDIA TEAM ACCOUNT MANAGEMENT RPCs
-- ============================================================================

CREATE FUNCTION public.admin_approve_media_team(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.media_team_accounts
  SET
    is_active = true,
    status = 'active',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_reject_media_team(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.media_team_accounts
  SET
    is_active = false,
    status = 'rejected',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_deactivate_media_team(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.media_team_accounts
  SET
    is_active = false,
    status = 'inactive',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


CREATE FUNCTION public.admin_reactivate_media_team(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_owner_admin() THEN
    RAISE EXCEPTION 'Not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  IF p_user_id = '8cac4381-f40a-49d9-bdef-bd5854c49525'::uuid THEN
    RAISE EXCEPTION 'The owner account cannot be modified through this operation';
  END IF;

  UPDATE public.media_team_accounts
  SET
    is_active = true,
    status = 'active',
    updated_at = pg_catalog.now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
END;
$function$;


-- ============================================================================
-- 11. FUNCTION EXECUTION PERMISSIONS
-- ============================================================================

-- PostgreSQL grants EXECUTE to PUBLIC by default on new functions.
-- Revoke PUBLIC, anon and authenticated before granting authenticated.
-- Authorization is still enforced inside every administrative RPC.

REVOKE ALL ON FUNCTION public.admin_list_secretariat()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_list_media_team()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_secretariat_stats()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_media_team_stats()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_approve_secretariat(uuid, text)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_reject_secretariat(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_deactivate_secretariat(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_reactivate_secretariat(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_approve_media_team(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_reject_media_team(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_deactivate_media_team(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_reactivate_media_team(uuid)
FROM PUBLIC, anon, authenticated;


GRANT EXECUTE ON FUNCTION public.admin_list_secretariat()
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_list_media_team()
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_secretariat_stats()
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_media_team_stats()
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_approve_secretariat(uuid, text)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_reject_secretariat(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_secretariat(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_secretariat(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_approve_media_team(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_reject_media_team(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_media_team(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_media_team(uuid)
TO authenticated;


-- ============================================================================
-- 12. POSTGREST SCHEMA RELOAD
-- ============================================================================

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
