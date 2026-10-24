-- ============================================================
-- SUPERSEDED — DO NOT RUN. Use supabase_schema_registration_05_farmer_access_gate.sql
-- instead: it covers every farmer module (not just five tables), also catches
-- writes made inside database functions, and removes the policies this file
-- creates if it was already run. Kept only so the history is complete.
-- ============================================================
--
-- SAGANA — Registration refactor, step 3 of 3 (RECOMMENDED, REVIEW FIRST):
-- backend write gate for farmers who are not approved
--
-- Why: today a Pending, Disapproved or Suspended farmer is stopped only by the
-- app (router redirect + AuthService.requireActiveMembership). The tables
-- below let any farmer write their own rows ("farmer manages own"), with no
-- check of user_roles.status — so anyone calling the Supabase API directly
-- could log harvests, expenses and crops before approval. The requirement is
-- that approval status is enforced by the backend.
--
-- What this adds (nothing existing is changed or dropped):
--   1. is_active_farmer()   TRUE when the caller is a farmer whose
--                           user_roles.status = 'active'.
--   2. RESTRICTIVE policies on the farmer-owned tables below. A restrictive
--      policy is ANDed with the existing permissive ones, so existing access
--      is only ever narrowed: INSERT / UPDATE / DELETE now also require
--      (is_staff() OR is_active_farmer()). SELECT is not touched.
--      SECURITY DEFINER functions are not affected (they bypass RLS).
--   3. A trigger so only a Manager can mark farmer_profiles.is_verified true.
--
-- Tables: harvest_records, inventory_batches, marketplace_listings,
--         farmer_expenses, farmer_crops.
--
-- This is deliberately a separate file: it narrows live write paths I cannot
-- exercise without your database. Apply it AFTER steps 1 and 2 are working,
-- then run the checks at the end with an approved and a pending test farmer.
-- To undo it, run the ROLLBACK block at the bottom.
--
-- Not applied automatically.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. The farmer-facing policies currently on these tables:
--    SELECT tablename, policyname, cmd, permissive FROM pg_policies
--    WHERE schemaname = 'public'
--      AND tablename IN ('harvest_records', 'inventory_batches',
--                        'marketplace_listings', 'farmer_expenses', 'farmer_crops')
--    ORDER BY tablename, cmd, policyname;
--
-- B. Any farmer who is NOT approved but already has rows (informational —
--    they keep the rows; they just cannot add or change more):
--    SELECT ur.status, count(DISTINCT hr.farmer_id) AS farmers_with_harvests
--    FROM public.harvest_records hr
--    JOIN public.user_roles ur ON ur.user_id = hr.farmer_id
--    WHERE ur.status <> 'active' GROUP BY ur.status;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.is_active_farmer(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_uid AND role = 'farmer' AND status = 'active'
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_farmer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_active_farmer(uuid) TO authenticated;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'harvest_records', 'inventory_batches', 'marketplace_listings',
    'farmer_expenses', 'farmer_crops'
  ]
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   t || ': approved farmers only (insert)', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
      'WITH CHECK (public.is_staff() OR public.is_active_farmer())',
      t || ': approved farmers only (insert)', t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   t || ': approved farmers only (update)', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
      'USING (public.is_staff() OR public.is_active_farmer()) '
      'WITH CHECK (public.is_staff() OR public.is_active_farmer())',
      t || ': approved farmers only (update)', t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   t || ': approved farmers only (delete)', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
      'USING (public.is_staff() OR public.is_active_farmer())',
      t || ': approved farmers only (delete)', t);
  END LOOP;
END;
$$;

-- Only a Manager can set is_verified = true (farmers can otherwise edit their
-- own farmer_profiles row). approve_member() and create_farmer_account() run
-- with the Manager's identity, so they pass.
CREATE OR REPLACE FUNCTION public.guard_farmer_profile_is_verified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_verified IS TRUE
     AND (TG_OP = 'INSERT' OR OLD.is_verified IS DISTINCT FROM TRUE)
     AND NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Only a Manager can verify a member';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_farmer_profile_is_verified ON public.farmer_profiles;
CREATE TRIGGER trg_guard_farmer_profile_is_verified
  BEFORE INSERT OR UPDATE ON public.farmer_profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_farmer_profile_is_verified();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. 15 restrictive policies exist (expect 15):
--    SELECT count(*) FROM pg_policies
--    WHERE schemaname = 'public' AND permissive = 'RESTRICTIVE'
--      AND policyname LIKE '%: approved farmers only (%';
--
-- 2. In the app, with a throwaway PENDING farmer: Harvest, Expenses, Crops and
--    Create Listing are unreachable (router) — and a direct API insert fails:
--    "new row violates row-level security policy".
-- 3. With an APPROVED farmer (or a Manager-created one): log a harvest, add an
--    expense, create a listing — all still work, including Sync Now for
--    records queued offline.
-- 4. A Manager / Officer still reads and edits those tables as before.
--
-- ─── ROLLBACK (undoes this file only) ────────────────────────────────────
-- BEGIN;
-- DO $$ DECLARE t text; BEGIN
--   FOREACH t IN ARRAY ARRAY['harvest_records','inventory_batches',
--     'marketplace_listings','farmer_expenses','farmer_crops'] LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (insert)', t);
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (update)', t);
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': approved farmers only (delete)', t);
--   END LOOP; END $$;
-- DROP TRIGGER IF EXISTS trg_guard_farmer_profile_is_verified ON public.farmer_profiles;
-- COMMIT;
-- ============================================================
