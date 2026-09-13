-- ============================================================
-- SAGANA — Loan RPC Idempotency (Offline Sync Duplicate Prevention)
-- Adds a replay-safe idempotency key to issue_loan() and
-- record_loan_payment(), so a queued offline loan issuance or
-- payment that succeeds on the server but fails to be deleted
-- from the local Hive queue (app killed/connectivity dropped
-- between the RPC call returning and HiveService.removePendingQueueItem()
-- completing) cannot be replayed as a second, duplicate loan or
-- payment on the next sync cycle.
--
-- SyncService passes the queued item's own Hive key (entry.key —
-- stable for the lifetime of that queue entry, assigned once at
-- queue time, unchanged across retries) as this key. Direct
-- online calls (Issue New Loan / Record Payment screens, not
-- through the offline queue) have no replay risk and pass NULL,
-- which the UNIQUE constraint permits any number of times — only
-- non-null keys are deduplicated.
--
-- Preserves all existing atomic/stock-validation/advisory-lock
-- logic in both functions unchanged — the only addition is an
-- early "already applied, return the prior result" check before
-- that logic runs.
--
-- CORRECTED: both functions' RETURNS TABLE column names
-- (reference_no, running_balance) collide with identically-named
-- columns on farmer_loans / farmer_loan_payments, making
-- unqualified references to them ambiguous inside the function
-- body. Fixed by table-aliasing every query against those tables
-- in the idempotency replay checks and the reference-sequence
-- lookup. No signature change, so CREATE OR REPLACE alone (no
-- DROP FUNCTION) is sufficient to apply this correction.
-- ============================================================

ALTER TABLE farmer_loan_payments
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE;

ALTER TABLE farmer_loans
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE;

-- ─────────────────────────────────────────────────────────────
-- record_loan_payment — adds p_idempotency_key (7th param).
-- Signature is changing (6 args → 7), so the old 6-arg overload
-- must be dropped first — same reasoning already documented in
-- supabase_schema_loan_atomic_operations.sql for issue_loan's DROP.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS record_loan_payment(UUID, NUMERIC, DATE, DATE, TEXT, UUID);

CREATE OR REPLACE FUNCTION record_loan_payment(
  p_loan_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_next_payment_date_if_active DATE,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS TABLE (is_fully_paid BOOLEAN, running_balance NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_value      NUMERIC;
  v_current_paid     NUMERIC;
  v_new_paid         NUMERIC;
  v_running_balance  NUMERIC;
  v_is_fully_paid    BOOLEAN;
  v_existing_balance NUMERIC;
BEGIN
  -- Replay check: if this exact queued payment already landed on a
  -- prior sync attempt, return its recorded result instead of
  -- applying the payment a second time. running_balance = 0 is an
  -- exact stand-in for is_fully_paid here, not an approximation —
  -- both are derived from the same v_new_paid >= v_total_value
  -- comparison below, so they can never disagree.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT flp.running_balance INTO v_existing_balance
      FROM farmer_loan_payments flp
      WHERE flp.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT (v_existing_balance = 0), v_existing_balance;
      RETURN;
    END IF;
  END IF;

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
    loan_id, payment_date, amount_paid, running_balance, notes, recorded_by, idempotency_key
  ) VALUES (
    p_loan_id, p_payment_date, p_amount, v_running_balance, p_notes, p_recorded_by, p_idempotency_key
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

GRANT EXECUTE ON FUNCTION record_loan_payment(UUID, NUMERIC, DATE, DATE, TEXT, UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- issue_loan — adds p_idempotency_key (8th param), same pattern.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS issue_loan(UUID, JSONB, DATE, NUMERIC, DATE, TEXT, UUID);

CREATE OR REPLACE FUNCTION issue_loan(
  p_farmer_id UUID,
  p_items JSONB,
  p_issued_date DATE,
  p_monthly_payment NUMERIC,
  p_next_payment_date DATE,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
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
  v_existing_id   UUID;
  v_existing_ref  TEXT;
BEGIN
  -- Replay check — same reasoning as record_loan_payment above.
  -- Placed before the advisory lock / reference-number generation
  -- below, so a detected replay doesn't burn a reference-number
  -- slot for a loan that's already been issued.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT fl.id, fl.reference_no INTO v_existing_id, v_existing_ref
      FROM farmer_loans fl
      WHERE fl.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing_id, v_existing_ref;
      RETURN;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fl.reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans fl
  WHERE fl.reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
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

GRANT EXECUTE ON FUNCTION issue_loan(UUID, JSONB, DATE, NUMERIC, DATE, TEXT, UUID, TEXT) TO authenticated;
