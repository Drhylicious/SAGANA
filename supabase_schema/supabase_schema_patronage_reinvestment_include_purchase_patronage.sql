-- ============================================================
-- SAGANA — Widen reinvest_patronage_capital() to include
-- Product Sales Program Patronage
--
-- reinvest_patronage_capital() (supabase_schema_patronage_capital_
-- reinvestment.sql) currently computes v_total_payout from only
-- actual_balik_tangkilik + actual_interest_on_capital — the Offer to
-- Cooperative (sales) side. It omits actual_purchase_patronage, added
-- later by supabase_schema_program_sales_patronage.sql for the Product
-- Sales Program (Option B) pool. As a result a farmer could only
-- reinvest the sales-side portion of their finalized payout even
-- though the farmer-facing UI (my_contribution_screen.dart) now shows
-- and offers to reinvest the full combined total. This migration
-- widens the function's payout calculation only — no schema change,
-- no new column, reinvested_amount already tracks generically against
-- whatever the combined total is.
-- ============================================================

BEGIN;

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

  -- Widened: now includes actual_purchase_patronage (Product Sales
  -- Program Patronage) alongside the original two Offer to Cooperative
  -- components, matching the combined total the farmer sees on-screen.
  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0)
                   + COALESCE(v_row.actual_interest_on_capital, 0)
                   + COALESCE(v_row.actual_purchase_patronage, 0);
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
-- Confirm a paid, purchase-patronage-bearing row's available amount now
-- includes it (should equal BT + interest + purchase patronage − reinvested):
--   SELECT year, actual_balik_tangkilik, actual_interest_on_capital,
--          actual_purchase_patronage, reinvested_amount,
--          (COALESCE(actual_balik_tangkilik,0) + COALESCE(actual_interest_on_capital,0)
--           + COALESCE(actual_purchase_patronage,0) - reinvested_amount) AS available_to_reinvest
--   FROM member_contributions
--   WHERE status = 'paid' AND actual_purchase_patronage > 0;
