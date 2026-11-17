-- ============================================================
-- supabase_schema_contrib_m01_monthly_contributions.sql
--
-- MONTHLY CONTRIBUTIONS (1). Run once, as a whole.
--
-- The proposed rules (confirm with the cooperative; every value is a setting):
--   * Each active Farmer owes PHP 100 a month, tracked separately per month, and the
--     obligation exists even when nothing is paid.
--   * Due on the 15th. An unpaid / partly paid balance is Overdue from the 16th.
--   * Partial payments are allowed; the balance stays on its own month.
--   * Statuses: Unpaid, Partial, Paid, Overdue, Waived. Overdue is a condition, not an
--     amount: a month is counted in exactly one status.
--   * Nothing here restricts a Farmer. Unpaid or overdue months block nothing.
--
-- What this script does
--   1. loan_policy_settings gets the two new settings (due day, first month charged).
--      The amount is the existing monthly_dues_amount.
--   2. capital_contribution_events (the existing Capital Contribution ledger) gets
--      contribution_month and payment_date, so a monthly payment IS a ledger entry
--      (no second ledger) and is still identifiable by month.
--   3. member_monthly_contributions: one row per Farmer per month (the obligation).
--      Its amount and due date are copied from the settings when the row is made,
--      so changing a setting never rewrites a past month.
--   4. member_monthly_contribution_status (view): amount paid, balance and status of
--      each month, worked out from the ledger, so a payment is never counted twice.
--   5. sync_monthly_contributions(): makes the missing monthly rows (daily job).
--   6. record_monthly_contribution_payment(): Manager / Officer with Manage access.
--   7. set_monthly_contribution_waiver(): Manager / Officer with Manage access.
--   8. reverse_capital_contribution(): the live function, plus the month and date
--      copied onto the cancellation entry, so a cancelled payment nets out of its month.
--   9. notify_monthly_contribution(): the three reminders, each sent once.
--
-- Months before monthly_contribution_start are NOT charged. It is set to the month this
-- script is run. To charge earlier months (for example September), see the note at the
-- end, then run: SELECT public.sync_monthly_contributions();
--
-- Earlier "member_payment" ledger entries have no month. They are left as they are: they
-- still count in the Capital Share, and are shown as "not assigned to a month".
-- Safe to re-run.
-- ============================================================

BEGIN;

-- ─── 1. Settings ─────────────────────────────────────────────────────────────
ALTER TABLE public.loan_policy_settings
  ADD COLUMN IF NOT EXISTS monthly_contribution_due_day integer NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS monthly_contribution_start  date;

ALTER TABLE public.loan_policy_settings
  DROP CONSTRAINT IF EXISTS loan_policy_settings_due_day_chk;
ALTER TABLE public.loan_policy_settings
  ADD CONSTRAINT loan_policy_settings_due_day_chk
  CHECK (monthly_contribution_due_day BETWEEN 1 AND 28);

UPDATE public.loan_policy_settings
SET monthly_contribution_start = date_trunc('month', (now() AT TIME ZONE 'Asia/Manila'))::date
WHERE id = 1 AND monthly_contribution_start IS NULL;

-- ─── 2. The ledger knows which month a monthly payment is for ────────────────
ALTER TABLE public.capital_contribution_events
  ADD COLUMN IF NOT EXISTS contribution_month date,
  ADD COLUMN IF NOT EXISTS payment_date       date;

ALTER TABLE public.capital_contribution_events
  DROP CONSTRAINT IF EXISTS cce_contribution_month_first_chk;
ALTER TABLE public.capital_contribution_events
  ADD CONSTRAINT cce_contribution_month_first_chk
  CHECK (contribution_month IS NULL OR contribution_month = date_trunc('month', contribution_month)::date);

CREATE INDEX IF NOT EXISTS idx_cce_farmer_month
  ON public.capital_contribution_events (farmer_id, contribution_month)
  WHERE contribution_month IS NOT NULL;

-- ─── 3. The monthly obligation ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.member_monthly_contributions (
  id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id          uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contribution_month date          NOT NULL
                       CHECK (contribution_month = date_trunc('month', contribution_month)::date),
  amount_due         numeric(12,2) NOT NULL CHECK (amount_due > 0),
  due_date           date          NOT NULL,
  waived_at          timestamptz,
  waived_by          uuid,
  waive_reason       text,
  created_at         timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT uq_member_monthly_contribution UNIQUE (farmer_id, contribution_month)
);

CREATE INDEX IF NOT EXISTS idx_mmc_month ON public.member_monthly_contributions (contribution_month);

