-- ============================================================
-- SAGANA — Upcoming Loan Payment Notification
-- Companion to supabase_schema_loan_overdue_notification.sql, which only
-- ever notified a farmer once a loan had ALREADY gone overdue. There was
-- no notification for an upcoming-but-not-yet-due payment at all — that
-- information previously only ever surfaced as a Farmer Recent Activity
-- entry ("Loan Payment Due"), which was removed from Recent Activity
-- entirely (it's passive, Admin-issued information, not a Farmer action).
-- This migration is what replaces it: the same information, delivered
-- exclusively through Notifications instead.
--
-- DEDUP: mirrors notified_overdue_at's reasoning, but keyed on the due
-- DATE itself (due_soon_notified_for_date) rather than a plain timestamp
-- flag — a loan's next_payment_date moves forward every time a payment
-- is recorded, so comparing against the date already notified for (not
-- just whether *any* notification was ever sent) means a new due date
-- always gets its own fresh notification with no separate reset step
-- required elsewhere in the codebase.
--
-- WINDOW: 7 days, matching the existing Priority Card "due soon" business
-- rule already documented in home_tab.md Section 5/14, so a farmer sees
-- the same urgency window in both Notifications and the Priority Card.
-- ============================================================

ALTER TABLE public.farmer_loans
  ADD COLUMN IF NOT EXISTS due_soon_notified_for_date DATE;

CREATE OR REPLACE FUNCTION notify_upcoming_loan_payments()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notified_count INT := 0;
  v_loan           RECORD;
BEGIN
  FOR v_loan IN
    SELECT id, farmer_id, reference_no, monthly_payment, next_payment_date
    FROM farmer_loans
    WHERE status = 'active'
      AND next_payment_date IS NOT NULL
      AND next_payment_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
      AND due_soon_notified_for_date IS DISTINCT FROM next_payment_date
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    VALUES (
      v_loan.farmer_id,
      'loan',
      'Loan Payment Due Soon',
      'Your loan ' || v_loan.reference_no || ' has an installment of ₱' ||
      to_char(v_loan.monthly_payment, 'FM999,999,990.00') ||
      ' due on ' || to_char(v_loan.next_payment_date, 'FMMonth DD, YYYY') || '.',
      FALSE,
      NOW()
    );

    UPDATE farmer_loans
    SET due_soon_notified_for_date = v_loan.next_payment_date
    WHERE id = v_loan.id;

    v_notified_count := v_notified_count + 1;
  END LOOP;

  RETURN v_notified_count;
END;
$$;

GRANT EXECUTE ON FUNCTION notify_upcoming_loan_payments TO authenticated;

-- ─── Extend the existing daily maintenance wrapper ──────────────────────────
-- Reuses the same cron job already scheduled by
-- supabase_schema_loan_overdue_notification.sql ('run-daily-loan-
-- maintenance') — no new schedule needed, just one more step in the same
-- daily run.

CREATE OR REPLACE FUNCTION run_daily_loan_maintenance()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM transition_overdue_loans();
  PERFORM notify_overdue_farmers();
  PERFORM notify_upcoming_loan_payments();
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_loan_maintenance TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) SELECT run_daily_loan_maintenance();
--    -- runs without error
--
-- 2) As a farmer with an active loan whose next_payment_date falls within
--    the next 7 days:
--    SELECT notify_upcoming_loan_payments();
--    -- expect 1, and a new row in notifications for that farmer
--    SELECT * FROM notifications WHERE user_id = '<that farmer's id>'
--      AND type = 'loan' ORDER BY created_at DESC LIMIT 1;
--
-- 3) Run notify_upcoming_loan_payments() again immediately:
--    -- expect 0 (already notified for this exact due date — dedup working)
--
-- 4) After that loan's payment is recorded (moving next_payment_date
--    forward), run notify_upcoming_loan_payments() again once the new
--    date falls within the 7-day window:
--    -- expect a fresh notification, since due_soon_notified_for_date no
--    -- longer matches the new next_payment_date
