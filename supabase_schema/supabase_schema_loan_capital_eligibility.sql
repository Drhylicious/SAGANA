-- ============================================================
-- SAGANA — Capital Share loan eligibility
--
-- THE RULE
--   A farmer can only borrow a loan item whose value does not exceed the farmer's
--   CURRENT Capital Share. Capital Share 500: an item worth 300 or 500 is allowed,
--   an item worth 600 is not. Capital Share 0: no loan item can be borrowed.
--
--   "Value of a loan item" = the value of that line of the loan or request:
--   quantity x unit price (2 x a 360 bag = 720). Each line is checked on its own;
--   the loan total is NOT capped (that is how the rule was worded). If the
--   cooperative means the whole loan, change ONE function: _enforce_loan_item_capital
--   / _enforce_loan_request_item_capital (see "DECISION" at the end).
--
-- WHERE THE CAPITAL SHARE COMES FROM (nothing is recalculated here)
--   member_capital_shares.total_contribution: the running total the ledger
--   (capital_contribution_events) keeps through trg_cce_recompute. Monthly
--   contributions, member-price purchase discounts, starting capital and corrections
--   all reach it that way. This script only READS it.
--
-- WHERE IT IS ENFORCED (the database, so no screen or API call can skip it)
--   1. A farmer's request   -> BEFORE INSERT on loan_request_items
--                              (submit_loan_request writes its lines there)
--   2. A loan issued        -> BEFORE INSERT on farmer_loan_items
--      (by hand, or by       (issue_loan writes its lines there, and
--       approving a request)  review_loan_request issues through issue_loan, so an
--                            approval is checked again against the Capital Share
--                            at that moment, not the one at request time)
--   Manager and Officer are treated alike (is_staff() decides nothing here).
--   The check refuses with a message that names the item, its value, the Capital
--   Share and the most that can be borrowed, so the app shows it as it is.
--
-- STALE DATA AND CONCURRENT TRANSACTIONS
--   The Capital Share is read INSIDE the transaction that saves the line, and the
--   row is locked FOR SHARE until that transaction ends. So:
--     * the value used is the latest committed one, never a copy from the screen;
--     * a contribution that lowers it (a reversal) at the same moment has to wait
--       until the loan or request is saved, instead of slipping in between.
--   Two loans for the same farmer can still be issued one after the other: the
--   rule is per item against the Capital Share, not a running limit (see DECISION).
--
-- WHAT DOES NOT CHANGE
--   issue_loan(), submit_loan_request() and review_loan_request() are NOT replaced
--   (their live copies may differ from the repo); the rule hangs on the tables they
--   write to. Failed-program assistance is not a loan and is untouched. Loans and
--   requests that already exist are not touched; a request that is still Pending is
--   checked again when it is approved. loan_policy_settings.minimum_capital_contribution
--   and loan_capital_eligibility() stay as they are (unused).
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end (and supabase_schema_loan_capital_eligibility_test.sql).
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ────────────────────────────
-- A. Everything this needs exists (expect 5 rows):
--    SELECT 'member_capital_shares.total_contribution' WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='member_capital_shares' AND column_name='total_contribution')
--    UNION ALL SELECT 'farmer_loan_items'  WHERE to_regclass('public.farmer_loan_items')  IS NOT NULL
--    UNION ALL SELECT 'loan_request_items' WHERE to_regclass('public.loan_request_items') IS NOT NULL
--    UNION ALL SELECT 'issue_loan'         WHERE to_regprocedure('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)') IS NOT NULL
--    UNION ALL SELECT 'is_staff'           WHERE to_regprocedure('public.is_staff()') IS NOT NULL;
-- B. The only functions that write loan lines (expect issue_loan and submit_loan_request;
--    if another name appears, it needs a look before this is applied):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND (prosrc ILIKE '%insert into farmer_loan_items%' OR prosrc ILIKE '%insert into loan_request_items%') ORDER BY 1;
-- C. Requests still waiting that this rule would now refuse (for your information;
--    each can still be disapproved with a reason, nothing is changed):
--    SELECT lr.request_no, ui.full_name, i.item_name, i.line_total,
--           COALESCE(m.total_contribution, 0) AS capital_share
--    FROM public.loan_requests lr
--    JOIN public.loan_request_items i ON i.request_id = lr.id
--    LEFT JOIN public.member_capital_shares m ON m.farmer_id = lr.farmer_id
--    LEFT JOIN public.user_information ui ON ui.user_id = lr.farmer_id
--    WHERE lr.status = 'pending' AND i.line_total > COALESCE(m.total_contribution, 0)
--    ORDER BY lr.requested_at;
-- D. Farmers who would be unable to borrow anything today (Capital Share 0):
--    SELECT ur.user_id, ui.full_name FROM public.user_roles ur
--    LEFT JOIN public.member_capital_shares m ON m.farmer_id = ur.user_id
--    LEFT JOIN public.user_information ui ON ui.user_id = ur.user_id
--    WHERE ur.role = 'farmer' AND ur.status = 'active' AND COALESCE(m.total_contribution, 0) = 0;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'member_capital_shares'
                   AND column_name = 'total_contribution') THEN
    RAISE EXCEPTION 'member_capital_shares.total_contribution is missing.';
  END IF;
  IF to_regclass('public.farmer_loan_items') IS NULL OR to_regclass('public.loan_request_items') IS NULL THEN
    RAISE EXCEPTION 'farmer_loan_items or loan_request_items is missing. Run supabase_schema_farmer_loan_requests.sql first.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