ALTER TABLE public.member_monthly_contributions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mmc: farmer reads own" ON public.member_monthly_contributions;
CREATE POLICY "mmc: farmer reads own"
  ON public.member_monthly_contributions FOR SELECT TO authenticated
  USING (auth.uid() = farmer_id);

DROP POLICY IF EXISTS "mmc: staff reads all" ON public.member_monthly_contributions;
CREATE POLICY "mmc: staff reads all"
  ON public.member_monthly_contributions FOR SELECT TO authenticated
  USING (public.is_staff());

-- Written only by the functions below.
REVOKE ALL ON public.member_monthly_contributions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.member_monthly_contributions TO authenticated;

-- A waiver is a staff change: keep it in the activity log like every Members change.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.member_monthly_contributions;
CREATE TRIGGER trg_audit_staff_change
  AFTER UPDATE ON public.member_monthly_contributions
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('members', '');

-- Each reminder is sent once per Farmer and month, however often the job runs.
CREATE TABLE IF NOT EXISTS public.monthly_contribution_notices (
  farmer_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contribution_month date        NOT NULL,
  kind               text        NOT NULL CHECK (kind IN ('eve', 'meeting', 'overdue')),
  sent_at            timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (farmer_id, contribution_month, kind)
);
ALTER TABLE public.monthly_contribution_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monthly_contribution_notices FROM PUBLIC, anon, authenticated;

-- ─── 4. Paid, balance and status of every month ──────────────────────────────
-- Paid = the ledger's member_payment entries of that month (a cancellation carries
-- the same month, so it nets out). Waived months owe nothing. Overdue wins over
-- Partial/Unpaid once the due date has passed, so a month is in exactly one status.
CREATE OR REPLACE VIEW public.member_monthly_contribution_status
WITH (security_invoker = true) AS
SELECT
  m.id,
  m.farmer_id,
  m.contribution_month,
  m.amount_due,
  m.due_date,
  (m.waived_at IS NOT NULL) AS waived,
  m.waive_reason,
  m.waived_at,
  p.paid AS paid_amount,
  CASE WHEN m.waived_at IS NOT NULL THEN 0
       ELSE GREATEST(m.amount_due - p.paid, 0) END AS balance,
  CASE WHEN m.waived_at IS NOT NULL THEN 'waived'
       WHEN p.paid >= m.amount_due THEN 'paid'
       WHEN (now() AT TIME ZONE 'Asia/Manila')::date > m.due_date THEN 'overdue'
       WHEN p.paid > 0 THEN 'partial'
       ELSE 'unpaid' END AS status
FROM public.member_monthly_contributions m
CROSS JOIN LATERAL (
  SELECT COALESCE(SUM(c.amount), 0)::numeric(12,2) AS paid
  FROM public.capital_contribution_events c
  WHERE c.farmer_id = m.farmer_id
    AND c.contribution_month = m.contribution_month
    AND c.source = 'member_payment'
) p;

GRANT SELECT ON public.member_monthly_contribution_status TO authenticated;

