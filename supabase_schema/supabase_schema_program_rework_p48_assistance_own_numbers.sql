-- ============================================================
-- SAGANA — p48: assistance has its OWN numbers (it is not a loan, so it must not use the loan number series)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p47. No data is changed or deleted.
--
-- Review finding: submit_assistance_request() took its request number from the LOAN REQUEST series (LQR-…) and
-- review_assistance_request() took its approval reference from the LOAN series (LRN-…). So an assistance request
-- looked like a loan request, and every assistance request used up a real loan number (gaps in the loan numbering).
--
-- From now on:
--   request number         ASR-YYYYMMDD-A001   (own counter)
--   approval reference     ASA-YYYYMMDD-A001   (own counter)
-- Requests already made keep the numbers they have (LQR-… / LRN-…); nothing is renumbered.
--
-- Everything else about assistance is unchanged: its own tables, no debt, no repayment, no due date, no payment
-- fields; approving deducts the stock and writes the inventory log, and never touches farmer_loans.
-- Also here: the refusal messages match the new rule (assistance only after "Referred", one approved request).
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.review_assistance_request(uuid,text,text)') IS NULL
     OR to_regprocedure('public.format_order_sequence(integer)') IS NULL THEN
    RAISE EXCEPTION 'Apply the assistance script (p7) first.';
  END IF;
END $$;

-- 1. Own counters and numbers
CREATE TABLE IF NOT EXISTS public.assistance_counters (
  kind      TEXT    NOT NULL CHECK (kind IN ('request', 'approval')),
  year      INTEGER NOT NULL CHECK (year BETWEEN 2000 AND 9999),
  last_seq  INTEGER NOT NULL CHECK (last_seq >= 0),
  PRIMARY KEY (kind, year)
);
ALTER TABLE public.assistance_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.assistance_counters FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_assistance_number(p_kind TEXT, p_at TIMESTAMPTZ DEFAULT NOW())
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
  IF p_kind NOT IN ('request', 'approval') THEN
    RAISE EXCEPTION 'Unknown assistance number kind.';
  END IF;
  v_local := p_at AT TIME ZONE 'Asia/Manila';
  v_year  := EXTRACT(YEAR FROM v_local)::INTEGER;
  INSERT INTO assistance_counters (kind, year, last_seq)
  VALUES (p_kind, v_year, 1)
  ON CONFLICT (kind, year) DO UPDATE SET last_seq = assistance_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN CASE p_kind WHEN 'request' THEN 'ASR-' ELSE 'ASA-' END
         || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END;
