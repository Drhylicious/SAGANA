-- ============================================================
-- SAGANA — Registration refactor, step 5: backend access gate for Farmers
-- who are not approved. REPLACES step 3 (do not run step 3 as well; if it
-- was already run, this file removes its policies and keeps its protection).
--
-- THE RULE. A signed-in user whose role is 'farmer' may write to the
-- cooperative's farmer modules only while user_roles.status = 'active'
-- (Approved). A Pending, Disapproved ('rejected') or Suspended Farmer gets a
-- clear error from the database instead. Managers, Officers, Buyers, and
-- system jobs (cron, no signed-in user) are never affected.
--
-- HOW IT IS ENFORCED. A row trigger on each module table, not a row-level
-- security policy, so it also catches writes made inside SECURITY DEFINER
-- functions (place_order, create_listing_with_reservation, the enrollment and
-- purchase requests ...), which bypass RLS. The trigger looks only at WHO is
-- signed in (auth.uid()), so no function body had to be rewritten.
--
-- WHAT STAYS OPEN FOR A PENDING / DISAPPROVED FARMER (on purpose)
--   * seeing their own application status, notifications and the public
--     catalogue data every signed-in user can already read;
--   * editing permitted personal information: name, phone, contact email,
--     photo (user_information), date of birth and gender (farmer_profiles),
--     and their address (buyer_addresses, fixed area enforced by step 4);
--   * submit_application / acknowledge_membership (user_roles, status events);
--   * marking their own notifications read; the profile / home activity logs.
--
-- FARM DATA IS NOT PERSONAL INFORMATION. farmer_profiles also holds farm
-- details; a not-approved Farmer may change only date_of_birth and gender
-- there. Only a Manager can mark a profile verified.
--
-- READ ACCESS IS NOT RESTRICTED. This file gates writes. A Pending Farmer has
-- no records of their own to read, and the shared reference data (programs,
-- market rates, marketplace listings) is what any signed-in user can already
-- see. Storage-bucket policies (photos) are NOT covered here; see the report.
--
-- Not applied automatically. Run the PRE-FLIGHT block, this file, then verify.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Which of the gated tables exist in your database (the loop below skips
--    any that do not):
--    SELECT t.name, to_regclass('public.'||t.name) IS NOT NULL AS exists
--    FROM (VALUES ('harvest_records'),('inventory_batches'),('marketplace_listings'),
--      ('farmer_expenses'),('farmer_crops'),('crop_requests'),('informal_sales'),
--      ('cooperative_purchase_offers'),('market_linking_programs'),
--      ('program_enrollment_requests'),('program_product_purchases'),('orders'),
--      ('expense_categories')) AS t(name);
--
-- B. Every table a not-approved Farmer could currently write, from the live
--    policies (review anything not in the list above):
--    SELECT tablename, policyname, cmd FROM pg_policies
--    WHERE schemaname='public' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
--      AND (qual ILIKE '%auth.uid()%' OR with_check ILIKE '%auth.uid()%')
--      AND policyname NOT ILIKE '%admin%' AND policyname NOT ILIKE '%staff%'
--    ORDER BY tablename, cmd;
--
-- C. Farmers who are not approved but already own rows (informational — they
--    keep them; they just cannot add or change more):
--    SELECT ur.status, count(DISTINCT hr.farmer_id) FROM public.harvest_records hr
--    JOIN public.user_roles ur ON ur.user_id = hr.farmer_id
--    WHERE ur.status <> 'active' GROUP BY ur.status;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- Step 3's restrictive policies (if it was run) are replaced by the triggers.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['harvest_records','inventory_batches','marketplace_listings','farmer_expenses','farmer_crops']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (insert)', t);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (update)', t);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (delete)', t);
    END IF;
  END LOOP;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 1. The gate
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_active_farmer_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_role   text;
  v_status text;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT role, status INTO v_role, v_status FROM public.user_roles WHERE user_id = v_uid;
    IF v_role = 'farmer' AND v_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION '%', CASE v_status
        WHEN 'pending'   THEN 'Your membership is pending approval. This feature is available once the SP3 Manager approves your application.'
        WHEN 'rejected'  THEN 'Your membership application was disapproved. This feature is not available to you.'
        WHEN 'suspended' THEN 'Your account is suspended. This feature is not available right now.'
        ELSE 'Please finish and submit your membership application first.'
      END;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'harvest_records',            -- harvest log
    'inventory_batches',          -- inventory
    'marketplace_listings',       -- listings
    'farmer_expenses',            -- expenses
    'farmer_crops',               -- my crops
    'crop_requests',              -- request a new crop
    'informal_sales',             -- informal sales
    'cooperative_purchase_offers',-- cooperative offers
    'market_linking_programs',    -- market linking requests / withdrawals
    'program_enrollment_requests',-- programs
    'program_product_purchases',  -- program product purchases
    'orders',                     -- buying as a farmer (place_order)
    'expense_categories'          -- adding an expense category
  ]
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_active_farmer_write ON public.%I', t);
      EXECUTE format(
        'CREATE TRIGGER trg_active_farmer_write BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.enforce_active_farmer_write()', t);
    END IF;
  END LOOP;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. farmer_profiles: personal information only until approved
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.guard_farmer_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_role   text;
  v_status text;
