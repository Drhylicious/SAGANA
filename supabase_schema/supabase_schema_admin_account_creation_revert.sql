-- ============================================================
-- SAGANA — Revert: Admin Account Creation feature
--
-- The original Phase 1 migration (supabase_schema_admin_profile_
-- settings_phase1.sql) incorrectly added an in-app Admin-account-
-- creation feature (admin_registry table, check_admin_registry() and
-- create_admin_account() RPCs). Admin accounts are explicitly NOT
-- created through the SAGANA app — they are created directly via
-- Supabase Authentication (Add User), the same way the existing Admin
-- account was originally created.
--
-- This script removes those three objects from a database that
-- already ran the original migration. It does NOT touch:
--   - admin_profiles.date_of_birth / gender (still needed for the
--     Admin's own Edit Profile self-edit)
--   - officer_profiles.date_of_birth / gender (still needed for
--     Officer account creation + Officer's own Edit Profile self-edit)
--   - create_officer_account() (unchanged, correctly in scope)
--   - the marketplace_listings.reviewed_by/reviewed_at fix (unrelated,
--     separately confirmed and approved)
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.create_admin_account(text,text,text,date,text,text,text,uuid);
DROP FUNCTION IF EXISTS public.check_admin_registry(text);
DROP TABLE IF EXISTS public.admin_registry;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-REVERT VERIFICATION
-- ============================================================
-- All three should return zero rows / not-found:
--    SELECT proname FROM pg_proc WHERE proname IN ('create_admin_account','check_admin_registry');
--    SELECT to_regclass('public.admin_registry');  -- null
--
-- These should be unaffected (still present):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name IN ('admin_profiles','officer_profiles') AND column_name IN ('date_of_birth','gender');  -- 4 rows
--    SELECT proname FROM pg_proc WHERE proname = 'create_officer_account';  -- 1 row
-- ============================================================
