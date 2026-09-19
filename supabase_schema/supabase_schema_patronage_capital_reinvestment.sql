-- ============================================================
-- SAGANA — Patronage Refund Reinvestment (Admin-Report tab review, Phase 8)
--
-- Lets a farmer reinvest all or part of their FINALIZED Balik-Tangkilik
-- payout (actual_balik_tangkilik + actual_interest_on_capital) as
-- additional capital share, from their own My Contribution screen —
-- after the distribution has already been recorded, per the organization's
-- explicit decision (post-distribution, farmer-initiated, partial or full).
--
-- The capital_contribution_events.source value 'patronage_capital' has
-- existed in the schema since Phase B (supabase_schema_phase_
-- b_member_id_capital_dob.sql) and already has display labels wired up
-- ("Patronage refund left as capital") in farmer_details_screen.dart, but
-- nothing has ever written a row with this source — this migration is the
-- first real write path for it.
--
-- reinvested_amount tracks how much of a given year's payout has already
-- been reinvested, so a farmer cannot reinvest more than they were
-- actually paid, and cannot reinvest the same payout twice across
-- multiple partial calls beyond its total.
-- ============================================================

BEGIN;

ALTER TABLE public.member_contributions
  ADD COLUMN IF NOT EXISTS reinvested_amount NUMERIC(12,2) NOT NULL DEFAULT 0
    CHECK (reinvested_amount >= 0);

COMMENT ON COLUMN public.member_contributions.reinvested_amount IS
  'How much of this year''s actual_balik_tangkilik + actual_interest_on_capital '
  'the farmer has already chosen to reinvest as capital share, via '
  'reinvest_patronage_capital(). Never exceeds the finalized payout total.';

-- ─── reinvest_patronage_capital ─────────────────────────────────────────────
-- Farmer-initiated (auth.uid() = the calling farmer, not admin). Atomic:
-- validates the payout is finalized and the amount is available, inserts
-- the ledger event, and updates reinvested_amount together or not at all.
CREATE OR REPLACE FUNCTION public.reinvest_patronage_capital(
  p_year INT,
  p_amount NUMERIC,
  p_note TEXT DEFAULT NULL
)
RETURNS NUMERIC  -- returns the amount still available to reinvest for that year
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer UUID := auth.uid();
  v_row RECORD;
  v_total_payout NUMERIC;
  v_available NUMERIC;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = v_farmer AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', v_farmer, p_year;
  END IF;
  IF v_row.status != 'paid' THEN
    RAISE EXCEPTION 'This year''s Balik-Tangkilik has not been finalized yet (status: %)', v_row.status;
  END IF;

  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0) + COALESCE(v_row.actual_interest_on_capital, 0);
  v_available := v_total_payout - v_row.reinvested_amount;

  IF p_amount > v_available THEN
    RAISE EXCEPTION 'Amount (%) exceeds what remains available to reinvest (%)', p_amount, v_available;
  END IF;

  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
  VALUES (
    v_farmer,
    p_amount,
    'patronage_capital',
    COALESCE(p_note, 'Reinvested from ' || p_year || ' Balik-Tangkilik payout'),
    v_farmer
  );

  UPDATE member_contributions
  SET reinvested_amount = reinvested_amount + p_amount
  WHERE farmer_id = v_farmer AND year = p_year;

  RETURN v_available - p_amount;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reinvest_patronage_capital(INT, NUMERIC, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Confirm the column exists and defaults correctly:
--   SELECT year, actual_balik_tangkilik, actual_interest_on_capital, reinvested_amount
--   FROM member_contributions WHERE status = 'paid';
--   -- expect reinvested_amount = 0 for every existing row (none reinvested yet)
