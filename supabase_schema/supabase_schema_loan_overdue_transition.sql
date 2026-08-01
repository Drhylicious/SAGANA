-- ============================================================
-- SAGANA — Overdue Loan Transition
-- Automates active → overdue when a scheduled BOD Saturday
-- payment (farmer_loans.next_payment_date) has passed without
-- a payment being recorded.
--
-- GRACE PERIOD: currently 1 day (see v_grace_period_days below),
-- matching the literal schema comment on farmer_loans.status
-- ("missed at least one BOD Saturday payment cycle"). This is a
-- PROVISIONAL value — SP3's actual collection leniency has not
-- been confirmed on-site. Adjust v_grace_period_days once that's
-- known; nothing else needs to change.
--
-- Deliberately does NOT touch next_payment_date on transition —
-- the UI (_AdminLoanCard) reads next_payment_date as the
-- "Overdue since {date}" label when status = 'overdue', so the
-- missed date must be preserved, not advanced.
-- ============================================================

CREATE OR REPLACE FUNCTION transition_overdue_loans()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grace_period_days INT := 1; -- PROVISIONAL — confirm real BOD grace policy on field visit
  v_updated_count INT;
BEGIN
  UPDATE farmer_loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND next_payment_date IS NOT NULL
    AND next_payment_date < (CURRENT_DATE - v_grace_period_days);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION transition_overdue_loans TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Daily schedule via pg_cron. Requires the extension enabled in this project
-- (Database → Extensions in the Supabase dashboard if this errors below).
-- Runs 00:05 UTC = 08:05 AM Philippine time (UTC+8) — early enough to be
-- accurate before an admin's typical morning check-in.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  'transition-overdue-loans-daily',
  '5 0 * * *',
  $$ SELECT transition_overdue_loans(); $$
);