-- ============================================================
-- SAGANA — Cooperative Details, Pickup and Delivery settings are MANAGER-ONLY
--
-- WHY
--   Your rule: only the Manager can change the Cooperative Details, the Pickup / Delivery
--   switches, the delivery fee rates and verify the cooperative contact number. The screens say
--   "Only the Manager can change them." Script 24 (officer_permissions_24) had opened these five
--   functions to every staff member and added them to the Officer gate under Marketplace.
--   This script puts the Manager-only test back. It is the reverse of script 24 for these five
--   functions ONLY.
--
-- WHAT IT DOES
--   1. set_pickup_enabled, set_delivery_enabled, save_delivery_fee_bands, save_cooperative_details
--      and verify_cooperative_contact: the test "is staff" becomes "is the Manager" again
--      (public.is_manager()), and the refusal text reads "Only the Manager can ..." again.
--      Each function is read from YOUR LIVE database (pg_get_functiondef) and changed in place, so
--      nothing newer is overwritten. A function that already tests is_manager() is left alone.
--      If a function does not look as expected, nothing is changed and the script stops.
--   2. Removes those five names from staff_permission_targets (the Officer gate). They no longer
--      need a gate entry: only the Manager can call them, so an Officer is refused whatever their
--      Marketplace level is.
--   Everything else script 24 did stays (deleting a disapproved account by an Officer with
--   Members = Manage, and Status History readable by every staff member). Every Officer can still
--   READ the Cooperative Details and Delivery Settings (read policies are unchanged).
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.is_manager()') IS NULL AND to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager() is missing.';
  END IF;
  IF to_regclass('public.staff_permission_targets') IS NULL THEN
    RAISE EXCEPTION 'staff_permission_targets is missing.';
  END IF;
END $$;

BEGIN;
SELECT set_config('lock_timeout', '5s', true);

DO $$
DECLARE
  r record;
  v_def text;
  v_new text;
BEGIN
  -- Every function with these names (whatever its argument list), read from the live database.
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('set_pickup_enabled', 'set_delivery_enabled', 'save_delivery_fee_bands',
                        'save_cooperative_details', 'verify_cooperative_contact')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    IF v_def ~* 'NOT\s+public\.is_manager\(\s*\)' AND v_def !~* 'NOT\s+public\.is_staff\(\s*\)' THEN
      RAISE NOTICE '% already tests is_manager(); left as it is.', r.sig;
      CONTINUE;
    END IF;
    IF v_def !~* 'NOT\s+public\.is_staff\(\s*\)' THEN
      RAISE EXCEPTION '% has no "NOT public.is_staff()" test this script recognises; nothing was changed. Send me its definition.', r.sig;
    END IF;
    v_new := regexp_replace(v_def, 'NOT\s+public\.is_staff\(\s*\)', 'NOT public.is_manager()', 'gi');
    v_new := replace(v_new, 'Only the Manager or an Officer can', 'Only the Manager can');
    IF v_new !~* 'is_manager\(' THEN
      RAISE EXCEPTION '% was not changed as expected; nothing was changed.', r.sig;
    END IF;
    EXECUTE v_new;
    RAISE NOTICE '% is Manager-only again.', r.sig;
  END LOOP;
END $$;

-- The Officer gate no longer lists them.
DELETE FROM public.staff_permission_targets
WHERE kind = 'rpc'
  AND name IN ('set_pickup_enabled', 'set_delivery_enabled', 'save_delivery_fee_bands',
               'save_cooperative_details', 'verify_cooperative_contact');

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   -- 1. Each of the five must test is_manager() and must NOT test is_staff():  expect 5 rows, both flags as shown
--   SELECT p.oid::regprocedure AS fn,
--          p.prosrc ~* 'NOT\s+public\.is_manager\(' AS tests_manager,
--          p.prosrc ~* 'NOT\s+public\.is_staff\('   AS tests_staff
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('set_pickup_enabled','set_delivery_enabled','save_delivery_fee_bands',
--                       'save_cooperative_details','verify_cooperative_contact');
--      -- expect tests_manager = true and tests_staff = false on every row
--   -- 2. No gate rows for them left:  expect 0 rows
--   SELECT name, module FROM staff_permission_targets
--   WHERE name IN ('set_pickup_enabled','set_delivery_enabled','save_delivery_fee_bands',
--                  'save_cooperative_details','verify_cooperative_contact');
-- In the app: as the Manager the Cooperative Details and Delivery Settings can be edited. As an Officer
-- (even with Marketplace = Manage) they open read-only with "Only the Manager can change them."
-- ────────────────────────────────────────────────────────────────────────
