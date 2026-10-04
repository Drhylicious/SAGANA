-- ============================================================
-- SAGANA — Farmer self-recorded Monthly Membership Renewal
--
-- Lets a farmer record their own ₱100/month membership renewal payment
-- directly from My Contribution, mirroring how Loan Management's payment
-- flow works conceptually (a recorded transaction inside the app, no
-- real payment gateway involved) but performed by the farmer themselves
-- rather than admin, per the organization's explicit decision.
--
-- capital_contribution_events has no farmer INSERT policy (by design —
-- "cce: admin manages all" is FOR ALL, admin-only; farmers only have
-- "cce: farmer reads own"), and every other farmer-initiated write to
-- this table already goes through a SECURITY DEFINER RPC rather than a
-- raw client insert (see reinvest_patronage_capital(), supabase_schema_
-- patronage_capital_reinvestment.sql) — this follows the same pattern,
-- since a real-money-adjacent operation should never be a raw client
-- insert a farmer could otherwise tamper with (arbitrary amount, source,
-- or repeated submissions).
--
-- Guards against a farmer recording more than one renewal in the same
-- calendar month — self-service with no admin confirmation step means
-- this is the only integrity check preventing inflated capital records.
-- ============================================================

BEGIN;

-- loan_policy_settings previously had no farmer SELECT policy at all
-- (only "admin reads" / "officer reads") — CapitalContributionRepository.
-- fetchCapitalSummary() silently fell back to hardcoded defaults when
-- called for a farmer, which happen to match today's actual defaults but
-- would go stale the moment the co-op changes them. This is plain
-- read-only policy data (loan minimum, monthly dues, share target), not
-- sensitive, so a farmer read policy is safe to add.
DROP POLICY IF EXISTS "loan_policy_settings: farmer reads" ON public.loan_policy_settings;
CREATE POLICY "loan_policy_settings: farmer reads"
  ON public.loan_policy_settings FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'farmer' AND status = 'active'
  ));

-- ─── record_membership_renewal ──────────────────────────────────────────────
-- Farmer-initiated (auth.uid() = the calling farmer). Amount is always the
-- current policy's monthly_dues_amount — never a farmer-supplied figure —
-- so this can only ever record exactly one month's worth of dues per call.
CREATE OR REPLACE FUNCTION public.record_membership_renewal(
  p_note TEXT DEFAULT NULL
)
RETURNS NUMERIC  -- returns the farmer's new total_contribution
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer UUID := auth.uid();
  v_amount NUMERIC;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::date;
  v_already_recorded BOOLEAN;
  v_new_total NUMERIC;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT monthly_dues_amount INTO v_amount
  FROM loan_policy_settings WHERE id = 1;
  IF v_amount IS NULL OR v_amount <= 0 THEN
    v_amount := 100; -- matches the app-side fallback default
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM capital_contribution_events
    WHERE farmer_id = v_farmer
      AND source = 'member_payment'
      AND note LIKE 'Monthly membership renewal —%'
      AND created_at >= v_month_start
  ) INTO v_already_recorded;

  IF v_already_recorded THEN
    RAISE EXCEPTION 'This month''s membership renewal has already been recorded.';
  END IF;

  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
  VALUES (
    v_farmer,
    v_amount,
    'member_payment',
    COALESCE(p_note, 'Monthly membership renewal — ' || to_char(CURRENT_DATE, 'FMMonth YYYY')),
    v_farmer
  );

  SELECT total_contribution INTO v_new_total
  FROM member_capital_shares WHERE farmer_id = v_farmer;

  RETURN COALESCE(v_new_total, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_membership_renewal(TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- As a test farmer account, call the RPC once and confirm it succeeds:
--   SELECT record_membership_renewal();
-- Calling it again in the same calendar month should raise:
--   "This month's membership renewal has already been recorded."
-- Confirm the ledger row and updated total:
--   SELECT * FROM capital_contribution_events
--   WHERE farmer_id = auth.uid() ORDER BY created_at DESC LIMIT 1;
--   SELECT total_contribution, total_shares FROM member_capital_shares
--   WHERE farmer_id = auth.uid();
-- Confirm loan_policy_settings is now readable as a farmer:
--   SELECT monthly_dues_amount, minimum_capital_contribution FROM loan_policy_settings WHERE id = 1;
