-- ============================================================
-- SAGANA — Program Management: Loan/ROI outcome workflow
-- (dashboard_issue.md Issue 3 "twist" / Phase 8, design approved)
--
-- Extends the existing distribution lifecycle (enroll -> distribute ->
-- [confirm_program_return for Revenue Share]) with one new step: an
-- admin-recorded outcome check-in per distributed member.
--   - 'thriving' -> Revenue Share programs become eligible for the
--     EXISTING confirm_program_return() settlement (no new RPC needed —
--     that function already exists and is untouched here). Grant programs
--     just close out with no return expected.
--   - 'failed'   -> the distributed item becomes a farmer_loans entry via
--     the new convert_program_distribution_to_loan() RPC below, tagged
--     with source_program_id so the Loans tab can show a "From Program
--     Distribution" indicator. Repayment then goes through the EXISTING
--     record_loan_payment() flow — no new repayment mechanism.
--
-- Deliberately NOT built: automated monitoring/reminders. Recommendation
-- (not implemented) was to reuse program_activities/the calendar for
-- check-in scheduling — a UI/workflow choice, not a schema requirement.
-- ============================================================

BEGIN;

ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS distribution_outcome TEXT
  CHECK (distribution_outcome IN ('pending', 'thriving', 'failed')),
  ADD COLUMN IF NOT EXISTS outcome_recorded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS converted_loan_id UUID REFERENCES public.farmer_loans(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.program_members.distribution_outcome IS
  'Admin-recorded check-in on a distributed benefit: pending (not yet '
  'checked), thriving (eligible for confirm_program_return settlement), '
  'or failed (converted to a loan via convert_program_distribution_to_loan).';

-- Loans that originated from a failed program distribution carry a
-- reference back to the program, so the Loans tab can show "From Program
-- Distribution: <program name>" rather than relying on freeform notes text
-- (which an admin could later edit, losing the tag).
ALTER TABLE public.farmer_loans
  ADD COLUMN IF NOT EXISTS source_program_id UUID REFERENCES public.cooperative_programs(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.farmer_loans.source_program_id IS
  'Set only when this loan was created by converting a failed program '
  'distribution (see convert_program_distribution_to_loan). Null for every '
  'ordinary admin-issued loan.';

-- ─── convert_program_distribution_to_loan() ─────────────────────────────────
-- Wraps the existing issue_loan() RPC rather than duplicating its reference-
-- number generation / farmer_loan_items insertion. Deliberately omits
-- "inventoryItemId" from the item payload passed to issue_loan() — the
-- stock was already deducted at distribution time by
-- distribute_program_benefit(), and issue_loan() only deducts inventory
-- when inventoryItemId is present, so this avoids double-deducting the
-- same stock a second time.

CREATE OR REPLACE FUNCTION convert_program_distribution_to_loan(
  p_program_member_id UUID,
  p_monthly_payment NUMERIC,
  p_next_payment_date DATE,
  p_notes TEXT DEFAULT NULL
)
RETURNS TABLE (loan_id UUID, reference_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member       RECORD;
  v_item         RECORD;
  v_line_total   NUMERIC;
  v_items        JSONB;
  v_result       RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can convert a distribution to a loan';
  END IF;

  SELECT pm.*, cp.program_name INTO v_member
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.id = p_program_member_id
  FOR UPDATE OF pm;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program member not found';
  END IF;

  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'This member has not been distributed a benefit yet';
  END IF;

  IF v_member.converted_loan_id IS NOT NULL THEN
    RAISE EXCEPTION 'This distribution has already been converted to a loan';
  END IF;

  IF v_member.inventory_item_id IS NULL OR v_member.quantity_given IS NULL THEN
    RAISE EXCEPTION 'This distribution has no recorded item/quantity to convert';
  END IF;

  SELECT item_name, unit, COALESCE(unit_cost, 0) AS unit_cost
  INTO v_item
  FROM cooperative_inventory
  WHERE id = v_member.inventory_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The distributed inventory item no longer exists';
  END IF;

  v_line_total := v_member.quantity_given * v_item.unit_cost;

  v_items := jsonb_build_array(jsonb_build_object(
    'itemName',  v_item.item_name,
    'quantity',  v_member.quantity_given,
    'unit',      v_item.unit,
    'unitPrice', v_item.unit_cost,
    'lineTotal', v_line_total
  ));

  SELECT * INTO v_result FROM issue_loan(
    v_member.farmer_id,
    v_items,
    CURRENT_DATE,
    p_monthly_payment,
    p_next_payment_date,
    COALESCE(p_notes, 'From Program Distribution: ' || v_member.program_name),
    auth.uid(),
    NULL
  );

  UPDATE farmer_loans
  SET source_program_id = v_member.program_id
  WHERE id = v_result.loan_id;

  UPDATE program_members
  SET distribution_outcome = 'failed',
      outcome_recorded_at = NOW(),
      converted_loan_id = v_result.loan_id
  WHERE id = p_program_member_id;

  RETURN QUERY SELECT v_result.loan_id, v_result.reference_no;
END;
$$;

GRANT EXECUTE ON FUNCTION convert_program_distribution_to_loan(UUID, NUMERIC, DATE, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
