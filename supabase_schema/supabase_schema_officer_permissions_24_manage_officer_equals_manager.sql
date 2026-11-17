-- ============================================================
-- SAGANA — Officer permissions, script 24:
--   AN OFFICER WITH MANAGE CAN DO WHAT THE MANAGER CAN, IN THAT MODULE
--
-- YOUR RULE: every action the Manager has inside a module an Officer is given Manage on
-- must also be available to that Officer; View Only still changes nothing.
--
-- WHAT YOUR LIVE CHECK SHOWED (Manager-only in the database)
--   Marketplace : set_pickup_enabled, set_delivery_enabled, save_delivery_fee_bands,
--                 save_cooperative_details, verify_cooperative_contact
--   Members     : admin_delete_rejected_applicant
--   Members     : the Status History (member_status_events) could be READ by the Manager only
--
-- WHAT THIS DOES
--   1. Marketplace (5 functions): the test "is the Manager" becomes "is staff". They are added
--      to the Officer gate under Marketplace, so an Officer with Marketplace = View Only is still
--      refused, exactly like every other Marketplace action.
--   2. Delete a disapproved account: the test becomes the Members test the other Members actions
--      use (Manager, or an Officer with Members = Manage). It is already in the gate under Members.
--      Everything it checks and records is unchanged (the dependency check, the accountability line).
--   3. Status History can be read by every staff member.
--   Each function is read from YOUR LIVE database (pg_get_functiondef) and changed in place, so
--   nothing newer is overwritten. If a function does not look as expected, nothing is changed and
--   the script stops with a message. The refusal text "Only the Manager can ..." now reads
--   "Only the Manager or an Officer can ...".
--
-- KEPT MANAGER-ONLY ON PURPOSE (unchanged here, still your decision to change):
--   creating Officer accounts, changing an Officer's access, and approving or disapproving a
--   Farmer that an Officer created. Opening those would let an Officer grant themselves more access
--   or approve their own work.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- ============================================================

DO $$
DECLARE
  v_sig text;
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL OR to_regprocedure('public.is_platform_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_staff() / is_platform_admin(uuid) are missing.';
  END IF;
  IF to_regclass('public.staff_permission_targets') IS NULL OR to_regclass('public.member_status_events') IS NULL THEN
    RAISE EXCEPTION 'staff_permission_targets or member_status_events is missing.';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.set_pickup_enabled(boolean)',
    'public.set_delivery_enabled(boolean)',
    'public.save_delivery_fee_bands(jsonb)',
    'public.save_cooperative_details(text,text,double precision,double precision,text)',
    'public.verify_cooperative_contact()',
    'public.admin_delete_rejected_applicant(uuid)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE NOTICE '% was not found by that exact signature; run the check at the bottom and send me its signature.', v_sig;
    END IF;
  END LOOP;
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
    SELECT p.oid, p.oid::regprocedure AS sig, p.proname,
           CASE WHEN p.proname = 'admin_delete_rejected_applicant' THEN 'public.is_platform_admin()' ELSE 'public.is_staff()' END AS replacement
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('set_pickup_enabled', 'set_delivery_enabled', 'save_delivery_fee_bands',
                        'save_cooperative_details', 'verify_cooperative_contact', 'admin_delete_rejected_applicant')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    IF v_def !~* 'is_manager\(' THEN
      RAISE NOTICE '% no longer tests is_manager(); left as it is.', r.sig;
      CONTINUE;
    END IF;
    v_new := regexp_replace(v_def, 'NOT\s+public\.is_manager\(\s*\)', 'NOT ' || r.replacement, 'gi');
    v_new := replace(v_new, 'Only the Manager can', 'Only the Manager or an Officer can');
    IF v_new ~* 'is_manager\(' THEN
      RAISE EXCEPTION '% still uses is_manager() in a form this script does not recognise; nothing was changed. Send me its definition.', r.sig;
    END IF;
    EXECUTE v_new;
    RAISE NOTICE '% changed.', r.sig;
  END LOOP;
END $$;

-- The Officer gate: View Only is refused, Manage is allowed (admin_delete_rejected_applicant is already there).
INSERT INTO public.staff_permission_targets (kind, name, module)
SELECT 'rpc', n, 'marketplace'
FROM (VALUES ('set_pickup_enabled'), ('set_delivery_enabled'), ('save_delivery_fee_bands'),
             ('save_cooperative_details'), ('verify_cooperative_contact')) v(n)
ON CONFLICT (kind, name) DO NOTHING;

-- Status History: every staff member can read it.
DROP POLICY IF EXISTS "mse: manager reads" ON public.member_status_events;
DROP POLICY IF EXISTS "mse: staff reads" ON public.member_status_events;
CREATE POLICY "mse: staff reads"
  ON public.member_status_events FOR SELECT
  USING (public.is_staff());

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('set_pickup_enabled','set_delivery_enabled','save_delivery_fee_bands',
--                       'save_cooperative_details','verify_cooperative_contact','admin_delete_rejected_applicant')
--     AND p.prosrc ~* 'is_manager\(';                                   -- expect no rows
--   SELECT name, module FROM staff_permission_targets
--   WHERE name IN ('set_pickup_enabled','set_delivery_enabled','save_delivery_fee_bands','save_cooperative_details',
--                  'verify_cooperative_contact','admin_delete_rejected_applicant');   -- 6 rows
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'member_status_events';  -- "mse: staff reads" / SELECT
-- In the app, as Arisu with Marketplace = Manage: Cooperative Details and Delivery Settings can be edited;
-- with Marketplace = View Only they open read-only. With Members = Manage, a disapproved account can be
-- deleted and Status History shows in Farmer Details.
-- ─────────────────────────────────────────────────────────────────────────