-- ─── 5. Make the missing monthly rows ────────────────────────────────────────
-- For every active Farmer, one row per month from the later of "first month charged"
-- and the month the Farmer became active, up to the current month. Existing rows are
-- never changed.
CREATE OR REPLACE FUNCTION public.sync_monthly_contributions(p_today date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_today  date := COALESCE(p_today, (now() AT TIME ZONE 'Asia/Manila')::date);
  v_amount numeric;
  v_day    integer;
  v_start  date;
  v_n      integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only the Manager or an Officer can do this.';
  END IF;

  SELECT monthly_dues_amount, monthly_contribution_due_day, monthly_contribution_start
    INTO v_amount, v_day, v_start
  FROM public.loan_policy_settings WHERE id = 1;

  IF v_amount IS NULL OR v_amount <= 0 OR v_start IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO public.member_monthly_contributions (farmer_id, contribution_month, amount_due, due_date)
  SELECT f.user_id, g.m::date, v_amount, (g.m::date + (v_day - 1))
  FROM (
    SELECT ur.user_id,
           date_trunc('month', COALESCE(
             (SELECT min(e.created_at) FROM public.member_status_events e
               WHERE e.member_id = ur.user_id AND e.to_status = 'active'),
             ur.created_at) AT TIME ZONE 'Asia/Manila') AS joined_month
    FROM public.user_roles ur
    WHERE ur.role = 'farmer' AND ur.status = 'active'
  ) f
  CROSS JOIN LATERAL generate_series(
    GREATEST(date_trunc('month', v_start::timestamp), f.joined_month),
    date_trunc('month', v_today::timestamp),
    interval '1 month'
  ) AS g(m)
  ON CONFLICT (farmer_id, contribution_month) DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sync_monthly_contributions(date) TO authenticated;

-- ─── 6. Record a payment (Manager / Officer with Manage access) ──────────────
CREATE OR REPLACE FUNCTION public.record_monthly_contribution_payment(
  p_farmer_id uuid,
  p_month     date,
  p_amount    numeric,
  p_paid_on   date DEFAULT NULL,
  p_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_month  date := date_trunc('month', p_month)::date;
  v_today  date := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_paid_on date := COALESCE(p_paid_on, v_today);
  v_amount numeric(12,2) := round(COALESCE(p_amount, 0), 2);
  v_row    public.member_monthly_contributions%ROWTYPE;
  v_paid   numeric(12,2);
  v_ref    text := NULLIF(btrim(COALESCE(p_reference, '')), '');
  v_new    uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only the Manager or an Officer who manages Members can record a payment.';
  END IF;
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Enter an amount greater than zero.';
  END IF;
  IF v_paid_on > v_today THEN
    RAISE EXCEPTION 'The payment date cannot be in the future.';
  END IF;
  IF v_ref IS NOT NULL AND length(v_ref) > 200 THEN
    RAISE EXCEPTION 'The reference is too long (200 characters at most).';
  END IF;

  SELECT * INTO v_row
  FROM public.member_monthly_contributions
  WHERE farmer_id = p_farmer_id AND contribution_month = v_month
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This Farmer has no monthly contribution recorded for that month.';
  END IF;
  IF v_row.waived_at IS NOT NULL THEN
    RAISE EXCEPTION 'This month was waived. Reinstate it before recording a payment.';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_paid
  FROM public.capital_contribution_events
  WHERE farmer_id = p_farmer_id AND contribution_month = v_month AND source = 'member_payment';

  IF v_amount > v_row.amount_due - v_paid THEN
    RAISE EXCEPTION 'The amount is more than the remaining balance of PHP %.',
      to_char(GREATEST(v_row.amount_due - v_paid, 0), 'FM999999990.00');
  END IF;

  INSERT INTO public.capital_contribution_events
    (farmer_id, amount, source, note, recorded_by, contribution_month, payment_date)
  VALUES
    (p_farmer_id, v_amount, 'member_payment', v_ref, auth.uid(), v_month, v_paid_on)
  RETURNING id INTO v_new;

  RETURN v_new;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.record_monthly_contribution_payment(uuid, date, numeric, date, text) TO authenticated;

-- ─── 7. Waive (or reinstate) a month ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_monthly_contribution_waiver(
  p_farmer_id uuid,
  p_month     date,
  p_waive     boolean,
  p_reason    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_month  date := date_trunc('month', p_month)::date;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_row    public.member_monthly_contributions%ROWTYPE;
  v_paid   numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only the Manager or an Officer who manages Members can waive a month.';
  END IF;

  SELECT * INTO v_row
  FROM public.member_monthly_contributions
  WHERE farmer_id = p_farmer_id AND contribution_month = v_month
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This Farmer has no monthly contribution recorded for that month.';
  END IF;

  IF p_waive THEN
    IF length(v_reason) < 3 THEN
      RAISE EXCEPTION 'Enter the reason for the waiver (at least 3 characters).';
    END IF;
    IF length(v_reason) > 500 THEN
      RAISE EXCEPTION 'The reason is too long (500 characters at most).';
    END IF;
    IF v_row.waived_at IS NOT NULL THEN
      RAISE EXCEPTION 'This month is already waived.';
    END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM public.capital_contribution_events
    WHERE farmer_id = p_farmer_id AND contribution_month = v_month AND source = 'member_payment';
    IF v_paid > 0 THEN
      RAISE EXCEPTION 'A payment is already recorded for this month. Cancel it before waiving the month.';
    END IF;
    UPDATE public.member_monthly_contributions
    SET waived_at = now(), waived_by = auth.uid(), waive_reason = v_reason
    WHERE id = v_row.id;
  ELSE
    IF v_row.waived_at IS NULL THEN
      RAISE EXCEPTION 'This month is not waived.';
    END IF;
    UPDATE public.member_monthly_contributions
    SET waived_at = NULL, waived_by = NULL, waive_reason = NULL
    WHERE id = v_row.id;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_monthly_contribution_waiver(uuid, date, boolean, text) TO authenticated;

-- An Officer is held to View Only / Manage like every other Members action.
INSERT INTO public.staff_permission_targets (kind, name, module)
SELECT 'rpc', n, 'members'
FROM (VALUES ('record_monthly_contribution_payment'), ('set_monthly_contribution_waiver')) v(n)
WHERE NOT EXISTS (
  SELECT 1 FROM public.staff_permission_targets t WHERE t.kind = 'rpc' AND t.name = v.n
);

-- ─── 8. Cancelling a payment keeps its month ─────────────────────────────────
-- The LIVE reverse_capital_contribution, with the month and payment date copied onto
-- the cancellation entry (so the month's paid amount nets out). Nothing else changed.
CREATE OR REPLACE FUNCTION public.reverse_capital_contribution(p_event_id uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_orig   public.capital_contribution_events%ROWTYPE;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_new    uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only the Manager or an Officer who manages Members can cancel a contribution.';
  END IF;
  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'Enter the reason for the cancellation (at least 3 characters).';
  END IF;
  IF length(v_reason) > 500 THEN
    RAISE EXCEPTION 'The reason is too long (500 characters at most).';
  END IF;

  SELECT * INTO v_orig FROM public.capital_contribution_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contribution not found.';
  END IF;
  IF v_orig.reverses_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'A cancellation cannot be cancelled.';
  END IF;
  IF v_orig.source = 'patronage_capital' THEN
    RAISE EXCEPTION 'A payout added to capital is handled in Balik-Tangkilik and cannot be cancelled here.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.capital_contribution_events WHERE reverses_event_id = p_event_id) THEN
    RAISE EXCEPTION 'This contribution has already been cancelled.';
  END IF;

  INSERT INTO public.capital_contribution_events
    (farmer_id, amount, source, note, recorded_by, reverses_event_id, reversal_reason,
     contribution_month, payment_date)
  VALUES
    (v_orig.farmer_id, -v_orig.amount, v_orig.source, NULL, auth.uid(), v_orig.id, v_reason,
     v_orig.contribution_month, v_orig.payment_date)
  RETURNING id INTO v_new;

  RETURN v_new;
END;
$function$;

-- ─── 9. The three reminders (each once per Farmer and month) ─────────────────
--   eve      the day before the first-Saturday BOD meeting
--   meeting  the day of the meeting
--   overdue  once, after the due date has passed
-- Only Farmers who still have a balance on that month are reminded; a Farmer who has
-- paid or been waived gets nothing. Never daily.
CREATE OR REPLACE FUNCTION public.notify_monthly_contribution(p_today date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_today   date := COALESCE(p_today, (now() AT TIME ZONE 'Asia/Manila')::date);
  v_meeting date := public.bod_first_saturday(v_today);
  v_kind    text;
  v_total   integer := 0;
  v_n       integer;
BEGIN
  PERFORM public.sync_monthly_contributions(v_today);

  IF v_today = v_meeting - 1 THEN
    v_kind := 'eve';
  ELSIF v_today = v_meeting THEN
    v_kind := 'meeting';
  END IF;

  IF v_kind IS NOT NULL THEN
    WITH due AS (
      SELECT s.farmer_id, s.contribution_month, s.balance, s.amount_due
      FROM public.member_monthly_contribution_status s
      JOIN public.user_roles ur ON ur.user_id = s.farmer_id AND ur.role = 'farmer' AND ur.status = 'active'
      WHERE s.contribution_month = date_trunc('month', v_today)::date
        AND s.balance > 0
        AND NOT EXISTS (
          SELECT 1 FROM public.monthly_contribution_notices n
          WHERE n.farmer_id = s.farmer_id AND n.contribution_month = s.contribution_month AND n.kind = v_kind)
    ), sent AS (
      INSERT INTO public.monthly_contribution_notices (farmer_id, contribution_month, kind)
      SELECT farmer_id, contribution_month, v_kind FROM due
      RETURNING farmer_id, contribution_month
    )
    INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    SELECT d.farmer_id, 'capital',
           CASE v_kind WHEN 'eve' THEN 'Monthly Contribution Reminder'
                       ELSE 'Monthly Contribution Announcement' END,
           CASE v_kind
             WHEN 'eve' THEN 'The BOD meeting is tomorrow. The monthly contribution of ₱'
             ELSE 'Today is the BOD meeting. The monthly contribution of ₱' END
             || to_char(d.amount_due, 'FM999999990.00') || ' for '
             || to_char(d.contribution_month, 'FMMonth YYYY')
             || CASE v_kind WHEN 'eve' THEN ' will be announced there.'
                            ELSE ' is part of the meeting announcement.' END
             || ' Remaining balance: ₱' || to_char(d.balance, 'FM999999990.00') || '.',
           FALSE, NOW(), '/farmer/profile/contribution'
    FROM due d JOIN sent s ON s.farmer_id = d.farmer_id AND s.contribution_month = d.contribution_month;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
  END IF;

  -- After the due date: once per month and Farmer.
  WITH late AS (
    SELECT s.farmer_id, s.contribution_month, s.balance, s.due_date
    FROM public.member_monthly_contribution_status s
    JOIN public.user_roles ur ON ur.user_id = s.farmer_id AND ur.role = 'farmer' AND ur.status = 'active'
    WHERE s.status = 'overdue'
      AND s.balance > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.monthly_contribution_notices n
        WHERE n.farmer_id = s.farmer_id AND n.contribution_month = s.contribution_month AND n.kind = 'overdue')
  ), sent AS (
    INSERT INTO public.monthly_contribution_notices (farmer_id, contribution_month, kind)
    SELECT farmer_id, contribution_month, 'overdue' FROM late
    RETURNING farmer_id, contribution_month
  )
  INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT l.farmer_id, 'capital', 'Monthly Contribution Overdue',
         'Your ' || to_char(l.contribution_month, 'FMMonth YYYY')
           || ' monthly contribution was due on ' || to_char(l.due_date, 'FMMonth DD, YYYY')
           || '. Remaining balance: ₱' || to_char(l.balance, 'FM999999990.00') || '.',
         FALSE, NOW(), '/farmer/profile/contribution'
  FROM late l JOIN sent s ON s.farmer_id = l.farmer_id AND s.contribution_month = l.contribution_month;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_total := v_total + v_n;

  RETURN v_total;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_monthly_contribution(date) FROM PUBLIC, anon, authenticated;

-- Daily, 00:30 UTC (8:30 AM in the Philippines), after the other daily jobs.
DO $cron$
BEGIN
  PERFORM cron.unschedule('monthly-contribution-notices')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'monthly-contribution-notices');
  PERFORM cron.schedule('monthly-contribution-notices', '30 0 * * *',
                        'SELECT public.notify_monthly_contribution();');
END
$cron$;

-- Make this month's rows now.
SELECT public.sync_monthly_contributions();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only). Run on their own. Every row PASS.
-- ============================================================
SELECT 'settings' AS check_name,
       CASE WHEN (SELECT monthly_contribution_due_day = 15 AND monthly_contribution_start IS NOT NULL
                  FROM public.loan_policy_settings WHERE id = 1)
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'ledger columns',
       CASE WHEN (SELECT count(*) FROM information_schema.columns
                  WHERE table_name = 'capital_contribution_events'
                    AND column_name IN ('contribution_month', 'payment_date')) = 2
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'one row per active Farmer for this month',
       CASE WHEN (SELECT count(*) FROM public.user_roles WHERE role = 'farmer' AND status = 'active')
                 = (SELECT count(*) FROM public.member_monthly_contributions
                    WHERE contribution_month = date_trunc('month', now() AT TIME ZONE 'Asia/Manila')::date)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'no month is counted in two statuses',
       CASE WHEN (SELECT count(*) FROM public.member_monthly_contribution_status)
                 = (SELECT count(*) FROM public.member_monthly_contributions)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'functions exist',
       CASE WHEN (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                  AND proname IN ('sync_monthly_contributions', 'record_monthly_contribution_payment',
                                  'set_monthly_contribution_waiver', 'notify_monthly_contribution')) = 4
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'Officer gate registered',
       CASE WHEN (SELECT count(*) FROM public.staff_permission_targets
                  WHERE name IN ('record_monthly_contribution_payment', 'set_monthly_contribution_waiver')) = 2
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'daily reminder job scheduled',
       CASE WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'monthly-contribution-notices')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'cancellation keeps the month',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'reverse_capital_contribution'
                  AND pronamespace = 'public'::regnamespace) LIKE '%contribution_month%'
            THEN 'PASS' ELSE 'FAIL' END;

-- ------------------------------------------------------------
-- OPTIONAL - change a policy value (run only if the cooperative decides):
--   UPDATE public.loan_policy_settings SET monthly_dues_amount = 100 WHERE id = 1;
--   UPDATE public.loan_policy_settings SET monthly_contribution_due_day = 15 WHERE id = 1;
-- A change applies to months made after it; existing months keep their own amount and date.
--
-- OPTIONAL - charge earlier months (for example from September 2026), then make them:
--   UPDATE public.loan_policy_settings SET monthly_contribution_start = '2026-09-01' WHERE id = 1;
--   SELECT public.sync_monthly_contributions();
-- ------------------------------------------------------------
