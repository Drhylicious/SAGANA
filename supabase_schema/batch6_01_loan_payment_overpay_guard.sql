-- ─────────────────────────────────────────────────────────────────────────────
-- batch6_01_loan_payment_overpay_guard.sql
-- Batch 6 (6.4) of the approved implementation plan.
--
-- Offline loan payments are queued on the device and sent by Sync. By the time
-- a queued payment is sent, the loan may already be paid down, so the server
-- must refuse a payment larger than what is still owed. A refused payment
-- stays in the Unsynced queue with the reason shown.
--
-- Before this, record_loan_payment accepted any amount and clamped the stored
-- balance at zero. Online payments are not affected: the app already caps the
-- amount at the remaining balance (after the overpayment confirmation).
--
-- Base: the definition in supabase_schema_role_based_staff_access.sql (the
-- latest in the repo). Compare it with the live definition first:
--   select pg_get_functiondef('public.record_loan_payment'::regproc);
-- Signature and return type are unchanged.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.record_loan_payment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_next_payment_date_if_active date,
  p_notes text DEFAULT NULL::text,
  p_recorded_by uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text
)
RETURNS TABLE(is_fully_paid boolean, running_balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_total_value      NUMERIC;
  v_current_paid     NUMERIC;
  v_new_paid         NUMERIC;
  v_running_balance  NUMERIC;
  v_is_fully_paid    BOOLEAN;
  v_existing_balance NUMERIC;
  v_farmer_id        UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins may record loan payments';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  -- A repeated request with the same key returns the original result and is
  -- not applied twice (offline replays always carry the key).
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

  -- New in Batch 6: refuse a payment larger than the balance still owed,
  -- read under the row lock so a concurrent payment cannot slip past it.
  IF p_amount > GREATEST(v_total_value - v_current_paid, 0) THEN
    RAISE EXCEPTION 'Payment of ₱% is more than the remaining balance of ₱%',
      to_char(p_amount, 'FM999,999,990.00'),
      to_char(GREATEST(v_total_value - v_current_paid, 0), 'FM999,999,990.00');
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'loan',
    CASE WHEN v_is_fully_paid THEN 'Loan Fully Paid' ELSE 'Payment Recorded' END,
    'Your payment of ₱' || to_char(p_amount, 'FM999,999,990.00') || ' was recorded.' ||
      CASE WHEN v_is_fully_paid
        THEN ' Your loan is now fully paid off. Thank you!'
        ELSE ' Remaining balance: ₱' || to_char(v_running_balance, 'FM999,999,990.00') || '.'
      END,
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_is_fully_paid, v_running_balance;
END;
$function$;

-- ─── Verification (run after applying) ───────────────────────────────────────
--   -- a payment above the balance is refused, and nothing is written
--   select public.record_loan_payment('<loan>', <balance + 1>, current_date,
--                                     current_date + 30, null, null, null);
--   -- expect: "Payment of ₱... is more than the remaining balance of ₱..."
--   -- a payment equal to the balance is accepted
--   select count(*) from farmer_loan_payments where loan_id = '<loan>';  -- unchanged after the refused call