BEGIN
  -- Only a Manager can mark a member verified (approve_member /
  -- create_farmer_account run with the Manager's identity and pass).
  IF NEW.is_verified IS TRUE
     AND (TG_OP = 'INSERT' OR OLD.is_verified IS DISTINCT FROM TRUE)
     AND v_uid IS NOT NULL
     AND NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Only a Manager can verify a member';
  END IF;

  -- A farmer who is not approved may change date of birth and gender only.
  IF TG_OP = 'UPDATE' AND v_uid IS NOT NULL THEN
    SELECT role, status INTO v_role, v_status FROM public.user_roles WHERE user_id = v_uid;
    IF v_role = 'farmer' AND v_status IS DISTINCT FROM 'active'
       AND (to_jsonb(NEW) - 'date_of_birth' - 'gender' - 'updated_at')
           IS DISTINCT FROM
           (to_jsonb(OLD) - 'date_of_birth' - 'gender' - 'updated_at') THEN
      RAISE EXCEPTION 'Farm details are available once the SP3 Manager approves your membership.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_farmer_profile_is_verified ON public.farmer_profiles; -- step 3's trigger
DROP TRIGGER IF EXISTS trg_guard_farmer_profile_update ON public.farmer_profiles;
CREATE TRIGGER trg_guard_farmer_profile_update
  BEFORE INSERT OR UPDATE ON public.farmer_profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_farmer_profile_update();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Triggers are in place (expect one row per existing table above):
--    SELECT event_object_table, count(*) FROM information_schema.triggers
--    WHERE trigger_name = 'trg_active_farmer_write' GROUP BY 1 ORDER BY 1;
--
-- 2. Simulate a PENDING farmer calling the API (rolled back). Replace the
--    uuid with a pending farmer's user_id. Expect the "pending approval" error:
--    BEGIN;
--      SET LOCAL ROLE authenticated;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<pending farmer uuid>','role','authenticated')::text, true);
--      INSERT INTO public.farmer_expenses (farmer_id, amount, category)
--        VALUES ('<pending farmer uuid>', 1, 'test');          -- expect ERROR
--    ROLLBACK;
--
-- 3. The same simulation for an APPROVED farmer must NOT raise the membership
--    error (it may still fail on your table's own required columns - that is
--    unrelated), and for a pending farmer these must still work:
--    BEGIN;
--      SET LOCAL ROLE authenticated;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<pending farmer uuid>','role','authenticated')::text, true);
--      UPDATE public.farmer_profiles SET gender = 'female' WHERE user_id = '<pending farmer uuid>';   -- allowed
--      UPDATE public.farmer_profiles SET farm_name = 'x'   WHERE user_id = '<pending farmer uuid>';   -- expect ERROR
--      UPDATE public.user_information SET full_name = full_name WHERE user_id = '<pending farmer uuid>'; -- allowed
--    ROLLBACK;
--
-- 4. Manager / Officer unaffected: repeat (2) with a Manager's or Officer's
--    uuid - the membership error must not appear.
-- ============================================================
