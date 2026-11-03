-- ============================================================
-- SAGANA — Officer permissions, script 17: COOPERATIVE YEARLY TOTALS — STAFF ONLY
--
-- DECISIONS (yours):
--   * Farmers see only their own share (script 16): they no longer read this table.
--   * The Manager AND Officers can read the yearly totals (the new read-only view
--     under the Reports tab). Only the Manager changes them, in Balik-Tangkilik
--     Management.
--   * Buyers never read it (script 13).
--
-- WHAT THIS DOES
--   Drops the rule that script 13 left for everyone except Buyers. What remains is
--   exactly:
--     read   : staff only (the existing rule "admin manages all (read)" = Manager and
--              Officers), plus the existing "approved farmers only" restriction
--     write  : Manager only (the existing insert / update / delete rules; they already
--              exclude Officers)
--   After this, a Farmer's or Buyer's direct read of the table returns nothing.
--
-- !! RUN THIS ONLY AFTER (1) script 16 and (2) the app update are installed !!
--   The current app's Farmer My Contribution still reads this table directly. If this
--   script runs first, that screen shows 0% shares until the update is installed
--   (nothing breaks otherwise). The script checks that script 16 is present.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo (Farmers read it again, Buyers still do not):
--   CREATE POLICY "cooperative_annual_totals: signed-in non-buyers read"
--     ON public.cooperative_annual_totals FOR SELECT
--     USING (auth.role() = 'authenticated'
--            AND NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = auth.uid() AND r.role = 'buyer'));
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.get_my_activity_share(integer)') IS NULL THEN
    RAISE EXCEPTION 'Run script 16 first (get_my_activity_share is missing), then install the app update.';
  END IF;
END $$;

BEGIN;

DROP POLICY IF EXISTS "cooperative_annual_totals: signed-in non-buyers read" ON public.cooperative_annual_totals;
DROP POLICY IF EXISTS "cooperative_annual_totals: authenticated reads" ON public.cooperative_annual_totals;

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT policyname, permissive, cmd FROM pg_policies
--   WHERE tablename = 'cooperative_annual_totals' ORDER BY cmd, policyname;
--   -- expect SELECT: "admin manages all (read)" (staff) and "approved farmers only (read)" (restrictive);
--   --        INSERT / UPDATE / DELETE: the three "admin manages all" rules (Manager only)
-- In the app: the Manager's Balik-Tangkilik Management and the new Reports > Cooperative
-- Yearly Totals load; an Officer sees the totals read-only; a Farmer's My Contribution shows
-- their share and no cooperative total; a Buyer is unaffected.
-- ─────────────────────────────────────────────────────────────────────────
