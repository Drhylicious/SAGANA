-- ============================================================
-- SAGANA — Loan maintenance staleness tracking
-- Adds a timestamp stamped at the end of a successful
-- run_daily_loan_maintenance() run, so the Dashboard can show a
-- "last verified" indicator on the Overdue Loans KPI instead of
-- presenting that figure as always-current with no way to check.
-- loan_policy_settings.updated_at is NOT reused — it tracks
-- policy-setting edits, a different event.
-- ============================================================

ALTER TABLE public.loan_policy_settings
  ADD COLUMN IF NOT EXISTS last_maintenance_run_at TIMESTAMPTZ;

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

  UPDATE loan_policy_settings
  SET last_maintenance_run_at = NOW()
  WHERE id = 1;
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_loan_maintenance TO authenticated;

NOTIFY pgrst, 'reload schema';
