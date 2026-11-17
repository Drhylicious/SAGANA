-- ============================================================
-- SAGANA — Failed-program assistance limited by the Capital Share
--
-- THE WORKFLOW (already built: p7 / p47 / p48, nothing is replaced here)
--   A program outcome is Failed -> the Manager/Officer picks "Referred for Assistance
--   Assessment" -> that Farmer sees Request Assistance -> chooses items from the loan
--   item catalog -> a Manager/Officer approves or disapproves. Assistance is NOT a loan:
--   not cash, no repayment, no due date, own tables and own numbers (ASR-/ASA-).
--
-- WHAT THIS ADDS: the Capital Share rule, the same one loans use
--   * a Farmer with a Capital Share of 0 cannot request assistance;
--   * each assistance item (quantity x unit price) can be worth no more than the
--     Farmer's CURRENT Capital Share.
--   The Capital Share is read from member_capital_shares.total_contribution through
--   _loan_capital_share() (supabase_schema_loan_capital_eligibility.sql), the same
--   single reader loans use. Nothing is recalculated.
--
-- ENFORCED IN THE DATABASE, so no screen can skip it (Manager and Officer alike):
--   1. BEFORE INSERT on program_assistance_requests   -> zero Capital Share is refused
--   2. BEFORE INSERT on program_assistance_items      -> each line is checked
--   3. BEFORE UPDATE OF status on program_assistance_requests, when it becomes
--      'approved'                                      -> the request is checked AGAIN
--      against the Capital Share at that moment (it may have fallen since the Farmer
--      asked). Disapproving is never blocked.
--   The Capital Share row is locked FOR SHARE inside the same transaction, so a
--   stale screen or a contribution reversal at the same moment cannot slip through.
--
-- NOT CHANGED: the overdue-loan rule is a LOAN rule and is not applied to assistance
--   (assistance is not a loan and creates no debt). If the cooperative wants it here
--   too, add _loan_overdue_balance() to the two trigger functions below.
--   submit_assistance_request() and review_assistance_request() are NOT replaced.
--
-- Run after: supabase_schema_loan_capital_eligibility.sql and p48.
-- Not applied automatically. Run in the Supabase SQL editor.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ─────────────────────────────────────────────────
-- A. What this needs exists (expect 3 rows):
--    SELECT 'capital reader' WHERE to_regprocedure('public._loan_capital_share(uuid,boolean)') IS NOT NULL
--    UNION ALL SELECT 'assistance requests' WHERE to_regclass('public.program_assistance_requests') IS NOT NULL
--    UNION ALL SELECT 'assistance items' WHERE to_regclass('public.program_assistance_items') IS NOT NULL;
-- B. Assistance requests still waiting that this would now refuse at approval (information only;
--    each can still be disapproved with a reason):
--    SELECT r.request_number, r.farmer_name, i.item_name,
--           round(i.quantity * COALESCE(i.unit_price, 0), 2) AS item_value,
--           COALESCE(m.total_contribution, 0) AS capital_share
--    FROM public.program_assistance_requests r
--    JOIN public.program_assistance_items i ON i.request_id = r.id
--    LEFT JOIN public.member_capital_shares m ON m.farmer_id = r.farmer_id
--    WHERE r.status = 'pending' AND round(i.quantity * COALESCE(i.unit_price, 0), 2) > COALESCE(m.total_contribution, 0);
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._loan_capital_share(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_loan_capital_eligibility.sql first.';
  END IF;
  IF to_regclass('public.program_assistance_requests') IS NULL OR to_regclass('public.program_assistance_items') IS NULL THEN
    RAISE EXCEPTION 'The assistance tables are missing (p7).';
  END IF;
END;
$$;

-- ═══ 1. Value of an assistance line, and the sentences shown ══════════════
-- quantity x the saved unit price; a line saved without a price uses today's catalog
-- price, so a missing price can never get a line past the rule.
CREATE OR REPLACE FUNCTION public._assistance_item_value(p_inventory_item_id uuid, p_quantity numeric, p_unit_price numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT round(COALESCE(p_quantity, 0) * COALESCE(
           p_unit_price,
           (SELECT lim.unit_price FROM loan_items_master lim WHERE lim.inventory_item_id = p_inventory_item_id LIMIT 1),
           0), 2);
$$;
REVOKE ALL ON FUNCTION public._assistance_item_value(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._assistance_capital_refusal(p_item text, p_value numeric, p_capital numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_capital <= 0 THEN
      'Assistance not allowed: the Capital Share is ₱0.00, so no assistance item can be requested yet.'
    ELSE
      'Assistance not allowed: ' || COALESCE(p_item, 'this item') || ' is worth ₱' ||
      to_char(p_value, 'FM999,999,990.00') || ', which is more than the Capital Share of ₱' ||
      to_char(p_capital, 'FM999,999,990.00') || '. Only items worth up to ₱' ||
      to_char(p_capital, 'FM999,999,990.00') || ' can be given.'
  END;
$$;
REVOKE ALL ON FUNCTION public._assistance_capital_refusal(text, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- ═══ 2. A request is made: zero Capital Share ═════════════════════════════
CREATE OR REPLACE FUNCTION public._enforce_assistance_request_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_capital numeric;
  v_it      RECORD;
BEGIN
  -- Becoming approved: every line must still fit the Capital Share as it is now.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
      v_capital := public._loan_capital_share(NEW.farmer_id, true);
      IF v_capital <= 0 THEN
        RAISE EXCEPTION '%', public._assistance_capital_refusal(NULL, 0, v_capital);
      END IF;
      FOR v_it IN SELECT i.item_name, public._assistance_item_value(i.inventory_item_id, i.quantity, i.unit_price) AS item_value
                    FROM program_assistance_items i WHERE i.request_id = NEW.id
      LOOP
        IF v_it.item_value > v_capital THEN
          RAISE EXCEPTION '%', public._assistance_capital_refusal(v_it.item_name, v_it.item_value, v_capital);
        END IF;
      END LOOP;
    END IF;
    RETURN NEW;
  END IF;

  -- A new request.
  v_capital := public._loan_capital_share(NEW.farmer_id, true);
  IF v_capital <= 0 THEN
    RAISE EXCEPTION '%', public._assistance_capital_refusal(NULL, 0, v_capital);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assistance_requests_capital_insert ON public.program_assistance_requests;
CREATE TRIGGER trg_assistance_requests_capital_insert
  BEFORE INSERT ON public.program_assistance_requests
  FOR EACH ROW EXECUTE FUNCTION public._enforce_assistance_request_capital();

DROP TRIGGER IF EXISTS trg_assistance_requests_capital_approve ON public.program_assistance_requests;
CREATE TRIGGER trg_assistance_requests_capital_approve
  BEFORE UPDATE OF status ON public.program_assistance_requests
  FOR EACH ROW EXECUTE FUNCTION public._enforce_assistance_request_capital();

-- ═══ 3. Each assistance item ══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._enforce_assistance_item_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer  uuid;
  v_capital numeric;
  v_value   numeric;
BEGIN
  SELECT r.farmer_id INTO v_farmer FROM program_assistance_requests r WHERE r.id = NEW.request_id;
  IF v_farmer IS NULL THEN
    RETURN NEW;
  END IF;
  v_value   := public._assistance_item_value(NEW.inventory_item_id, NEW.quantity, NEW.unit_price);
  v_capital := public._loan_capital_share(v_farmer, true);
  IF v_value > v_capital THEN
    RAISE EXCEPTION '%', public._assistance_capital_refusal(NEW.item_name, v_value, v_capital);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assistance_items_capital ON public.program_assistance_items;
CREATE TRIGGER trg_assistance_items_capital
  BEFORE INSERT ON public.program_assistance_items
  FOR EACH ROW EXECUTE FUNCTION public._enforce_assistance_item_capital();

-- ═══ 4. What the Manager / Officer sees on a waiting request ══════════════
-- capital_share   the Farmer's Capital Share now
-- blocked         true when it is 0, or any item of the request is worth more than it
-- (the Farmer reads their own limit with get_loan_capital_standing)
CREATE OR REPLACE FUNCTION public.get_assistance_capital_check(p_request_id uuid)
RETURNS TABLE (capital_share numeric, blocked boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer  uuid;
  v_capital numeric;
  v_over    boolean;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can check an assistance request.';
  END IF;
  SELECT r.farmer_id INTO v_farmer FROM program_assistance_requests r WHERE r.id = p_request_id;
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Assistance request not found.';
  END IF;
  v_capital := public._loan_capital_share(v_farmer, false);
  SELECT EXISTS (
    SELECT 1 FROM program_assistance_items i
     WHERE i.request_id = p_request_id
       AND public._assistance_item_value(i.inventory_item_id, i.quantity, i.unit_price) > v_capital
  ) INTO v_over;
  RETURN QUERY SELECT v_capital, (v_capital <= 0 OR v_over);
END;
$$;
REVOKE ALL ON FUNCTION public.get_assistance_capital_check(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assistance_capital_check(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. The three triggers exist (expect 3 rows):
--    SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
--      AND tgname IN ('trg_assistance_requests_capital_insert', 'trg_assistance_requests_capital_approve', 'trg_assistance_items_capital');
-- 2. submit_assistance_request / review_assistance_request were NOT replaced (expect false, false):
--    SELECT (SELECT prosrc ILIKE '%_loan_capital_share%' FROM pg_proc WHERE proname = 'submit_assistance_request' AND pronamespace = 'public'::regnamespace),
--           (SELECT prosrc ILIKE '%_loan_capital_share%' FROM pg_proc WHERE proname = 'review_assistance_request' AND pronamespace = 'public'::regnamespace);
-- 3. Assistance still never touches the loan tables (expect 0):
--    SELECT count(*) FROM pg_proc WHERE proname IN ('submit_assistance_request', 'review_assistance_request')
--      AND (prosrc ILIKE '%farmer_loans%' OR prosrc ILIKE '%loan_requests%');
-- 4. By hand: as a Farmer with a Capital Share of 0, Request Assistance is refused; with a Capital Share
--    below an item's value that item is refused; lower the Capital Share after a request was made and
--    approving it is refused, disapproving still works.
-- ─────────────────────────────────────────────────────────────────────────
