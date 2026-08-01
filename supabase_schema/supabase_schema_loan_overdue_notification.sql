-- ============================================================
-- SAGANA — Overdue Loan Notification
-- Notifies farmers when their loan transitions to overdue, on a
-- timing schedule controlled by loan_policy_settings. Builds on
-- top of supabase_schema_loan_overdue_transition.sql — this file
-- adds the notification half of daily loan maintenance.
--
-- DEDUP: farmer_loans.notified_overdue_at tracks whether a loan's
-- current overdue occurrence has already been notified, since
-- notifications has no reference_id/reference_type column to
-- link a notification back to a specific loan. A targeted column
-- here (vs. generalizing notifications itself) mirrors how the
-- schema already tracks similar single-purpose flags elsewhere.
-- Reset to NULL in admin_loan_repository.dart whenever a loan
-- leaves overdue status (recordPayment, markLoanAsPaid), so a
-- loan that becomes overdue again later gets notified again.
--
-- TIMING: controlled by loan_policy_settings.notification_timing_mode
-- (on_transition | delayed | next_bod_meeting) — see that table's
-- comments for what each mode means. Defaults to 'on_transition'.
-- PROVISIONAL until SP3's actual preference is confirmed on-site.
-- ============================================================

-- ─── Policy settings (single-row config table) ─────────────────────────────

CREATE TABLE IF NOT EXISTS public.loan_policy_settings (
  id                        INT         PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  grace_period_days         INT         NOT NULL DEFAULT 1,
  notification_timing_mode  TEXT        NOT NULL DEFAULT 'on_transition'
                             CHECK (notification_timing_mode IN ('on_transition', 'delayed', 'next_bod_meeting')),
  notification_delay_days   INT         NOT NULL DEFAULT 3,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.loan_policy_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.loan_policy_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "loan_policy_settings: admin reads"
  ON public.loan_policy_settings FOR SELECT
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));

-- Deliberately no INSERT/UPDATE policy yet — matches the "no settings UI
-- until after the field visit" decision. Adjust via Supabase Studio for now.

-- ─── Dedup column on farmer_loans ───────────────────────────────────────────

ALTER TABLE public.farmer_loans
  ADD COLUMN IF NOT EXISTS notified_overdue_at TIMESTAMPTZ;

-- ─── Shared BOD-Saturday helper ─────────────────────────────────────────────
-- Mirrors the Dart logic in AdminLoanRepository._nextBodSaturdayAfter /
-- _firstSaturdayOf exactly, so both sides of the app agree on what
-- "next BOD Saturday" means.

CREATE OR REPLACE FUNCTION next_bod_saturday_after(p_date DATE)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_candidate DATE;
BEGIN
  v_candidate := date_trunc('month', p_date)::DATE;
  WHILE EXTRACT(DOW FROM v_candidate) != 6 LOOP
    v_candidate := v_candidate + 1;
  END LOOP;
  IF v_candidate <= p_date THEN
    v_candidate := (date_trunc('month', p_date) + INTERVAL '1 month')::DATE;
    WHILE EXTRACT(DOW FROM v_candidate) != 6 LOOP
      v_candidate := v_candidate + 1;
    END LOOP;
  END IF;
  RETURN v_candidate;
END;
$$;

-- ─── Notification function ──────────────────────────────────────────────────

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

-- ─── Daily maintenance wrapper ───────────────────────────────────────────────
-- Replaces the single-purpose cron job from supabase_schema_loan_overdue_
-- transition.sql with one that runs both steps in order: status
-- transition, then notification.

CREATE OR REPLACE FUNCTION run_daily_loan_maintenance()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM transition_overdue_loans();
  PERFORM notify_overdue_farmers();
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_loan_maintenance TO authenticated;

SELECT cron.unschedule('transition-overdue-loans-daily');
SELECT cron.schedule('run-daily-loan-maintenance', '5 0 * * *', $$ SELECT run_daily_loan_maintenance(); $$);
