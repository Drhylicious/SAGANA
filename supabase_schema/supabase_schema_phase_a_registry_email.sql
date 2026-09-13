-- ============================================================
-- SAGANA — Phase A: Registry email, auto-fill, duplicate blocking
-- (Admin Members tab enhancement — Issues 1, 2, 3)
--
-- Scope of this migration:
--   1. sp3_member_registry gets an optional `email` column so the
--      Register screen can auto-fill it for matched official members.
--      (Registry = official membership / matching information only:
--       Full Name, Purok, Phone Number, Email.)
--   2. check_sp3_registry now also returns phone_number + email, and
--      still reports is_available (= NOT is_registered) so the client
--      can tell "matched but already registered" apart from "no match".
--   3. New check_full_name_available(text) — global, case-insensitive
--      full-name uniqueness across BOTH sp3_member_registry (registered
--      rows) AND user_information (any existing account). Powers the
--      immediate "this name is already registered" error (Issue 3).
--   4. New check_email_available(text) — case-insensitive uniqueness of
--      user_information.contact_email, so a provided email is unique at
--      registration (Decision D10).
--
-- normalized_name on sp3_member_registry is a GENERATED ALWAYS column
-- (lower(trim(full_name))) and is already used for name matching today,
-- so it is intentionally left untouched here.
--
-- Function bodies below are rewritten from the CURRENT live definition
-- of check_sp3_registry (see supabase_schema_sitio_to_purok_rename.sql),
-- not the older username_auth migration.
-- ============================================================

BEGIN;

-- ─── 1. sp3_member_registry.email (optional) ────────────────────────────────

ALTER TABLE public.sp3_member_registry
  ADD COLUMN IF NOT EXISTS email TEXT;

COMMENT ON COLUMN public.sp3_member_registry.email IS
  'Optional. Official contact email recorded by the cooperative. '
  'Auto-filled into the Register screen when a full name matches. '
  'Nullable — many members have no email.';

-- ─── 2. check_sp3_registry — add phone_number + email to result ─────────────

DROP FUNCTION IF EXISTS public.check_sp3_registry(text);

CREATE FUNCTION public.check_sp3_registry(p_full_name text)
 RETURNS TABLE(
   registry_id     uuid,
   is_available    boolean,
   suggested_purok text,
   phone_number    text,
   email           text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    r.id,
    NOT r.is_registered AS is_available,
    r.purok,
    r.phone_number,
    r.email
  FROM sp3_member_registry r
  WHERE r.normalized_name = lower(trim(p_full_name))
  LIMIT 1;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_sp3_registry(text) TO anon, authenticated;

-- ─── 3. check_full_name_available ──────────────────────────────────────────
-- Returns:
--   'taken_account'  — a user_information row already has this full name
--   'taken_registry' — an sp3_member_registry row with this name is
--                      already marked is_registered (edge case: account
--                      row missing but registry says registered)
--   'available'      — safe to register this name
-- Case-insensitive, whitespace-trimmed on both sides.

CREATE OR REPLACE FUNCTION public.check_full_name_available(p_full_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := lower(trim(p_full_name));
BEGIN
  IF v_norm = '' THEN
    RETURN 'available';
  END IF;

  IF EXISTS (
    SELECT 1 FROM user_information ui
    WHERE lower(trim(ui.full_name)) = v_norm
  ) THEN
    RETURN 'taken_account';
  END IF;

  IF EXISTS (
    SELECT 1 FROM sp3_member_registry r
    WHERE r.normalized_name = v_norm
      AND r.is_registered = true
  ) THEN
    RETURN 'taken_registry';
  END IF;

  RETURN 'available';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_full_name_available(text) TO anon, authenticated;

-- ─── 4. check_email_available ──────────────────────────────────────────────
-- TRUE when no user_information.contact_email matches (case-insensitive).
-- An empty / null input is considered available (email is optional).

CREATE OR REPLACE FUNCTION public.check_email_available(p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := lower(trim(coalesce(p_email, '')));
BEGIN
  IF v_norm = '' THEN
    RETURN true;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1 FROM user_information ui
    WHERE lower(trim(ui.contact_email)) = v_norm
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_email_available(text) TO anon, authenticated;

COMMIT;

-- ============================================================
-- POST-DEPLOY VERIFICATION (run manually, expect the noted results)
-- ============================================================
-- 1) Column exists:
--    SELECT column_name, data_type, is_nullable
--    FROM information_schema.columns
--    WHERE table_name = 'sp3_member_registry' AND column_name = 'email';
--    -- expect: email | text | YES
--
-- 2) check_sp3_registry returns 5 columns now:
--    SELECT * FROM check_sp3_registry('some known registry name');
--    -- expect one row: registry_id, is_available, suggested_purok,
--    --                  phone_number, email
--
-- 3) Duplicate detection:
--    SELECT check_full_name_available('<an existing account full name>');
--    -- expect: taken_account
--    SELECT check_full_name_available('Totally New Person 12345');
--    -- expect: available
--
-- 4) Email uniqueness:
--    SELECT check_email_available('<an existing contact_email>');  -- expect: false
--    SELECT check_email_available('brandnew@example.com');         -- expect: true
--    SELECT check_email_available('');                             -- expect: true
-- ============================================================
