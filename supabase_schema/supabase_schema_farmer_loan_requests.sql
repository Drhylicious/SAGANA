-- ============================================================
-- SAGANA — Farmer loan requests, and the capital-share loan gate removed
--
-- PART 1  The ₱2,000 capital-share requirement is taken OUT of issue_loan().
--         Nothing replaces it: no new eligibility rule is introduced until the
--         cooperative confirms one. What still applies to a loan, as before: the
--         farmer must be an ACTIVE member, every item must have enough stock, the
--         monthly payment must be above zero. loan_policy_settings and
--         loan_capital_eligibility() are left exactly as they are (unused by loans).
--
-- PART 2  A Farmer can REQUEST a loan from the existing loan item catalog
--         (loan_items_master -> cooperative_inventory). The request is reviewed by
--         a Manager or Officer, who approves or disapproves it.
--
--   Farmer   list_loanable_items()      the catalog with the live stock on hand
--            submit_loan_request()      items + quantities; stock is checked on the
--                                       server (zero or too little stock is refused)
--            cancel_loan_request()      withdraw a request that is still Pending
--            get_my_loan_requests()     the farmer's own requests (no staff identity)
--   Staff    review_loan_request()      approve (issues the loan through the SAME
--                                       issue_loan() every loan uses, so stock,
--                                       inventory log, reference number and notice are
--                                       unchanged) or disapprove (a reason is required)
--
--   Stock is NOT held by a request (same as a loan today: stock leaves the shelf only
--   when the loan is issued). Stock is checked when the request is made AND again
--   when it is approved; if it ran out in between, the approval is refused with the
--   item named and nothing changes.
--
-- PART 3  WHO DID WHAT (staff only)
--   The existing workflow_events table (supabase_schema_listing_edit_approval.sql)
--   now also records 'loan_request' (submitted / approved / disapproved / cancelled)
--   and 'loan' (issued / payment_recorded / overdue / paid) with auth.uid() as the
--   actor, their role and the time. A Farmer has no access to that table. A Farmer
--   sees "Cooperative", never a staff name. loan_requests.reviewed_by is readable by
--   staff only (the Farmer reads their requests through get_my_loan_requests()).
--   History starts when this script is applied; earlier loans have no recorded
--   issuer and nothing is guessed.
--
-- Request numbers: LQR-YYYYMMDD-A001 (Philippine date; one counter per year; same
-- layout function Orders and Loans use).
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end (and supabase_schema_farmer_loan_requests_test.sql).
-- Requires, applied first:
--   supabase_schema_loan_reference_number.sql      (issue_loan with the LRN trigger)
--   supabase_schema_listing_edit_approval.sql      (workflow_events, _wf_log)
--   supabase_schema_phase2_notification_completeness.sql (notify_staff)
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run these first, each by itself) ─────────────
-- A. The three prerequisites (expect 3 rows):
--    SELECT 'issue_loan' AS item WHERE to_regprocedure('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)') IS NOT NULL
--    UNION ALL SELECT 'workflow_events' WHERE to_regclass('public.workflow_events') IS NOT NULL
--    UNION ALL SELECT 'lrn trigger' WHERE EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_farmer_loans_assign_reference');
-- B. The live issue_loan still has the capital rule (expect true before, false after):
--    SELECT pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure)
--           ILIKE '%minimum capital contribution%';
-- C. Loan items a Farmer would be offered right now:
--    SELECT ci.item_name, ci.unit, ci.quantity_on_hand, lim.unit_price
--    FROM loan_items_master lim JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
--    WHERE lim.is_loan_eligible AND ci.is_active ORDER BY 1;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'issue_loan() is missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_farmer_loans_assign_reference') THEN
    RAISE EXCEPTION 'Run supabase_schema_loan_reference_number.sql first (the loan reference trigger is missing).';
  END IF;
  IF to_regclass('public.workflow_events') IS NULL OR to_regprocedure('public._wf_log(text,uuid,text,text,text,text,jsonb,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first (workflow_events / _wf_log are missing).';
  END IF;
  IF to_regprocedure('public.notify_staff(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_phase2_notification_completeness.sql first (notify_staff is missing).';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
  IF to_regprocedure('public.format_order_sequence(integer)') IS NULL THEN
    RAISE EXCEPTION 'format_order_sequence() is missing. Run supabase_schema_order_number.sql first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'loan_items_master' AND column_name = 'inventory_item_id') THEN
    RAISE EXCEPTION 'loan_items_master.inventory_item_id is missing (loan catalog is not linked to inventory).';
  END IF;
END;
$$;

-- ═══ 1. workflow_events knows loan requests and loans ═════════════════════
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.workflow_events'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%entity_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.workflow_events DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.workflow_events
  ADD CONSTRAINT workflow_events_entity_type_check
  CHECK (entity_type IN ('listing', 'order', 'market_linking', 'market_linking_enrollment',
                         'loan_request', 'loan'));

-- ═══ 2. Request numbers: LQR-YYYYMMDD-A001 ════════════════════════════════
CREATE TABLE IF NOT EXISTS public.loan_request_counters (
  year      INTEGER PRIMARY KEY CHECK (year BETWEEN 2000 AND 9999),
  last_seq  INTEGER NOT NULL CHECK (last_seq >= 0)
);
ALTER TABLE public.loan_request_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.loan_request_counters FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_loan_request_reference(p_at TIMESTAMPTZ DEFAULT NOW())
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
  INSERT INTO loan_request_counters (year, last_seq)
  VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_seq = loan_request_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN 'LQR-' || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END;
$$;
REVOKE ALL ON FUNCTION public.next_loan_request_reference(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- ═══ 3. The request and its items ═════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.loan_requests (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  request_no      TEXT          NOT NULL UNIQUE,
  farmer_id       UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status          TEXT          NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'disapproved', 'cancelled')),
  total_value     NUMERIC(12,2) NOT NULL CHECK (total_value > 0),
  notes           TEXT,
  idempotency_key TEXT          UNIQUE,
  requested_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  -- The Manager / Officer who decided. Staff-readable only (see RLS below).
  reviewed_by     UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at     TIMESTAMPTZ,
  decision_note   TEXT,
  loan_id         UUID          REFERENCES public.farmer_loans(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT loan_requests_disapproval_needs_reason
    CHECK (status <> 'disapproved' OR (decision_note IS NOT NULL AND btrim(decision_note) <> ''))
);

CREATE TABLE IF NOT EXISTS public.loan_request_items (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id        UUID          NOT NULL REFERENCES public.loan_requests(id) ON DELETE CASCADE,
  inventory_item_id UUID          REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL,
  item_name         TEXT          NOT NULL,
  unit              TEXT          NOT NULL,
  quantity          NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
  unit_price        NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  line_total        NUMERIC(12,2) NOT NULL CHECK (line_total >= 0)
);

CREATE INDEX IF NOT EXISTS idx_loan_requests_farmer ON public.loan_requests (farmer_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_loan_requests_status ON public.loan_requests (status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_loan_request_items_request ON public.loan_request_items (request_id);

DROP TRIGGER IF EXISTS trg_loan_requests_updated_at ON public.loan_requests;
CREATE TRIGGER trg_loan_requests_updated_at
  BEFORE UPDATE ON public.loan_requests
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.assign_loan_request_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.request_no := public.next_loan_request_reference(COALESCE(NEW.created_at, NOW()));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loan_requests_assign_reference ON public.loan_requests;
CREATE TRIGGER trg_loan_requests_assign_reference
  BEFORE INSERT ON public.loan_requests
  FOR EACH ROW EXECUTE FUNCTION public.assign_loan_request_reference();

CREATE OR REPLACE FUNCTION public.protect_loan_request_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.request_no IS DISTINCT FROM OLD.request_no THEN
    RAISE EXCEPTION 'A loan request number cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loan_requests_protect_reference ON public.loan_requests;
CREATE TRIGGER trg_loan_requests_protect_reference
  BEFORE UPDATE OF request_no ON public.loan_requests
  FOR EACH ROW EXECUTE FUNCTION public.protect_loan_request_reference();

-- RLS: staff read, nobody writes directly. A Farmer reads their own requests only
-- through get_my_loan_requests(), which leaves the reviewer out.
ALTER TABLE public.loan_requests      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loan_request_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "loan_requests: staff reads" ON public.loan_requests;
CREATE POLICY "loan_requests: staff reads"
  ON public.loan_requests FOR SELECT TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "loan_request_items: staff reads" ON public.loan_request_items;
CREATE POLICY "loan_request_items: staff reads"
  ON public.loan_request_items FOR SELECT TO authenticated
  USING (public.is_staff());

REVOKE ALL ON public.loan_requests, public.loan_request_items FROM PUBLIC, anon;
GRANT SELECT ON public.loan_requests, public.loan_request_items TO authenticated;

-- ═══ 4. Who did what: loans and their payments ════════════════════════════
CREATE OR REPLACE FUNCTION public._wf_loan_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._wf_log('loan', NEW.id, 'issued', NULL, NEW.status, NULL,
      jsonb_build_object('reference', NEW.reference_no, 'total', NEW.total_value));
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public._wf_log('loan', NEW.id, NEW.status, OLD.status, NEW.status);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_loan ON public.farmer_loans;
CREATE TRIGGER trg_zz_wf_loan
  AFTER INSERT OR UPDATE OF status ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION public._wf_loan_trigger();

CREATE OR REPLACE FUNCTION public._wf_loan_payment_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._wf_log('loan', NEW.loan_id, 'payment_recorded', NULL, NULL, NULL,
    jsonb_build_object('amount', NEW.amount_paid, 'balance', NEW.running_balance));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_wf_loan_payment ON public.farmer_loan_payments;
CREATE TRIGGER trg_zz_wf_loan_payment
  AFTER INSERT ON public.farmer_loan_payments
  FOR EACH ROW EXECUTE FUNCTION public._wf_loan_payment_trigger();

-- ═══ 5. issue_loan(): the capital-share gate removed ══════════════════════
-- Copied from supabase_schema_loan_reference_number.sql section 4 (the latest
-- definition in the repo). The ONLY change: the "Capital-share loan eligibility"
-- block and its two variables are gone. Everything else is unchanged: staff check,
-- ACTIVE-member gate, item validation, replay by idempotency key, stock check and
-- deduction, inventory log, the LRN reference from the trigger, the farmer notice.
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
  v_farmer_status TEXT;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Farmer membership-status gate — the target farmer must be an active member.
  SELECT status INTO v_farmer_status
  FROM user_roles
  WHERE user_id = p_farmer_id AND role = 'farmer';

  IF v_farmer_status IS NULL THEN
    RAISE EXCEPTION 'Farmer account not found';
  END IF;

  IF v_farmer_status <> 'active' THEN
    RAISE EXCEPTION 'Farmer is not an active cooperative member (status: %) and is not eligible for a loan', v_farmer_status;
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

-- ═══ 6. The Farmer's side ═════════════════════════════════════════════════

-- 6a. The loan item catalog with live stock. Read-only; shows only loanable items.
CREATE OR REPLACE FUNCTION public.list_loanable_items()
RETURNS TABLE (
  loan_item_id      UUID,
  inventory_item_id UUID,
  item_name         TEXT,
  category          TEXT,
  unit              TEXT,
  unit_price        NUMERIC,
  quantity_on_hand  NUMERIC,
  image_url         TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF NOT (public.is_staff()
          OR EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = auth.uid() AND ur.role = 'farmer')) THEN
    RAISE EXCEPTION 'Only a farmer can browse the loan catalog.';
  END IF;

  RETURN QUERY
  SELECT lim.id, ci.id, ci.item_name::TEXT, ci.category::TEXT, ci.unit::TEXT,
         lim.unit_price::NUMERIC, ci.quantity_on_hand::NUMERIC, ci.image_url::TEXT
  FROM loan_items_master lim
  JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
  WHERE lim.is_loan_eligible AND ci.is_active
  ORDER BY ci.category, ci.item_name;
END;
$$;
REVOKE ALL ON FUNCTION public.list_loanable_items() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_loanable_items() TO authenticated;

-- 6b. Submit a request. p_items = [{"inventoryItemId": "...", "quantity": 2.5}, ...].
-- Prices and names come from the catalog, never from the client.
CREATE OR REPLACE FUNCTION public.submit_loan_request(
  p_items           JSONB,
  p_notes           TEXT DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS TABLE (new_request_id UUID, new_request_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        UUID := auth.uid();
  v_status     TEXT;
  v_item       JSONB;
  v_inv_id     UUID;
  v_qty        NUMERIC;
  v_price      NUMERIC;
  v_available  NUMERIC;
  v_name       TEXT;
  v_unit       TEXT;
  v_total      NUMERIC := 0;
  v_seen       UUID[] := ARRAY[]::UUID[];
  v_request    UUID;
  v_no         TEXT;
  v_existing   RECORD;
  v_farmer     TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  SELECT ur.status INTO v_status FROM user_roles ur WHERE ur.user_id = v_uid AND ur.role = 'farmer';
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Only a farmer can request a loan.';
  END IF;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'Only an active cooperative member can request a loan (status: %).', v_status;
  END IF;

  -- A replayed submission returns the request it already created.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT lr.id AS id, lr.request_no AS request_no INTO v_existing
      FROM loan_requests lr
     WHERE lr.idempotency_key = p_idempotency_key AND lr.farmer_id = v_uid;
    IF FOUND THEN
      RETURN QUERY SELECT v_existing.id, v_existing.request_no;
      RETURN;
    END IF;
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Choose at least one item.';
  END IF;
  IF jsonb_array_length(p_items) > 20 THEN
    RAISE EXCEPTION 'A request can have at most 20 items.';
  END IF;

  -- Pass 1: validate every line against the catalog and the stock on hand.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    v_qty    := (v_item->>'quantity')::NUMERIC;

    IF v_inv_id IS NULL THEN
      RAISE EXCEPTION 'Every item must be chosen from the loan catalog.';
    END IF;
    IF v_inv_id = ANY (v_seen) THEN
      RAISE EXCEPTION 'An item can appear only once in a request.';
    END IF;
    v_seen := v_seen || v_inv_id;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Enter a quantity greater than zero.';
    END IF;
    IF v_qty <> round(v_qty, 2) THEN
      RAISE EXCEPTION 'Use at most 2 decimal places for a quantity.';
    END IF;

    SELECT ci.item_name, ci.unit, ci.quantity_on_hand, lim.unit_price
      INTO v_name, v_unit, v_available, v_price
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv_id AND lim.is_loan_eligible AND ci.is_active
     LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'This item is not available for loans.';
    END IF;
    IF v_available <= 0 THEN
      RAISE EXCEPTION '% is out of stock.', v_name;
    END IF;
    IF v_qty > v_available THEN
      RAISE EXCEPTION 'Not enough stock for %: % % available, % requested.',
        v_name, to_char(v_available, 'FM999,999,990.##'), v_unit, to_char(v_qty, 'FM999,999,990.##');
    END IF;

    v_total := v_total + round(v_qty * v_price, 2);
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'The request total must be more than zero.';
  END IF;

  INSERT INTO loan_requests AS lr (farmer_id, status, total_value, notes, idempotency_key)
  VALUES (v_uid, 'pending', v_total, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_idempotency_key)
  RETURNING lr.id, lr.request_no INTO v_request, v_no;

  -- Pass 2: save the lines with the catalog's name, unit and price at this moment.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv_id := (v_item->>'inventoryItemId')::UUID;
    v_qty    := (v_item->>'quantity')::NUMERIC;
    SELECT ci.item_name, ci.unit, lim.unit_price INTO v_name, v_unit, v_price
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv_id
     LIMIT 1;
    INSERT INTO loan_request_items
      (request_id, inventory_item_id, item_name, unit, quantity, unit_price, line_total)
    VALUES
      (v_request, v_inv_id, v_name, v_unit, v_qty, v_price, round(v_qty * v_price, 2));
  END LOOP;

  PERFORM public._wf_log('loan_request', v_request, 'submitted', NULL, 'pending', NULL,
    jsonb_build_object('total', v_total, 'items', jsonb_array_length(p_items)));

  SELECT ui.full_name INTO v_farmer FROM user_information ui WHERE ui.user_id = v_uid;
  PERFORM public.notify_staff(
    'loan',
    'New Loan Request',
    COALESCE(v_farmer, 'A farmer') || ' requested a loan (' || v_no || ') worth ₱' ||
      to_char(v_total, 'FM999,999,990.00') || '. It is waiting for your review.',
    '/admin/loans/requests'
  );

  RETURN QUERY SELECT v_request, v_no;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_loan_request(JSONB, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_loan_request(JSONB, TEXT, TEXT) TO authenticated;

-- 6c. The Farmer withdraws a request that nobody has decided yet.
CREATE OR REPLACE FUNCTION public.cancel_loan_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req loan_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM loan_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_req.farmer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Loan request not found.';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending request can be cancelled (this one is %).', v_req.status;
  END IF;

  UPDATE loan_requests SET status = 'cancelled' WHERE id = p_request_id;
  PERFORM public._wf_log('loan_request', p_request_id, 'cancelled', 'pending', 'cancelled');
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_loan_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_loan_request(UUID) TO authenticated;

-- 6d. The Farmer's own requests. No reviewer, no staff identity: only that the
-- Cooperative decided, when, and why.
CREATE OR REPLACE FUNCTION public.get_my_loan_requests()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(r.j ORDER BY r.requested_at DESC), '[]'::jsonb)
  FROM (
    SELECT lr.requested_at,
           jsonb_build_object(
             'id', lr.id,
             'request_no', lr.request_no,
             'status', lr.status,
             'total_value', lr.total_value,
             'notes', lr.notes,
             'requested_at', lr.requested_at,
             'decided_at', lr.reviewed_at,
             'decision_note', lr.decision_note,
             'loan_reference', fl.reference_no,
             'items', COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                        'item_name', i.item_name, 'unit', i.unit, 'quantity', i.quantity,
                        'unit_price', i.unit_price, 'line_total', i.line_total)
                      ORDER BY i.item_name)
               FROM loan_request_items i WHERE i.request_id = lr.id), '[]'::jsonb)
           ) AS j
    FROM loan_requests lr
    LEFT JOIN farmer_loans fl ON fl.id = lr.loan_id
    WHERE lr.farmer_id = auth.uid()
  ) r;
$$;
REVOKE ALL ON FUNCTION public.get_my_loan_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_loan_requests() TO authenticated;

-- ═══ 7. The Manager / Officer decides ═════════════════════════════════════
-- p_decision: 'approve' | 'disapprove'.
--   approve     p_monthly_payment and p_next_payment_date are required (as when a
--               loan is issued by hand); p_issued_date defaults to today
--               (Philippine date). The loan is issued by issue_loan() with the
--               request's saved items and prices. Stock is checked again there.
--   disapprove  p_note (the reason) is required and is shown to the Farmer.
-- The deciding staff member is saved on the request and in workflow_events.
CREATE OR REPLACE FUNCTION public.review_loan_request(
  p_request_id        UUID,
  p_decision          TEXT,
  p_note              TEXT DEFAULT NULL,
  p_monthly_payment   NUMERIC DEFAULT NULL,
  p_next_payment_date DATE DEFAULT NULL,
  p_issued_date       DATE DEFAULT NULL
) RETURNS TABLE (out_status TEXT, out_loan_id UUID, out_reference_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req    loan_requests%ROWTYPE;
  v_note   TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_items  JSONB;
  v_issued DATE;
  v_loan   UUID;
  v_ref    TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can review a loan request.';
  END IF;
  IF p_decision NOT IN ('approve', 'disapprove') THEN
    RAISE EXCEPTION 'The decision must be approve or disapprove.';
  END IF;

  SELECT * INTO v_req FROM loan_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan request not found.';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'This request was already %.', v_req.status;
  END IF;

  IF p_decision = 'disapprove' THEN
    IF v_note IS NULL THEN
      RAISE EXCEPTION 'Enter the reason for disapproving this request.';
    END IF;

    UPDATE loan_requests
       SET status = 'disapproved', reviewed_by = auth.uid(), reviewed_at = NOW(), decision_note = v_note
     WHERE id = p_request_id;

    PERFORM public._wf_log('loan_request', p_request_id, 'disapproved', 'pending', 'disapproved', v_note);

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (v_req.farmer_id, 'loan', 'Loan Request Disapproved',
            'Your loan request ' || v_req.request_no || ' was not approved. Reason: ' || v_note,
            FALSE, NOW(), '/farmer/profile/loans');

    RETURN QUERY SELECT 'disapproved'::TEXT, NULL::UUID, NULL::TEXT;
    RETURN;
  END IF;

  -- approve
  IF p_monthly_payment IS NULL OR p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;
  IF p_next_payment_date IS NULL THEN
    RAISE EXCEPTION 'Choose the first payment date.';
  END IF;
  v_issued := COALESCE(p_issued_date, (NOW() AT TIME ZONE 'Asia/Manila')::DATE);

  IF EXISTS (SELECT 1 FROM loan_request_items i WHERE i.request_id = p_request_id AND i.inventory_item_id IS NULL) THEN
    RAISE EXCEPTION 'An item on this request was removed from inventory. Disapprove it and ask the farmer to request again.';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
           'inventoryItemId', i.inventory_item_id,
           'itemName',        i.item_name,
           'quantity',        i.quantity,
           'unit',            i.unit,
           'unitPrice',       i.unit_price,
           'lineTotal',       i.line_total) ORDER BY i.item_name)
    INTO v_items
    FROM loan_request_items i WHERE i.request_id = p_request_id;

  -- The one loan-issuing function: stock check + deduction, inventory log,
  -- reference number and the farmer's "Loan Issued" notice. If stock ran out
  -- since the request was made, this raises and nothing below happens.
  SELECT il.loan_id, il.reference_no INTO v_loan, v_ref
    FROM public.issue_loan(
      v_req.farmer_id, v_items, v_issued, p_monthly_payment, p_next_payment_date,
      'Loan request ' || v_req.request_no || COALESCE(' - ' || v_note, ''),
      auth.uid(), 'loan_request:' || p_request_id::TEXT
    ) il;

  UPDATE loan_requests
     SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(),
         decision_note = v_note, loan_id = v_loan
   WHERE id = p_request_id;

  PERFORM public._wf_log('loan_request', p_request_id, 'approved', 'pending', 'approved', v_note,
    jsonb_build_object('loan_reference', v_ref, 'total', v_req.total_value,
                       'monthly_payment', p_monthly_payment));

  RETURN QUERY SELECT 'approved'::TEXT, v_loan, v_ref;
END;
$$;
REVOKE ALL ON FUNCTION public.review_loan_request(UUID, TEXT, TEXT, NUMERIC, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_loan_request(UUID, TEXT, TEXT, NUMERIC, DATE, DATE) TO authenticated;

-- ═══ 8. Live screens for staff ════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
                     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'loan_requests') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.loan_requests;
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. The capital rule is gone from issue_loan (expect false) and the staff check,
--    stock check and idempotency are still there (expect true, true, true):
--    SELECT pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%minimum capital contribution%' AS still_has_capital_rule,
--           pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%is_staff()%' AS has_staff_check,
--           pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%Insufficient stock%' AS has_stock_check,
--           pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure) ILIKE '%idempotency_key%' AS has_idempotency;
-- 2. The new objects exist (expect 6 functions, 3 tables):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('list_loanable_items','submit_loan_request','cancel_loan_request','get_my_loan_requests','review_loan_request','next_loan_request_reference');
--    SELECT to_regclass('public.loan_requests'), to_regclass('public.loan_request_items'), to_regclass('public.loan_request_counters');
-- 3. A Farmer cannot read the tables directly (RLS: staff only). As a farmer this
--    returns 0 rows; as staff it returns every request:
--    SELECT count(*) FROM public.loan_requests;
-- 4. After a request is approved, its loan exists exactly once and the stock moved
--    once (expect 1 row per approved request):
--    SELECT lr.request_no, fl.reference_no, count(it.*) AS stock_moves
--    FROM loan_requests lr JOIN farmer_loans fl ON fl.id = lr.loan_id
--    LEFT JOIN inventory_transactions it ON it.reference_id = fl.id AND it.reference_type = 'loan'
--    WHERE lr.status = 'approved' GROUP BY 1, 2;
-- 5. Who decided each request (staff only):
--    SELECT lr.request_no, lr.status, ui.full_name AS decided_by, lr.reviewed_at
--    FROM loan_requests lr LEFT JOIN user_information ui ON ui.user_id = lr.reviewed_by
--    WHERE lr.status IN ('approved','disapproved') ORDER BY lr.reviewed_at DESC;
-- 6. The history rows for loans and requests:
--    SELECT entity_type, action, actor_role, created_at FROM workflow_events
--    WHERE entity_type IN ('loan_request','loan') ORDER BY created_at DESC LIMIT 20;
-- ─────────────────────────────────────────────────────────────────────────
