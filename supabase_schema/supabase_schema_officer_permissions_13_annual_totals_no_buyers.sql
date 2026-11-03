-- ============================================================
-- SAGANA — Officer permissions, script 13: COOPERATIVE YEARLY TOTALS — NO BUYERS
--
-- You asked to remove Buyer access NOW and to decide Farmer and Officer access
-- later. This script does only the first part.
--
-- WHAT THE TABLE HOLDS: cooperative_annual_totals — one row per year: total
--   cooperative sales, distributable surplus, interest rate, whether the annual
--   financial statement is final, and the same for the Product Sales Program.
--
-- HOW BUYERS GOT ACCESS: when the table was created (supabase_schema_contributions.sql)
--   it got the rule "authenticated reads" — any signed-in user — with the comment
--   "needed for share % display" (the Farmer's My Contribution screen). A Buyer is
--   also a signed-in user, so the rule covered Buyers by accident. Later, a
--   restrictive rule ("approved farmers only") was added to keep pending
--   applicants out, but nothing excluded Buyers.
--
-- NO BUYER SCREEN USES IT: only two screens read this table (see the list in my
--   report): the Manager's Balik-Tangkilik Management and the Farmer's My
--   Contribution. The Reports tab does not read it.
--
-- WHAT THIS DOES
--   Replaces the rule "authenticated reads" with the same rule that excludes a
--   Buyer's account. Farmers, Officers and the Manager read exactly as before.
--   The staff read rule and the "approved farmers only" restriction are untouched.
--   Nobody gains access.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo:
--   DROP POLICY "cooperative_annual_totals: signed-in non-buyers read" ON public.cooperative_annual_totals;
--   CREATE POLICY "cooperative_annual_totals: authenticated reads" ON public.cooperative_annual_totals
--     FOR SELECT USING (auth.role() = 'authenticated');
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "cooperative_annual_totals: authenticated reads" ON public.cooperative_annual_totals;
DROP POLICY IF EXISTS "cooperative_annual_totals: signed-in non-buyers read" ON public.cooperative_annual_totals;

CREATE POLICY "cooperative_annual_totals: signed-in non-buyers read"
  ON public.cooperative_annual_totals FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'buyer'
    )
  );

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT policyname, permissive, cmd, qual FROM pg_policies
--   WHERE tablename = 'cooperative_annual_totals' AND cmd = 'SELECT' ORDER BY policyname;
--   -- expect: the staff read, the "approved farmers only" restriction, and the new rule
-- In the app: a Buyer account sees no change anywhere (no Buyer screen reads this
-- table); a Farmer's My Contribution still shows the share percentage and the
-- cooperative total; the Manager's Balik-Tangkilik Management still loads.
-- ─────────────────────────────────────────────────────────────────────────