$$;
REVOKE ALL ON FUNCTION public.next_assistance_number(TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- 2. Submit (as p7; own request number; refusal messages for the Referred-only rule)
CREATE OR REPLACE FUNCTION public.submit_assistance_request(
  p_program_member_id UUID,
  p_items             JSONB,
  p_message           TEXT DEFAULT NULL
) RETURNS TABLE (new_request_id UUID, new_request_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     UUID := auth.uid();
  v_m       program_members%ROWTYPE;
  v_block   TEXT;
  v_item    JSONB;
  v_inv     UUID;
  v_qty     NUMERIC;
  v_ci      RECORD;
  v_seen    UUID[] := ARRAY[]::UUID[];
  v_id      UUID := gen_random_uuid();
  v_no      TEXT;
  v_name    TEXT;
  v_prog    TEXT;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only an active Farmer can request assistance.';
  END IF;

  -- Lock the member row so two taps cannot both pass the checks.
  SELECT * INTO v_m FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  v_block := public._assistance_blocker(p_program_member_id, v_uid);
  IF v_block = 'pending' THEN
    RAISE EXCEPTION 'ASSIST_PENDING: A request for this program is already waiting for review.';
  ELSIF v_block = 'approved' THEN
    RAISE EXCEPTION 'ASSIST_LIMIT: Your assistance request for this program was already approved.';
  ELSIF v_block = 'limit' THEN
    RAISE EXCEPTION 'ASSIST_LIMIT: The limit or deadline for assistance requests has been reached.';
  ELSIF v_block IS NOT NULL THEN
    RAISE EXCEPTION 'ASSIST_NOT_ELIGIBLE: Assistance can be requested only after the cooperative refers you for assistance, while the program is still open.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR jsonb_array_length(p_items) > 20 THEN
    RAISE EXCEPTION 'ASSIST_ITEMS: Choose between 1 and 20 items.';
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_m.program_id;
  v_no := public.next_assistance_number('request', NOW());

  INSERT INTO program_assistance_requests
    (id, request_number, program_id, program_member_id, farmer_id, farmer_name, message)
  VALUES (v_id, v_no, v_m.program_id, v_m.id, v_uid, v_name, NULLIF(btrim(COALESCE(p_message, '')), ''));

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    v_qty := (v_item->>'quantity')::NUMERIC;
    IF v_inv IS NULL OR v_qty IS NULL OR v_qty <= 0 OR v_qty <> round(v_qty, 2) OR v_inv = ANY (v_seen) THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: Each item needs a quantity greater than zero, and can be chosen once.';
    END IF;
    v_seen := v_seen || v_inv;

    SELECT ci.item_name, ci.unit, ci.quantity_on_hand, ci.quantity_reserved, lim.unit_price
      INTO v_ci
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv AND lim.is_loan_eligible AND ci.is_active AND ci.archived_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: One of the items is not available for assistance.';
    END IF;
    IF v_ci.quantity_on_hand - v_ci.quantity_reserved < v_qty THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: % does not have enough stock.', v_ci.item_name;
    END IF;

    INSERT INTO program_assistance_items (request_id, inventory_item_id, item_name, unit, quantity, unit_price)
    VALUES (v_id, v_inv, v_ci.item_name, v_ci.unit, v_qty, v_ci.unit_price);
  END LOOP;

  PERFORM public.notify_staff('program', 'Assistance Request',
    COALESCE(v_name, 'A Farmer') || ' asked for assistance after the ' || COALESCE(v_prog, 'program') ||
      ' outcome (' || v_no || ').', '/admin/loans/requests');

  RETURN QUERY SELECT v_id, v_no;
END;
$function$;
REVOKE ALL ON FUNCTION public.submit_assistance_request(UUID, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_assistance_request(UUID, JSONB, TEXT) TO authenticated;

-- 3. Review (as p7; own approval reference)
CREATE OR REPLACE FUNCTION public.review_assistance_request(
  p_request_id UUID,
  p_decision   TEXT,            -- 'approved' | 'rejected' (shown as Disapproved)
  p_note       TEXT DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r     program_assistance_requests%ROWTYPE;
  v_note  TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name  TEXT;
  v_role  TEXT;
  v_ref   TEXT;
  v_it    RECORD;
  v_inv   cooperative_inventory%ROWTYPE;
  v_prog  TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can review an assistance request.';
  END IF;
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Choose approve or disapprove.';
  END IF;
  SELECT * INTO v_r FROM program_assistance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Request not found.';
  END IF;
  IF v_r.status <> 'pending' THEN
    RAISE EXCEPTION 'NOT_ALLOWED: This request was already reviewed or cancelled.';
  END IF;
  IF p_decision = 'rejected' AND v_note IS NULL THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Give a reason when disapproving a request.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_r.program_id;

  IF p_decision = 'approved' THEN
    -- Re-check the stock now (it may have changed since the Farmer asked), lock,
    -- deduct and write the ledger. Anything short makes the whole approval fail.
    FOR v_it IN SELECT * FROM program_assistance_items WHERE request_id = p_request_id ORDER BY inventory_item_id
    LOOP
      SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_it.inventory_item_id FOR UPDATE;
      IF NOT FOUND OR NOT v_inv.is_active OR v_inv.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'ASSIST_ITEMS: % is no longer available.', v_it.item_name;
      END IF;
      IF v_inv.quantity_on_hand - v_inv.quantity_reserved < v_it.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_it.item_name, v_inv.quantity_on_hand - v_inv.quantity_reserved, v_it.quantity;
      END IF;
      UPDATE cooperative_inventory
         SET quantity_on_hand = quantity_on_hand - v_it.quantity
       WHERE id = v_it.inventory_item_id;
      INSERT INTO inventory_transactions
        (inventory_id, transaction_type, quantity, reference_id, reference_type, notes, recorded_by)
      VALUES (v_it.inventory_item_id, 'program_distribution', -v_it.quantity, p_request_id,
              'program_assistance', 'Assistance after a failed program outcome', auth.uid());
    END LOOP;

    v_ref := public.next_assistance_number('approval', NOW());
    UPDATE program_assistance_requests
       SET status = 'approved', assistance_reference = v_ref, review_note = v_note,
           reviewed_by = auth.uid(), reviewed_by_name = v_name, reviewed_by_role = v_role, reviewed_at = NOW()
     WHERE id = p_request_id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (v_r.farmer_id, 'program', 'Assistance Approved',
            'Your assistance request ' || v_r.request_number || ' for ' || COALESCE(v_prog, 'your program') ||
              ' was approved (' || v_ref || ').', FALSE, NOW(), '/farmer/profile/programs/enrolled');
    RETURN v_ref;
  END IF;

  UPDATE program_assistance_requests
     SET status = 'rejected', review_note = v_note,
         reviewed_by = auth.uid(), reviewed_by_name = v_name, reviewed_by_role = v_role, reviewed_at = NOW()
   WHERE id = p_request_id;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Assistance Request Not Approved',
          'Your assistance request ' || v_r.request_number || ' was not approved.', FALSE, NOW(),
          '/farmer/profile/programs/enrolled');
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.review_assistance_request(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_assistance_request(UUID, TEXT, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK 1 (the two functions no longer call the loan number series; expect 0 rows):
--   SELECT proname FROM pg_proc
--    WHERE proname IN ('submit_assistance_request', 'review_assistance_request')
--      AND (prosrc ILIKE '%next_loan_request_reference%' OR prosrc ILIKE '%next_loan_reference%');
-- CHECK 2 (assistance never touches the loan tables; expect 0):
--   SELECT count(*) FROM pg_proc
--    WHERE proname IN ('submit_assistance_request', 'review_assistance_request')
--      AND (prosrc ILIKE '%farmer_loans%' OR prosrc ILIKE '%loan_requests%');
