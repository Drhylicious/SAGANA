-- ============================================================
-- SAGANA — Balik-Tangkilik payout decision: request + admin
-- confirmation workflow
--
-- Closes a real double-processing risk: "Keep as Cash" previously wrote
-- nothing anywhere, so nothing prevented a farmer from later also using
-- "Add to Capital" for the same already-cash-claimed money (the reverse
-- was already safe — reinvest_patronage_capital() tracked
-- reinvested_amount correctly — but cash had no equivalent tracking at
-- all). Reworked to mirror the existing farmer-requests/admin-confirms
-- shape already used by program_product_purchases (request_program_
-- purchase() -> pending -> confirm_program_purchase()) and
-- cooperative_purchase_offers (pending -> confirm_cooperative_offer()) —
-- not a new pattern invented for this feature.
--
-- Design: exactly ONE payout decision per farmer per year. Submitting a
-- decision (cash or capital) immediately locks that year against any
-- further decision, whether pending or already confirmed. Admin
-- approval is required for both sides:
--   - Capital: approval is the moment the capital transfer actually
--     happens (this replaces reinvest_patronage_capital() as the write
--     path — see the REVOKE at the bottom).
--   - Cash: approval performs no computation (the cooperative still
--     hands over physical cash outside the app, unchanged) — it is a
--     checklist confirmation that the payout was actually handled,
--     matching this app's standing rule that a real-money event only
--     counts once admin confirms it happened.
-- ============================================================

BEGIN;

ALTER TABLE public.member_contributions
  ADD COLUMN IF NOT EXISTS payout_decision TEXT
    CHECK (payout_decision IN ('pending_cash', 'pending_capital', 'cash_confirmed', 'capital_confirmed')),
  ADD COLUMN IF NOT EXISTS payout_decision_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS payout_decision_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payout_decision_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payout_decision_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.member_contributions.payout_decision IS
  'Null until the farmer submits a choice for this year''s finalized payout. '
  'pending_cash/pending_capital = awaiting admin confirmation; '
  'cash_confirmed/capital_confirmed = finalized. Exactly one decision per '
  'farmer per year — submitting locks out the other option immediately, '
  'not just after admin approval.';

-- ─── request_payout_decision ─────────────────────────────────────────────────
-- Farmer-initiated (auth.uid() = the calling farmer). Records the choice as
-- PENDING only — no money moves and no capital_contribution_events row is
-- written here. p_decision = 'cash' claims the entire remaining available
-- amount (cash needs no partial split, since nothing is computed for it);
-- p_decision = 'capital' requires p_amount, which may be less than the full
-- available amount.
CREATE OR REPLACE FUNCTION public.request_payout_decision(
  p_year INT,
  p_decision TEXT,
  p_amount NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer UUID := auth.uid();
  v_row RECORD;
  v_total_payout NUMERIC;
  v_available NUMERIC;
  v_amount NUMERIC;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_decision NOT IN ('cash', 'capital') THEN
    RAISE EXCEPTION 'Decision must be ''cash'' or ''capital''';
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
  IF v_row.payout_decision IS NOT NULL THEN
    RAISE EXCEPTION 'A payout decision has already been submitted for this year (%)', v_row.payout_decision;
  END IF;

  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0)
                   + COALESCE(v_row.actual_interest_on_capital, 0)
                   + COALESCE(v_row.actual_purchase_patronage, 0);
  v_available := v_total_payout - COALESCE(v_row.reinvested_amount, 0);

  IF v_available <= 0 THEN
    RAISE EXCEPTION 'Nothing remains available to decide on for this year';
  END IF;

  IF p_decision = 'cash' THEN
    v_amount := v_available;
  ELSE
    IF p_amount IS NULL OR p_amount <= 0 THEN
      RAISE EXCEPTION 'Amount must be greater than zero';
    END IF;
    IF p_amount > v_available THEN
      RAISE EXCEPTION 'Amount (%) exceeds what remains available (%)', p_amount, v_available;
    END IF;
    v_amount := p_amount;
  END IF;

  UPDATE member_contributions
  SET payout_decision = CASE WHEN p_decision = 'cash' THEN 'pending_cash' ELSE 'pending_capital' END,
      payout_decision_amount = v_amount,
      payout_decision_requested_at = NOW()
  WHERE farmer_id = v_farmer AND year = p_year;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_payout_decision(INT, TEXT, NUMERIC) TO authenticated;

