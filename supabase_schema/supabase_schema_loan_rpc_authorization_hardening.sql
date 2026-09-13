-- ============================================================
-- SAGANA — Loan RPC Authorization & Validation Hardening (v2)
--
-- Supersedes the earlier version of this migration, which was
-- written against supabase_schema_loan_atomic_operations.sql's
-- pre-idempotency signatures and would have regressed the
-- idempotency feature in supabase_schema_loan_idempotency.sql if
-- applied. This version is layered on top of the idempotency-aware
-- functions instead — every line of existing replay-check, advisory-
-- lock, and table-aliasing logic is preserved unchanged. The only
-- additions are: an admin-only check as the first statement in each
-- function body, and input validation before any row is written.
--
-- No signature changes were needed for issue_loan() or
-- record_loan_payment() — both keep their current idempotency-aware
-- parameter lists exactly, so CREATE OR REPLACE alone is correct
-- here (no DROP FUNCTION), same as supabase_schema_loan_idempotency
-- .sql's own note on this.
--
-- transition_overdue_loans() / notify_overdue_farmers() /
-- run_daily_loan_maintenance() are carried over unchanged from the
-- previous version of this migration — idempotency doesn't touch
-- any of these three, so nothing about them needed correcting.
-- ============================================================

-- ─── issue_loan() — admin check + item validation, idempotency preserved ──

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
  v_unit_price    NUMERIC;
  v_line_total    NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
  v_reference_no  TEXT;
  v_existing_id   UUID;
  v_existing_ref  TEXT;
BEGIN
  -- Admin check — first statement in the body, ahead of even the replay
  -- check below, so a non-admin caller learns nothing from either path.
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Input validation — runs before the replay check too. A replayed call
  -- carries the same p_items payload that already passed validation on
  -- its first attempt, so re-validating here is harmless; it just also
  -- protects the (unlikely) case of a replay with a tampered payload.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one loan item is required';
  END IF;

  IF p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity   := (v_item->>'quantity')::NUMERIC;
    v_unit_price := (v_item->>'unitPrice')::NUMERIC;
    v_line_total := (v_item->>'lineTotal')::NUMERIC;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero: %', v_item->>'itemName';
    END IF;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'Item unit price must not be negative: %', v_item->>'itemName';
    END IF;

    IF v_line_total IS NULL OR v_line_total < 0 THEN
      RAISE EXCEPTION 'Item line total must not be negative: %', v_item->>'itemName';
    END IF;
  END LOOP;

  -- Everything below this line is unchanged from
  -- supabase_schema_loan_idempotency.sql.

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

-- ─── record_loan_payment() — admin check + amount validation, idempotency preserved ──

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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may record loan payments';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  -- Everything below this line is unchanged from
  -- supabase_schema_loan_idempotency.sql.

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

-- ─── The remaining three functions — unchanged from the prior version of ──
-- ─── this migration; idempotency doesn't affect any of them.            ──

CREATE OR REPLACE FUNCTION transition_overdue_loans()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grace_days      INT;
  v_updated_count   INT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT grace_period_days INTO v_grace_days
  FROM loan_policy_settings WHERE id = 1;

  UPDATE farmer_loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND next_payment_date IS NOT NULL
    AND next_payment_date < (CURRENT_DATE - v_grace_days);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION transition_overdue_loans TO authenticated;

CREATE OR REPLACE FUNCTION notify_overdue_farmers()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode           TEXT;
  v_delay_days     INT;
  v_notified_count INT := 0;
  v_loan           RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT notification_timing_mode, notification_delay_days
  INTO v_mode, v_delay_days
  FROM loan_policy_settings WHERE id = 1;

  FOR v_loan IN
    SELECT id, farmer_id, reference_no, total_value, amount_paid, next_payment_date
    FROM farmer_loans
    WHERE status = 'overdue'
      AND notified_overdue_at IS NULL
      AND (
        v_mode = 'on_transition'
        OR (v_mode = 'delayed' AND next_payment_date <= CURRENT_DATE - v_delay_days)
        OR (v_mode = 'next_bod_meeting' AND CURRENT_DATE >= next_bod_saturday_after(next_payment_date))
      )
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    VALUES (
      v_loan.farmer_id,
      'loan',
      'Payment Reminder',
      'Your loan ' || v_loan.reference_no || ' has a missed payment. Outstanding balance: ₱' ||
      to_char(v_loan.total_value - v_loan.amount_paid, 'FM999,999,990.00') ||
      '. Please settle at the next BOD meeting or visit the cooperative office.',
      FALSE,
      NOW()
    );

    UPDATE farmer_loans SET notified_overdue_at = NOW() WHERE id = v_loan.id;
    v_notified_count := v_notified_count + 1;
  END LOOP;

  RETURN v_notified_count;
END;
$$;

GRANT EXECUTE ON FUNCTION notify_overdue_farmers TO authenticated;

CREATE OR REPLACE FUNCTION run_daily_loan_maintenance()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  PERFORM transition_overdue_loans();
  PERFORM notify_overdue_farmers();
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_loan_maintenance TO authenticated;