-- ============================================================
-- SAGANA — Atomic Loan Payment & Issuance
-- Replaces AdminLoanRepository's multi-step client-side writes
-- for recordPayment() and issueLoan() with single-transaction
-- RPCs, so a connectivity drop mid-operation (the app's core
-- offline-first failure mode) can no longer leave farmer_loans,
-- farmer_loan_payments, farmer_loan_items, cooperative_inventory,
-- or inventory_transactions out of sync with each other.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- record_loan_payment
-- Re-reads the loan's live balance under a row lock (FOR UPDATE),
-- so two admins recording a payment on the same loan at the same
-- moment can no longer race and clobber each other's contribution
-- — the same class of concurrency protection decrement_inventory_
-- stock already gave loan issuance, now applied to payments too.
--
-- next_payment_date scheduling stays in Dart (BodSchedule.after())
-- rather than being reimplemented here, to avoid the same business
-- rule living in two languages. The caller passes the candidate
-- date; this function only decides WHETHER to apply it, based on
-- its own live is_fully_paid determination.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION record_loan_payment(
  p_loan_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_next_payment_date_if_active DATE,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL
)
RETURNS TABLE (is_fully_paid BOOLEAN, running_balance NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_value     NUMERIC;
  v_current_paid    NUMERIC;
  v_new_paid        NUMERIC;
  v_running_balance NUMERIC;
  v_is_fully_paid   BOOLEAN;
BEGIN
  SELECT total_value, COALESCE(amount_paid, 0)
    INTO v_total_value, v_current_paid
    FROM farmer_loans
    WHERE id = p_loan_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan % not found', p_loan_id;
  END IF;

  v_new_paid        := v_current_paid + p_amount;
  v_running_balance := GREATEST(v_total_value - v_new_paid, 0);
  v_is_fully_paid   := v_new_paid >= v_total_value;

  INSERT INTO farmer_loan_payments (
    loan_id, payment_date, amount_paid, running_balance, notes, recorded_by
  ) VALUES (
    p_loan_id, p_payment_date, p_amount, v_running_balance, p_notes, p_recorded_by
  );

  UPDATE farmer_loans
  SET amount_paid         = v_new_paid,
      status              = CASE WHEN v_is_fully_paid THEN 'paid' ELSE 'active' END,
      notified_overdue_at = NULL,
      next_payment_date   = CASE WHEN v_is_fully_paid
                               THEN next_payment_date
                               ELSE p_next_payment_date_if_active
                             END
  WHERE id = p_loan_id;

  RETURN QUERY SELECT v_is_fully_paid, v_running_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION record_loan_payment TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- issue_loan
-- Inserts the loan, its items, and every inventory movement in
-- one transaction. Per JD's decision: if ANY item lacks enough
-- cooperative_inventory.quantity_on_hand, the entire loan is
-- rejected atomically — nothing is written, including the
-- farmer_loans/farmer_loan_items rows already inserted earlier
-- in this same function call. This intentionally does NOT reuse
-- decrement_inventory_stock() (see supabase_schema_loan_inventory
-- _link.sql) — that function floors at zero silently, which is
-- the exact behavior this replaces for the loan-issuance path.
-- decrement_inventory_stock() itself is left in place in case
-- anything else still calls it; worth confirming that before
-- ever removing it.
--
-- DROP below is required, not optional: the reference-number-race
-- fix removed p_reference_no from the parameter list, so this is a
-- different signature than the original issue_loan(). CREATE OR
-- REPLACE only replaces a function with an IDENTICAL parameter
-- list — with a changed signature it silently creates a second,
-- overloaded issue_loan() instead of replacing the first, which is
-- what caused "function name is not unique" on GRANT. Dropping the
-- old 8-arg overload by its exact signature first prevents that.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS issue_loan(UUID, TEXT, JSONB, DATE, NUMERIC, DATE, TEXT, UUID);

CREATE OR REPLACE FUNCTION issue_loan(
  p_farmer_id UUID,
  p_items JSONB,
  p_issued_date DATE,
  p_monthly_payment NUMERIC,
  p_next_payment_date DATE,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL
)
RETURNS TABLE (loan_id UUID, reference_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loan_id       UUID;
  v_total_value   NUMERIC := 0;
  v_item          JSONB;
  v_inventory_id  UUID;
  v_quantity      NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
  v_reference_no  TEXT;
BEGIN
  -- Serialize reference-number generation per year, for the lifetime of
  -- this transaction only (auto-released on commit/rollback) — closes
  -- the race where two concurrent issuances could both read the same
  -- "max existing reference" and compute the same next number.
  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans
  WHERE reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date
  )
  RETURNING id INTO v_loan_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total)
    VALUES (
      v_loan_id,
      v_item->>'itemName',
      (v_item->>'quantity')::NUMERIC,
      v_item->>'unit',
      (v_item->>'unitPrice')::NUMERIC,
      (v_item->>'lineTotal')::NUMERIC
    );

    v_inventory_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    IF v_inventory_id IS NOT NULL THEN
      v_quantity := (v_item->>'quantity')::NUMERIC;

      SELECT quantity_on_hand, item_name INTO v_available, v_item_name
        FROM cooperative_inventory
        WHERE id = v_inventory_id
        FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item % no longer exists', v_inventory_id;
      END IF;

      IF v_available < v_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_item_name, v_available, v_quantity;
      END IF;

      UPDATE cooperative_inventory
      SET quantity_on_hand = quantity_on_hand - v_quantity
      WHERE id = v_inventory_id;

      INSERT INTO inventory_transactions (
        inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
      ) VALUES (
        v_inventory_id, 'loan_issued', -v_quantity, v_loan_id, 'loan', p_recorded_by
      );
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$$;

GRANT EXECUTE ON FUNCTION issue_loan(UUID, JSONB, DATE, NUMERIC, DATE, TEXT, UUID) TO authenticated;