-- ============================================================
-- SAGANA — Loan reference numbers: LRN-YYYYMMDD-XXXX
--
-- Until now a loan's reference was built inside issue_loan() as LN-YYYY-###
-- (year of the ISSUE DATE + a 3-digit counter found with MAX()+1 under an
-- advisory lock). It carried no month or day, and its year came from a date a
-- Manager can change. This script makes the database issue the number the same
-- way it issues Order numbers (supabase_schema_order_number.sql):
--
--     LRN-20261024-A001
--         |        |
--         |        +-- sequence for the YEAR: A001 ... A999, B001 ... Z999,
--         |            then AA001 ... (a letter block of 999 loans)
--         +----------- the date the loan was created (Philippine time)
--
--   * One counter per year; it starts again at A001 on 1 January (Philippine
--     time). The letter/number layout is the SAME function Orders use,
--     format_order_sequence(), so the two numbering schemes cannot drift apart.
--   * It is issued by a BEFORE INSERT trigger on farmer_loans, so it does not
--     matter which function or screen creates the loan. A value sent by a client
--     or by a function is ignored and replaced.
--   * The counter row is locked while a number is issued, so loans created at the
--     same moment get different numbers, in order, with no gaps (a number is only
--     used when its loan is saved: a rolled-back loan gives its number back).
--   * A loan reference can never be changed once it is set.
--   * issue_loan() no longer builds a number. It lets the trigger issue it and
--     reads it back from the saved row. Nothing else about issue_loan() changes:
--     it is the definition in batch9_01_decision_notices.sql (the latest in the
--     repo) with only the reference-number block replaced.
--
-- LOANS THAT ALREADY EXIST keep their reference (LN-YYYY-### or any older
-- style). Nothing is renumbered, updated or deleted. Their payments, items,
-- notifications and reports keep pointing at the same value.
--
-- The "date the loan was created" is farmer_loans.created_at (the moment the loan
-- is saved), not issued_date. A Manager may back-date the Issue Date by up to 30
-- days; that date is still shown separately and is not part of the reference.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end (and supabase_schema_loan_reference_number_test.sql).
-- Requires supabase_schema_order_number.sql (format_order_sequence) and
-- batch9_01_decision_notices.sql (or any later issue_loan) to be applied first.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Loans that exist now (they keep their reference):
--    SELECT count(*) AS loans_now FROM public.farmer_loans;
-- B. The reference styles in use today (informational):
--    SELECT CASE WHEN reference_no ~ '^LN-[0-9]{4}-[0-9]+$' THEN 'LN-YYYY-###'
--                WHEN reference_no ~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$' THEN 'LRN (new)'
--                ELSE 'other' END AS style, count(*)
--    FROM public.farmer_loans GROUP BY 1 ORDER BY 1;
-- C. Triggers already on farmer_loans (informational):
--    SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.farmer_loans'::regclass
--      AND NOT tgisinternal ORDER BY 1;
-- D. issue_loan() in the live database is the batch9 version (expect true):
--    SELECT pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure)
--           ILIKE '%A new loan (%';
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.farmer_loans') IS NULL THEN
    RAISE EXCEPTION 'public.farmer_loans is missing.';
  END IF;
  IF to_regprocedure('public.format_order_sequence(integer)') IS NULL THEN
    RAISE EXCEPTION 'format_order_sequence() is missing. Run supabase_schema_order_number.sql first.';
  END IF;
  IF to_regprocedure('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'issue_loan() is missing.';
  END IF;
END;
$$;

-- ═══ 1. The yearly counter ══════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.loan_reference_counters (
  year      INTEGER PRIMARY KEY CHECK (year BETWEEN 2000 AND 9999),
  last_seq  INTEGER NOT NULL CHECK (last_seq >= 0)
);

-- Internal: nobody reads or writes it from the app.
ALTER TABLE public.loan_reference_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.loan_reference_counters FROM PUBLIC, anon, authenticated;

-- ═══ 2. Issuing a number ════════════════════════════════════════════════
-- The year and the date are taken in Philippine time, so a loan saved just after
-- midnight there belongs to the new day and, on 1 January, the new year.
CREATE OR REPLACE FUNCTION public.next_loan_reference(p_at TIMESTAMPTZ DEFAULT NOW())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP;
  v_year  INTEGER;
  v_seq   INTEGER;
BEGIN
  v_local := p_at AT TIME ZONE 'Asia/Manila';
  v_year  := EXTRACT(YEAR FROM v_local)::INTEGER;

  -- One atomic statement: the first loan of a year creates the row at 1; every
  -- other loan locks the row, adds 1 and waits its turn behind any loan being
  -- saved at the same moment.
  INSERT INTO loan_reference_counters (year, last_seq)
  VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_seq = loan_reference_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;

  RETURN 'LRN-' || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END;
$$;

REVOKE ALL ON FUNCTION public.next_loan_reference(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- ═══ 3. Triggers on farmer_loans ════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.assign_loan_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Always issued here; whatever a client or a function sent is replaced.
  NEW.reference_no := public.next_loan_reference(COALESCE(NEW.created_at, NOW()));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_loans_assign_reference ON public.farmer_loans;
CREATE TRIGGER trg_farmer_loans_assign_reference
  BEFORE INSERT ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION public.assign_loan_reference();

CREATE OR REPLACE FUNCTION public.protect_loan_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.reference_no IS DISTINCT FROM OLD.reference_no THEN
    RAISE EXCEPTION 'A loan reference number cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_loans_protect_reference ON public.farmer_loans;
CREATE TRIGGER trg_farmer_loans_protect_reference
  BEFORE UPDATE OF reference_no ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION public.protect_loan_reference();

-- ═══ 4. issue_loan(): let the database issue the reference ═════════════
-- Copied from batch9_01_decision_notices.sql section 5. Changes, and only these:
--   * v_year / v_next_seq and the advisory lock + MAX()+1 block are removed;
--   * the INSERT no longer names reference_no (the trigger issues it) and reads
--     it back with RETURNING, so the notice and the returned row show the number
--     that was really saved.
-- Everything else (staff check, member and capital gates, item checks, replay by
-- idempotency key, stock deduction, inventory log, notice) is unchanged.

CREATE OR REPLACE FUNCTION public.issue_loan(p_farmer_id uuid, p_items jsonb, p_issued_date date, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_loan_id       UUID;
  v_total_value   NUMERIC := 0;
  v_item          JSONB;
  v_inventory_id  UUID;
  v_quantity      NUMERIC;
  v_unit_price    NUMERIC;
  v_line_total    NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_reference_no  TEXT;
  v_existing_id   UUID;
  v_existing_ref  TEXT;
  v_contribution  NUMERIC;
  v_minimum       NUMERIC;
  v_farmer_status TEXT;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Farmer membership-status gate (Admin-Loan Issue 1.3) — the target
  -- farmer must be an active member. Checked before the capital-share
  -- gate so a non-member gets a membership-specific error rather than a
  -- misleading capital-contribution one.
  SELECT status INTO v_farmer_status
  FROM user_roles
  WHERE user_id = p_farmer_id AND role = 'farmer';

  IF v_farmer_status IS NULL THEN
    RAISE EXCEPTION 'Farmer account not found';
  END IF;

  IF v_farmer_status <> 'active' THEN
    RAISE EXCEPTION 'Farmer is not an active cooperative member (status: %) and is not eligible for a loan', v_farmer_status;
  END IF;

  -- Capital-share loan eligibility — HARD block (Issue 4d). Runs before
  -- the replay check so a replayed call re-verifies too. The Issue-Loan
  -- screen shows its own warning banner; this is the backend authority.
  SELECT COALESCE(mcs.total_contribution, 0) INTO v_contribution
  FROM member_capital_shares mcs
  WHERE mcs.farmer_id = p_farmer_id;
  v_contribution := COALESCE(v_contribution, 0);

  SELECT COALESCE(lps.minimum_capital_contribution, 2000) INTO v_minimum
  FROM loan_policy_settings lps
  WHERE lps.id = 1;
  v_minimum := COALESCE(v_minimum, 2000);

  IF v_contribution < v_minimum THEN
    RAISE EXCEPTION
      'Farmer has not met the minimum capital contribution of % required for a loan (current contribution: %)',
      v_minimum, v_contribution;
  END IF;

  -- Input validation.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one loan item is required';
  END IF;

  IF p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity   := (v_item->>'quantity')::NUMERIC;
    v_unit_price := (v_item->>'unitPrice')::NUMERIC;
    v_line_total := (v_item->>'lineTotal')::NUMERIC;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero: %', v_item->>'itemName';
    END IF;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'Item unit price must not be negative: %', v_item->>'itemName';
    END IF;

    IF v_line_total IS NULL OR v_line_total < 0 THEN
      RAISE EXCEPTION 'Item line total must not be negative: %', v_item->>'itemName';
    END IF;
  END LOOP;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT fl.id, fl.reference_no INTO v_existing_id, v_existing_ref
      FROM farmer_loans fl
      WHERE fl.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing_id, v_existing_ref;
      RETURN;
    END IF;
  END IF;

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  -- reference_no is not named: trg_farmer_loans_assign_reference issues
  -- LRN-YYYYMMDD-XXXX as the row is saved, and RETURNING reads it back.
  INSERT INTO farmer_loans AS fl (
    farmer_id, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
  )
  RETURNING fl.id, fl.reference_no INTO v_loan_id, v_reference_no;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total)
    VALUES (
      v_loan_id,
      v_item->>'itemName',
      (v_item->>'quantity')::NUMERIC,
      v_item->>'unit',
      (v_item->>'unitPrice')::NUMERIC,
      (v_item->>'lineTotal')::NUMERIC
    );

    v_inventory_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    IF v_inventory_id IS NOT NULL THEN
      v_quantity := (v_item->>'quantity')::NUMERIC;

      SELECT quantity_on_hand, item_name INTO v_available, v_item_name
        FROM cooperative_inventory
        WHERE id = v_inventory_id
        FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item % no longer exists', v_inventory_id;
      END IF;

      IF v_available < v_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_item_name, v_available, v_quantity;
      END IF;

      UPDATE cooperative_inventory
      SET quantity_on_hand = quantity_on_hand - v_quantity
      WHERE id = v_inventory_id;

      INSERT INTO inventory_transactions (
        inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
      ) VALUES (
        v_inventory_id, 'loan_issued', -v_quantity, v_loan_id, 'loan', p_recorded_by
      );
    END IF;
  END LOOP;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'loan', 'Loan Issued',
    'A new loan (' || v_reference_no || ') worth ₱' ||
      to_char(v_total_value, 'FM999,999,990.00') || ' has been issued to you: ' ||
      COALESCE((SELECT string_agg(fli.item_name || ' x ' || to_char(fli.quantity, 'FM999,999,990.##') || ' ' || fli.unit, ', ' ORDER BY fli.item_name)
                FROM farmer_loan_items fli WHERE fli.loan_id = v_loan_id), 'no items recorded') || '.',
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$function$;

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Objects exist (expect 2 triggers, 3 functions, the counter table):
--    SELECT tgname FROM pg_trigger WHERE tgrelid='public.farmer_loans'::regclass
--      AND tgname IN ('trg_farmer_loans_assign_reference','trg_farmer_loans_protect_reference');
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('next_loan_reference','assign_loan_reference','protect_loan_reference');
--    SELECT to_regclass('public.loan_reference_counters');
-- 2. issue_loan() no longer builds LN- numbers (expect false) and still has the
--    notice body (expect true):
--    SELECT pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) LIKE '%''LN-''%' AS still_builds_ln,
--           pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%A new loan (%' AS has_notice;
-- 3. Loans from before were not touched (the count must equal pre-flight A, and
--    old references are unchanged):
--    SELECT count(*) FILTER (WHERE reference_no NOT LIKE 'LRN-%') AS old_loans,
--           count(*) FILTER (WHERE reference_no LIKE 'LRN-%')     AS new_loans
--    FROM public.farmer_loans;
-- 4. After issuing loans: every new reference has the right shape (expect 0 rows):
--    SELECT id, reference_no FROM public.farmer_loans
--    WHERE reference_no LIKE 'LRN-%' AND reference_no !~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$';
-- 5. No duplicates (expect 0 rows):
--    SELECT reference_no, count(*) FROM public.farmer_loans GROUP BY 1 HAVING count(*) > 1;
-- 6. The date in each new reference is the loan's creation date in Philippine
--    time (expect 0 rows):
--    SELECT id, reference_no, created_at FROM public.farmer_loans
--    WHERE reference_no LIKE 'LRN-%'
--      AND substr(reference_no, 5, 8) <> to_char(created_at AT TIME ZONE 'Asia/Manila', 'YYYYMMDD');
-- 7. The sequence restarts each year. For each year the counter should equal the
--    number of new loans of that year (a smaller count only means a loan was
--    deleted afterwards, which leaves its number unused):
--    SELECT c.year, c.last_seq,
--           (SELECT count(*) FROM public.farmer_loans l
--             WHERE l.reference_no LIKE 'LRN-' || c.year || '%') AS new_loans
--    FROM public.loan_reference_counters c ORDER BY c.year;
-- ─────────────────────────────────────────────────────────────────────────
