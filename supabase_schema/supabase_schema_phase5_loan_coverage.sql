-- ============================================================
-- SAGANA — Phase 5: Loans notification coverage
-- ============================================================
-- issue_loan and record_loan_payment had zero notification coverage —
-- a farmer only ever heard about their loan once it went overdue
-- (notify_overdue_farmers, already working). This adds:
--   1. issue_loan            → notify the farmer a loan was issued
--   2. record_loan_payment   → notify the farmer a payment was recorded
--
-- Both functions support idempotent replay (p_idempotency_key) with an
-- early RETURN on a duplicate call — the new notification inserts are
-- placed only in the real, first-time execution path, never in the
-- early-return replay branch, so a retried call can't double-notify.
--
-- type='loan' matches notify_overdue_farmers' existing type for this
-- module.
-- ============================================================

-- ─── 1. issue_loan → notify the farmer ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.issue_loan(p_farmer_id uuid, p_items jsonb, p_issued_date date, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
RETURNS TABLE(loan_id uuid, reference_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
  v_contribution  NUMERIC;
  v_minimum       NUMERIC;
  v_farmer_status TEXT;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Farmer membership-status gate (Admin-Loan Issue 1.3) — the target
  -- farmer must be an active member. Checked before the capital-share
  -- gate so a non-member gets a membership-specific error rather than a
  -- misleading capital-contribution one.
  SELECT status INTO v_farmer_status
  FROM user_roles
  WHERE user_id = p_farmer_id AND role = 'farmer';

  IF v_farmer_status IS NULL THEN
    RAISE EXCEPTION 'Farmer account not found';
  END IF;

  IF v_farmer_status <> 'active' THEN
    RAISE EXCEPTION 'Farmer is not an active cooperative member (status: %) and is not eligible for a loan', v_farmer_status;
  END IF;

  -- Capital-share loan eligibility — HARD block (Issue 4d). Runs before
  -- the replay check so a replayed call re-verifies too. The Issue-Loan
  -- screen shows its own warning banner; this is the backend authority.
  SELECT COALESCE(mcs.total_contribution, 0) INTO v_contribution
  FROM member_capital_shares mcs
  WHERE mcs.farmer_id = p_farmer_id;
  v_contribution := COALESCE(v_contribution, 0);

  SELECT COALESCE(lps.minimum_capital_contribution, 2000) INTO v_minimum
  FROM loan_policy_settings lps
  WHERE lps.id = 1;
  v_minimum := COALESCE(v_minimum, 2000);

  IF v_contribution < v_minimum THEN
    RAISE EXCEPTION
      'Farmer has not met the minimum capital contribution of % required for a loan (current contribution: %)',
      v_minimum, v_contribution;
  END IF;

  -- Input validation.
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    p_farmer_id, 'loan', 'Loan Issued',
    'A new loan (' || v_reference_no || ') worth ₱' ||
      to_char(v_total_value, 'FM999,999,990.00') || ' has been issued to you.',
    FALSE, NOW()
  );

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$$;

-- ─── 2. record_loan_payment → notify the farmer ─────────────────────────────

CREATE OR REPLACE FUNCTION public.record_loan_payment(p_loan_id uuid, p_amount numeric, p_payment_date date, p_next_payment_date_if_active date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
RETURNS TABLE(is_fully_paid boolean, running_balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_value      NUMERIC;
  v_current_paid     NUMERIC;
  v_new_paid         NUMERIC;
  v_running_balance  NUMERIC;
  v_is_fully_paid    BOOLEAN;
  v_existing_balance NUMERIC;
  v_farmer_id        UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may record loan payments';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  -- Everything below this line is unchanged from
  -- supabase_schema_loan_idempotency.sql, except the added farmer_id
  -- lookup and the new notification insert at the end.

  IF p_idempotency_key IS NOT NULL THEN
    SELECT flp.running_balance INTO v_existing_balance
      FROM farmer_loan_payments flp
      WHERE flp.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT (v_existing_balance = 0), v_existing_balance;
      RETURN;
    END IF;
  END IF;

  SELECT total_value, COALESCE(amount_paid, 0), farmer_id
    INTO v_total_value, v_current_paid, v_farmer_id
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'loan',
    CASE WHEN v_is_fully_paid THEN 'Loan Fully Paid' ELSE 'Payment Recorded' END,
    'Your payment of ₱' || to_char(p_amount, 'FM999,999,990.00') || ' was recorded.' ||
      CASE WHEN v_is_fully_paid
        THEN ' Your loan is now fully paid off. Thank you!'
        ELSE ' Remaining balance: ₱' || to_char(v_running_balance, 'FM999,999,990.00') || '.'
      END,
    FALSE, NOW()
  );

  RETURN QUERY SELECT v_is_fully_paid, v_running_balance;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT proname, prosrc ILIKE '%INSERT INTO notifications%' AS has_notify
-- FROM pg_proc WHERE proname IN ('issue_loan', 'record_loan_payment');
-- -- expect both TRUE
--
-- In-app: issue a test loan and record a payment against it, confirm the
-- farmer receives both notifications, and confirm a retried
-- (idempotent-replay) call does NOT create a duplicate notification.
-- ============================================================