-- ─── confirm_payout_decision ─────────────────────────────────────────────────
-- Admin-only. For a pending capital decision, this IS the moment the
-- capital transfer actually happens — same ledger write
-- reinvest_patronage_capital() used to perform directly, now gated
-- behind admin confirmation instead of the farmer's own request.
CREATE OR REPLACE FUNCTION public.confirm_payout_decision(
  p_farmer_id UUID,
  p_year INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can confirm a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'No pending payout decision to confirm (current: %)', v_row.payout_decision;
  END IF;

  IF v_row.payout_decision = 'pending_capital' THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
    VALUES (
      p_farmer_id,
      v_row.payout_decision_amount,
      'patronage_capital',
      'Reinvested from ' || p_year || ' Balik-Tangkilik payout (admin-confirmed)',
      v_admin
    );

    UPDATE member_contributions
    SET reinvested_amount = COALESCE(reinvested_amount, 0) + v_row.payout_decision_amount,
        payout_decision = 'capital_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  ELSE
    UPDATE member_contributions
    SET payout_decision = 'cash_confirmed',
        payout_decision_confirmed_at = NOW(),
        payout_decision_confirmed_by = v_admin
    WHERE farmer_id = p_farmer_id AND year = p_year;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_payout_decision(UUID, INT) TO authenticated;

-- ─── reject_payout_decision ───────────────────────────────────────────────────
-- Admin-only. Clears a still-pending decision back to null so the farmer
-- can submit a corrected one — mirrors decline_cooperative_offer()'s role
-- for the equivalent case. Only reachable while pending (a confirmed
-- decision, especially capital_confirmed, has already moved real money
-- into capital_contribution_events and is not reversible by this
-- function).
CREATE OR REPLACE FUNCTION public.reject_payout_decision(
  p_farmer_id UUID,
  p_year INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_row RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin) THEN
    RAISE EXCEPTION 'Only an admin can reject a payout decision.';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = p_farmer_id AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', p_farmer_id, p_year;
  END IF;
  IF v_row.payout_decision NOT IN ('pending_cash', 'pending_capital') THEN
    RAISE EXCEPTION 'Only a pending decision can be rejected (current: %)', v_row.payout_decision;
  END IF;

  UPDATE member_contributions
  SET payout_decision = NULL,
      payout_decision_amount = NULL,
      payout_decision_requested_at = NULL
  WHERE farmer_id = p_farmer_id AND year = p_year;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_payout_decision(UUID, INT) TO authenticated;

-- ─── reinvest_patronage_capital() is now superseded ─────────────────────────
-- Capital additions must go through the admin-confirmed workflow above.
-- Revoking EXECUTE (rather than leaving it reachable) matters for the same
-- reason record_membership_renewal() was dropped entirely in the earlier
-- renewal-revert migration: a farmer could otherwise still call the old
-- immediate-write RPC directly against the API, bypassing admin
-- confirmation entirely even with the app UI no longer offering it.
REVOKE EXECUTE ON FUNCTION public.reinvest_patronage_capital(INT, NUMERIC, TEXT) FROM authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- As the test farmer, submit a decision (e.g. cash) and confirm it's
-- recorded as pending, not yet moving any money:
--   SELECT request_payout_decision(2026, 'cash');
--   SELECT payout_decision, payout_decision_amount, payout_decision_requested_at
--   FROM member_contributions WHERE farmer_id = auth.uid() AND year = 2026;
--   -- expect: payout_decision = 'pending_cash'
--
-- Confirm submitting a second decision for the same year is blocked:
--   SELECT request_payout_decision(2026, 'capital', 100);
--   -- expect: "A payout decision has already been submitted for this year (pending_cash)"
--
-- As an admin account, confirm the pending decision:
--   SELECT confirm_payout_decision('<that farmer's user_id>', 2026);
--   SELECT payout_decision, payout_decision_confirmed_at FROM member_contributions
--   WHERE farmer_id = '<that farmer's user_id>' AND year = 2026;
--   -- expect: payout_decision = 'cash_confirmed'
--
-- Confirm the old direct RPC is no longer callable by a farmer:
--   SELECT reinvest_patronage_capital(2026, 100);
--   -- expect: a permission-denied error, not a successful reinvestment
