-- ============================================================
-- SAGANA — Officer permissions, script 16: A FARMER'S OWN SHARE (function)
--
-- DECISION (yours): a Farmer sees only their OWN contribution totals and their
-- estimated share. The cooperative-wide totals are hidden from Farmer
-- "My Contribution".
--
-- WHY A FUNCTION: today My Contribution reads the cooperative totals straight from
-- the table (cooperative_annual_totals) and divides the Farmer's own total by it
-- on the phone, so the Farmer's phone receives the cooperative-wide figure. This
-- function does the division INSIDE the database and returns only the two
-- percentages; the cooperative total never leaves the database.
--
-- WHAT IT RETURNS (one row, for the signed-in Farmer only, for the year asked):
--   selling_share_percent   my sales to the cooperative  / all sales to the cooperative  * 100
--   buying_share_percent    my Product Sales Program purchases / all program purchases     * 100
-- Same formula the app uses now (0 when the cooperative total is 0 or missing).
-- It takes no member id: it always answers for the caller, so nobody can ask about
-- another member. A pending applicant gets no row, like the table's own
-- "approved farmers only" rule.
--
-- ADDITIVE AND SAFE TO RUN FIRST: it creates one new function and changes nothing
-- else. The current app keeps working until the app update is installed.
-- Script 17 (later, AFTER the app update) removes the Farmer's direct table read.
--
-- CORRECTION (2026-11): the first version of this script stopped with
-- "is_unapproved_applicant() is missing". The function exists; its real signature is
--   public.is_unapproved_applicant(p_uid uuid DEFAULT auth.uid())     (registration_08)
-- one argument with a default, which is why the policies can call it with no
-- argument. The check asked for a zero-argument version, which does not exist. It
-- now checks the real signature, and the function passes auth.uid() explicitly.
--
-- BASED ON the live table columns seen in the code: cooperative_annual_totals
-- (year, total_coop_sales, total_program_sales) and member_contributions
-- (farmer_id, year, total_sales_amount, program_purchases_amount).
--
-- Not applied automatically. Run in the Supabase SQL editor. Re-runnable.
-- To undo: DROP FUNCTION public.get_my_activity_share(integer);
-- ============================================================

DO $$
BEGIN
  IF to_regclass('public.cooperative_annual_totals') IS NULL OR to_regclass('public.member_contributions') IS NULL THEN
    RAISE EXCEPTION 'cooperative_annual_totals or member_contributions is missing.';
  END IF;
  IF to_regprocedure('public.is_unapproved_applicant(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_unapproved_applicant(uuid) is missing.';
  END IF;
END $$;

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_activity_share(p_year integer)
RETURNS TABLE (selling_share_percent numeric, buying_share_percent numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE WHEN COALESCE(t.total_coop_sales, 0) > 0
         THEN COALESCE(mc.total_sales_amount, 0) / t.total_coop_sales * 100
         ELSE 0 END,
    CASE WHEN COALESCE(t.total_program_sales, 0) > 0
         THEN COALESCE(mc.program_purchases_amount, 0) / t.total_program_sales * 100
         ELSE 0 END
  FROM (SELECT 1) AS one
  LEFT JOIN cooperative_annual_totals t ON t.year = p_year
  LEFT JOIN member_contributions mc ON mc.farmer_id = auth.uid() AND mc.year = p_year
  WHERE auth.uid() IS NOT NULL
    AND NOT public.is_unapproved_applicant(auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_my_activity_share(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_activity_share(integer) TO authenticated;

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT proname, prosecdef, pg_get_function_result(oid) FROM pg_proc WHERE proname = 'get_my_activity_share';
--   -- expect: prosecdef true; result: TABLE(selling_share_percent numeric, buying_share_percent numeric)
-- As a Farmer in the app (after the update): My Contribution shows "My Share" for
-- selling and buying, and no "Cooperative Total".
-- ─────────────────────────────────────────────────────────────────────────
