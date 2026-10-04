-- ============================================================
-- SAGANA — Let the farmer enter a custom amount when recording
-- their own Monthly Membership Renewal
--
-- record_membership_renewal() (supabase_schema_farmer_membership_
-- renewal.sql) previously always used the co-op's fixed monthly dues
-- policy amount. The organization decided a farmer should be able to
-- enter their own amount instead — e.g. catching up several months'
-- dues in one go — while still only being able to record ONE renewal
-- per calendar month (that guard is unchanged; only the amount is now
-- farmer-supplied instead of fixed).
--
-- This replaces the function with a new signature (p_amount first,
-- p_note second) — the old (p_note TEXT) — only signature is dropped
-- outright rather than left alongside it, so there's no ambiguity over
-- which overload a client call resolves to.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.record_membership_renewal(TEXT);

CREATE OR REPLACE FUNCTION public.record_membership_renewal(
  p_amount NUMERIC DEFAULT NULL,
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
  v_default_amount NUMERIC;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::date;
  v_already_recorded BOOLEAN;
  v_new_total NUMERIC;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT monthly_dues_amount INTO v_default_amount
  FROM loan_policy_settings WHERE id = 1;
  IF v_default_amount IS NULL OR v_default_amount <= 0 THEN
    v_default_amount := 100;
  END IF;

  -- Farmer-supplied amount if given (e.g. catching up multiple months'
  -- dues at once); falls back to the official monthly due otherwise.
  v_amount := COALESCE(p_amount, v_default_amount);
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
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

GRANT EXECUTE ON FUNCTION public.record_membership_renewal(NUMERIC, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- As a test farmer account, record a custom amount (e.g. catching up
-- 3 months at ₱100 each = ₱300):
--   SELECT record_membership_renewal(300);
-- Confirm the ledger shows exactly ₱300, not the policy default:
--   SELECT amount, note FROM capital_contribution_events
--   WHERE farmer_id = auth.uid() ORDER BY created_at DESC LIMIT 1;
-- Confirm a second call this same month is still rejected regardless
-- of amount:
--   SELECT record_membership_renewal(50);
--   -- expect: "This month's membership renewal has already been recorded."