END;
$$;

-- ═══ 1. The one place the Capital Share is read for loans ═════════════════
-- p_lock = true keeps the row locked FOR SHARE until the calling transaction ends.
-- A farmer with no row has a Capital Share of 0.
CREATE OR REPLACE FUNCTION public._loan_capital_share(p_farmer_id uuid, p_lock boolean DEFAULT false)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_capital numeric;
BEGIN
  IF p_lock THEN
    SELECT m.total_contribution INTO v_capital
      FROM member_capital_shares m
     WHERE m.farmer_id = p_farmer_id
       FOR SHARE;
  ELSE
    SELECT m.total_contribution INTO v_capital
      FROM member_capital_shares m
     WHERE m.farmer_id = p_farmer_id;
  END IF;
  RETURN COALESCE(v_capital, 0);
END;
$$;
REVOKE ALL ON FUNCTION public._loan_capital_share(uuid, boolean) FROM PUBLIC, anon, authenticated;

-- The sentence shown when a line is refused. Written for whoever reads it (the
-- farmer on Request a Loan, the Manager or Officer on Issue New Loan / approval).
CREATE OR REPLACE FUNCTION public._loan_capital_refusal(p_item text, p_value numeric, p_capital numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_capital <= 0 THEN
      'Loan not allowed: the Capital Share is ₱0.00, so no loan item can be borrowed yet.'
    ELSE
      'Loan not allowed: ' || COALESCE(p_item, 'this item') || ' is worth ₱' ||
      to_char(p_value, 'FM999,999,990.00') || ', which is more than the Capital Share of ₱' ||
      to_char(p_capital, 'FM999,999,990.00') || '. Only items worth up to ₱' ||
      to_char(p_capital, 'FM999,999,990.00') || ' can be borrowed.'
  END;
$$;
REVOKE ALL ON FUNCTION public._loan_capital_refusal(text, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- ═══ 2. A loan being issued ═══════════════════════════════════════════════
-- The value is the larger of the saved line total and quantity x unit price, so a
-- line total sent smaller than its quantity and price cannot get past the rule.
CREATE OR REPLACE FUNCTION public._enforce_loan_item_capital()
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
  SELECT fl.farmer_id INTO v_farmer FROM farmer_loans fl WHERE fl.id = NEW.loan_id;
  IF v_farmer IS NULL THEN
    RETURN NEW;
  END IF;

  v_value   := GREATEST(COALESCE(NEW.line_total, 0),
                        round(COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_price, 0), 2));
  v_capital := public._loan_capital_share(v_farmer, true);

  IF v_value > v_capital THEN
    RAISE EXCEPTION '%', public._loan_capital_refusal(NEW.item_name, v_value, v_capital);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_loan_items_capital ON public.farmer_loan_items;
CREATE TRIGGER trg_farmer_loan_items_capital
  BEFORE INSERT ON public.farmer_loan_items
  FOR EACH ROW EXECUTE FUNCTION public._enforce_loan_item_capital();

-- ═══ 3. A request being made ══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._enforce_loan_request_item_capital()
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
  SELECT lr.farmer_id INTO v_farmer FROM loan_requests lr WHERE lr.id = NEW.request_id;
  IF v_farmer IS NULL THEN
    RETURN NEW;
  END IF;

  v_value   := GREATEST(COALESCE(NEW.line_total, 0),
                        round(COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_price, 0), 2));
  v_capital := public._loan_capital_share(v_farmer, true);

  IF v_value > v_capital THEN
    RAISE EXCEPTION '%', public._loan_capital_refusal(NEW.item_name, v_value, v_capital);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loan_request_items_capital ON public.loan_request_items;
