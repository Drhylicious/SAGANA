-- ============================================================
-- SAGANA — Loan eligibility: zero Capital Share and unpaid overdue loans
--
-- Builds on supabase_schema_loan_capital_eligibility.sql (run that first).
-- A farmer cannot be issued a loan (Manager / Officer) or request one (Farmer) when:
--   1. ZERO CAPITAL SHARE   the Capital Share (member_capital_shares.total_contribution) is 0; or
--   2. OVERDUE LOAN         the farmer has an overdue loan that is not fully paid.
--      The overdue loan must be PAID IN FULL. A partial payment does NOT restore
--      eligibility, even though the loan's status goes back to "active" when a
--      payment is recorded (existing rule, unchanged). That is why a loan now
--      remembers that it went overdue: farmer_loans.overdue_since.
--      "Overdue balance" = what is still unpaid on those loans.
--
-- ENFORCEMENT (database, so no screen can skip it; Manager and Officer alike):
--   BEFORE INSERT on farmer_loans   (every loan issued, by hand or by approving a request)
--   BEFORE INSERT on loan_requests  (every farmer request)
--   The per-item Capital Share limit from the earlier script stays as it is.
--   issue_loan(), submit_loan_request() and review_loan_request() are NOT replaced.
--
-- A loan counts as overdue for this rule when it still has a balance and
--   * its status is 'overdue', or
--   * it was overdue before (overdue_since is set, even after a partial payment), or
--   * it is 'active' but its payment date plus the grace period has already passed
--     (the daily job has not flipped it yet).
--
-- Existing loans: overdue_since is set to now() for loans that are overdue right now.
-- Nothing else is changed, nothing is deleted.
--
-- Not applied automatically. Run in the Supabase SQL editor.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ─────────────────────────────────────────────────
-- A. The earlier script is applied (expect 2 rows):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('_loan_capital_share', 'get_loan_capital_standing');
-- B. Farmers this will block today (overdue balance, Capital Share):
--    SELECT ui.full_name, sum(fl.total_value - fl.amount_paid) AS overdue_balance,
--           COALESCE(max(m.total_contribution), 0) AS capital_share
--    FROM public.farmer_loans fl
--    LEFT JOIN public.user_information ui ON ui.user_id = fl.farmer_id
--    LEFT JOIN public.member_capital_shares m ON m.farmer_id = fl.farmer_id
--    WHERE fl.status = 'overdue' GROUP BY ui.full_name;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._loan_capital_share(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_loan_capital_eligibility.sql first.';
  END IF;
END;
$$;

-- ═══ 1. A loan remembers that it went overdue ═════════════════════════════
ALTER TABLE public.farmer_loans ADD COLUMN IF NOT EXISTS overdue_since TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public._mark_loan_overdue_since()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'overdue' AND NEW.overdue_since IS NULL THEN
    NEW.overdue_since := NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_loans_overdue_since ON public.farmer_loans;
CREATE TRIGGER trg_farmer_loans_overdue_since
  BEFORE INSERT OR UPDATE OF status ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION public._mark_loan_overdue_since();

-- Loans that are overdue right now start their history today.
UPDATE public.farmer_loans
   SET overdue_since = NOW()
 WHERE status = 'overdue' AND overdue_since IS NULL;

-- ═══ 2. What a farmer still owes on overdue loans ═════════════════════════
CREATE OR REPLACE FUNCTION public._loan_overdue_balance(p_farmer_id uuid)
RETURNS TABLE (overdue_balance numeric, overdue_loans integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(fl.total_value - fl.amount_paid), 0)::numeric,
         COUNT(*)::integer
    FROM farmer_loans fl
   WHERE fl.farmer_id = p_farmer_id
     AND fl.status <> 'paid'
     AND fl.total_value - fl.amount_paid > 0
     AND (
           fl.status = 'overdue'
        OR fl.overdue_since IS NOT NULL
        OR (fl.status = 'active'
            AND fl.next_payment_date IS NOT NULL
            AND fl.next_payment_date < ((NOW() AT TIME ZONE 'Asia/Manila')::date
                  - COALESCE((SELECT s.grace_period_days FROM loan_policy_settings s WHERE s.id = 1), 1)))
         );
$$;
REVOKE ALL ON FUNCTION public._loan_overdue_balance(uuid) FROM PUBLIC, anon, authenticated;

-- ═══ 3. The sentence shown when a loan or request is refused ══════════════
-- NULL when the farmer may borrow. p_you: the farmer is the one asking.
-- Kept short: the app shows a database sentence only when it is a plain one.
CREATE OR REPLACE FUNCTION public._loan_block_reasons(p_farmer_id uuid, p_you boolean, p_lock boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_capital numeric;
  v_overdue numeric;
  v_text    text := '';
BEGIN
  v_capital := public._loan_capital_share(p_farmer_id, p_lock);
  SELECT o.overdue_balance INTO v_overdue FROM public._loan_overdue_balance(p_farmer_id) o;

  IF v_capital <= 0 THEN
    v_text := v_text || CASE WHEN p_you
      THEN 'Your Capital Share is ₱0.00, so no loan item can be requested yet.'
      ELSE 'The Capital Share is ₱0.00, so no loan item can be issued yet.' END;
  END IF;

  IF v_overdue > 0 THEN
    v_text := v_text || CASE WHEN v_text = '' THEN '' ELSE ' ' END || CASE WHEN p_you
      THEN 'You have an overdue loan (₱' || to_char(v_overdue, 'FM999,999,990.00') || ' unpaid). Pay it in full first; a partial payment is not enough.'
      ELSE 'This farmer has an overdue loan (₱' || to_char(v_overdue, 'FM999,999,990.00') || ' unpaid). It must be paid in full first; a partial payment is not enough.' END;
  END IF;

  IF v_text = '' THEN
    RETURN NULL;
  END IF;
  RETURN 'Not eligible: ' || v_text;
END;
$$;
REVOKE ALL ON FUNCTION public._loan_block_reasons(uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- ═══ 4. Enforcement on the loan and on the request ════════════════════════
CREATE OR REPLACE FUNCTION public._enforce_loan_eligibility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason text;
BEGIN
  v_reason := public._loan_block_reasons(NEW.farmer_id, auth.uid() IS NOT DISTINCT FROM NEW.farmer_id, true);
  IF v_reason IS NOT NULL THEN
    RAISE EXCEPTION '%', v_reason;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_loans_eligibility ON public.farmer_loans;
CREATE TRIGGER trg_farmer_loans_eligibility
  BEFORE INSERT ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION public._enforce_loan_eligibility();

DROP TRIGGER IF EXISTS trg_loan_requests_eligibility ON public.loan_requests;
CREATE TRIGGER trg_loan_requests_eligibility
  BEFORE INSERT ON public.loan_requests
  FOR EACH ROW EXECUTE FUNCTION public._enforce_loan_eligibility();

-- ═══ 5. What the screens show ═════════════════════════════════════════════
-- Same function as before with more columns, so it is dropped and recreated.
DROP FUNCTION IF EXISTS public.get_loan_capital_standing(uuid);

CREATE OR REPLACE FUNCTION public.get_loan_capital_standing(p_farmer_id uuid DEFAULT NULL)
RETURNS TABLE (
  capital_share   numeric,
  max_item_value  numeric,
  overdue_balance numeric,
  overdue_loans   integer,
  is_eligible     boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target  uuid;
  v_capital numeric;
  v_balance numeric;
  v_count   integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  IF public.is_staff() THEN
    v_target := COALESCE(p_farmer_id, auth.uid());
  ELSE
    IF p_farmer_id IS NOT NULL AND p_farmer_id <> auth.uid() THEN
      RAISE EXCEPTION 'You can only see your own Capital Share.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = auth.uid() AND ur.role = 'farmer') THEN
      RAISE EXCEPTION 'Only a farmer or staff can see this.';
    END IF;
    v_target := auth.uid();
  END IF;

  v_capital := public._loan_capital_share(v_target, false);
  SELECT o.overdue_balance, o.overdue_loans INTO v_balance, v_count FROM public._loan_overdue_balance(v_target) o;

  RETURN QUERY SELECT v_capital, v_capital, v_balance, v_count, (v_capital > 0 AND v_balance <= 0);
END;
$$;
REVOKE ALL ON FUNCTION public.get_loan_capital_standing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_loan_capital_standing(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. The objects exist (expect 2 triggers + the overdue_since trigger, and the column):
--    SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
--      AND tgname IN ('trg_farmer_loans_eligibility', 'trg_loan_requests_eligibility', 'trg_farmer_loans_overdue_since');
--    SELECT column_name FROM information_schema.columns WHERE table_name = 'farmer_loans' AND column_name = 'overdue_since';
-- 2. Loans that are overdue now remember it (expect 0 rows):
--    SELECT id, reference_no FROM public.farmer_loans WHERE status = 'overdue' AND overdue_since IS NULL;
-- 3. Who is blocked now, and why (staff, in the SQL editor):
--    SELECT ur.user_id, ui.full_name, public._loan_block_reasons(ur.user_id, false) AS reason
--    FROM public.user_roles ur LEFT JOIN public.user_information ui ON ui.user_id = ur.user_id
--    WHERE ur.role = 'farmer' AND ur.status = 'active' AND public._loan_block_reasons(ur.user_id, false) IS NOT NULL;
-- 4. A partial payment does not restore eligibility: take an overdue loan, record part of
--    its balance in the app, and check that the farmer is still listed by query 3 and the
--    Issue Loan button stays off. Paying the loan in full removes the farmer from query 3.
--
-- DECISION: "the overdue amount" is read as the unpaid balance of the overdue loan(s), as
-- the screens show it ("Overdue balance"). If the cooperative means only the missed
-- instalment, _loan_overdue_balance is the one place to change.
-- ─────────────────────────────────────────────────────────────────────────
