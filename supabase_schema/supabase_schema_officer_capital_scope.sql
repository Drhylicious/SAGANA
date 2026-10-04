-- Officers: loan eligibility without the capital amount.
--
-- Why: Officers issue loans, and the loan screen needs to know whether a farmer
-- meets the capital minimum. It does not need the farmer's capital total. This
-- adds a check that returns only "meets the minimum" (yes or no) and the minimum,
-- then removes Officers' direct read access to member_capital_shares.
--
-- Admin access is unchanged. Farmers still read their own capital rows.
-- Officers keep their other module reads (loans, orders, reports, dashboard).
--
-- Not applied automatically. Run in the Supabase SQL editor, then the checks below.

BEGIN;

CREATE OR REPLACE FUNCTION public.loan_capital_eligibility(p_farmer_id uuid)
RETURNS TABLE (meets_minimum boolean, minimum_required numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total numeric;
  v_min   numeric;
BEGIN
  IF NOT (
    public.is_platform_admin()
    OR EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Only an Admin or an Officer can check loan eligibility'
      USING ERRCODE = '42501';
  END IF;

  SELECT m.total_contribution INTO v_total
  FROM public.member_capital_shares m
  WHERE m.farmer_id = p_farmer_id;

  SELECT s.minimum_capital_contribution INTO v_min
  FROM public.loan_policy_settings s
  WHERE s.id = 1;

  v_min := COALESCE(v_min, 0);
  RETURN QUERY SELECT COALESCE(v_total, 0) >= v_min, v_min;
END;
$$;

REVOKE ALL ON FUNCTION public.loan_capital_eligibility(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.loan_capital_eligibility(uuid) TO authenticated;

DROP POLICY IF EXISTS "member_capital_shares: officer reads all" ON public.member_capital_shares;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (run after applying) ───────────────────────────────────────────
-- 1. The officer policy is gone; Admin and Farmer policies remain:
--    select polname from pg_policy where polrelid = 'member_capital_shares'::regclass;
--    Expected: "member_capital_shares: admin manages all", "member_capital_shares: farmer reads own".
--
-- 2. Signed in as an Officer, the Issue Loan screen shows Eligible / Not eligible and the
--    minimum. It does not show a farmer's capital amount.
--
-- 3. Signed in as an Admin, the Issue Loan screen still shows the farmer's capital amount.
