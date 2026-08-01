-- ============================================================
-- SAGANA — Loan Overdue Automation
-- Automates active → overdue transitions and farmer notification,
-- both governed by configurable policy in loan_policy_settings
-- rather than hardcoded values.
--
-- PROVISIONAL DEFAULTS — grace_period_days and
-- notification_timing_mode below reflect our best guess prior to
-- visiting SP3 in person. Update via a plain UPDATE statement on
-- loan_policy_settings once their real collection policy is
-- confirmed — no code or redeploy needed.
-- ============================================================

-- ─── Policy settings (single row) ──────────────────────────────────────────

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

DROP POLICY IF EXISTS "loan_policy_settings: admin reads" ON public.loan_policy_settings;

CREATE POLICY "loan_policy_settings: admin reads"
  ON public.loan_policy_settings FOR SELECT
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));

-- ─── Dedup tracking column ──────────────────────────────────────────────────

ALTER TABLE public.farmer_loans
  ADD COLUMN IF NOT EXISTS notified_overdue_at TIMESTAMPTZ;

-- ─── Shared BOD-Saturday helper (SQL side) ─────────────────────────────────
-- Mirrors BodSchedule.after() in bod_schedule_utils.dart exactly.

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

-- ─── Status transition: active → overdue ───────────────────────────────────

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

-- ─── Farmer notification ────────────────────────────────────────────────────

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

-- ─── Daily wrapper ──────────────────────────────────────────────────────────
-- This function is always created regardless of plan — it's the thing that
-- actually needs to run daily, however that ends up being triggered. It can
-- be invoked three ways depending on what your Supabase plan supports:
--   1. pg_cron (below) — requires Pro plan or above, since pg_cron needs a
--      long-running background worker that Supabase only enables on paid
--      projects. Free-tier projects will not be able to enable it.
--   2. An external scheduler (GitHub Actions on a schedule, cron-job.org,
--      etc.) hitting a Supabase Edge Function that calls
--      `supabase.rpc('run_daily_loan_maintenance')`. Works on any plan.
--   3. Supabase's dashboard "Cron" integration (Database → Cron), which is
--      the same pg_cron engine under the hood and has the same Pro-plan
--      requirement, but gives you a UI instead of writing cron.schedule()
--      by hand.

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

-- ─── pg_cron scheduling (Pro plan and above only) ──────────────────────────
-- Wrapped in a DO block so this migration doesn't hard-fail on free-tier
-- projects where pg_cron can't be enabled — it logs a NOTICE and moves on
-- instead. If you're on Pro+ and this silently no-ops, check the NOTICE in
-- the query output; if you're on Free, use option 2 or 3 above instead.
-- Runs 00:05 UTC = 08:05 AM Philippine time.

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  PERFORM cron.schedule(
    'run-daily-loan-maintenance',
    '5 0 * * *',
    $cron$ SELECT run_daily_loan_maintenance(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron scheduling skipped (likely unavailable on this plan): %', SQLERRM;
END;
$$;