CREATE TRIGGER trg_loan_request_items_capital
  BEFORE INSERT ON public.loan_request_items
  FOR EACH ROW EXECUTE FUNCTION public._enforce_loan_request_item_capital();

-- ═══ 4. What the screens show ═════════════════════════════════════════════
-- capital_share    the farmer's current Capital Share
-- max_item_value   the most one loan item can be worth (= the Capital Share today;
--                  kept as its own column so the rule lives here, not in the app)
-- A farmer reads their own; a Manager / Officer reads any farmer's.
CREATE OR REPLACE FUNCTION public.get_loan_capital_standing(p_farmer_id uuid DEFAULT NULL)
RETURNS TABLE (capital_share numeric, max_item_value numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target  uuid;
  v_capital numeric;
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
  RETURN QUERY SELECT v_capital, v_capital;
END;
$$;
REVOKE ALL ON FUNCTION public.get_loan_capital_standing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_loan_capital_standing(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Both triggers and the three functions exist (expect 2 rows, then 4 rows):
--    SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
--      AND tgname IN ('trg_farmer_loan_items_capital', 'trg_loan_request_items_capital');
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('_loan_capital_share', '_loan_capital_refusal', 'get_loan_capital_standing', '_enforce_loan_item_capital', '_enforce_loan_request_item_capital');
-- 2. The capital is read with a lock (expect true):
--    SELECT pg_get_functiondef('public._loan_capital_share(uuid,boolean)'::regprocedure) ILIKE '%FOR SHARE%';
-- 3. issue_loan, submit_loan_request and review_loan_request were NOT replaced (expect false, false):
--    SELECT pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%_loan_capital_share%' AS issue_loan_changed,
--           (SELECT prosrc ILIKE '%_loan_capital_share%' FROM pg_proc WHERE proname = 'review_loan_request' AND pronamespace = 'public'::regnamespace) AS review_changed;
-- 4. Loans and requests that already exist were not touched (counts only):
--    SELECT (SELECT count(*) FROM public.farmer_loans) AS loans, (SELECT count(*) FROM public.loan_requests) AS requests;
-- 5. What a given farmer can borrow right now (replace the id; run as staff in the app,
--    or compare with the ledger here):
--    SELECT m.farmer_id, m.total_contribution AS capital_share,
--           (SELECT greatest(sum(amount), 0) FROM public.capital_contribution_events e WHERE e.farmer_id = m.farmer_id) AS ledger_total
--    FROM public.member_capital_shares m WHERE m.farmer_id = '<farmer uuid>';
--    (the two numbers must be equal; if not, the ledger trigger is the thing to look at, not this script)
--
-- DECISION (not made by this script — it follows the wording "a loan item whose value
-- does not exceed the Capital Share"):
--   * The rule is per ITEM LINE. A farmer with 500 could still borrow five different
--     items worth 500 each in one loan, or take a second loan the next day.
--   * If the cooperative wants the whole LOAN (all lines together) capped at the Capital
--     Share, or the farmer's total outstanding balance included, replace
--     _enforce_loan_item_capital with a version that adds the other lines of the same
--     loan (and, for the balance, the unpaid part of the farmer's other loans). The
--     screens only need their wording changed; they ask this database for the limit.
-- ─────────────────────────────────────────────────────────────────────────
