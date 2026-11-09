-- ============================================================
-- SAGANA — Program Management rework, PHASE 6:
--          FAILED-PROGRAM ASSISTANCE (separate from loans)
--
-- NOT APPLIED — run it yourself in the Supabase SQL editor, once, AFTER
-- …_p6_harvest_return_resolutions.sql. One transaction.
--
-- A Farmer whose program outcome was finalized as FAILED may ask the cooperative
-- for assistance: items from the active Loan Item Catalog (is_loan_eligible and
-- in stock). Staff approve or reject it in Loan Requests.
--
-- ASSISTANCE IS NOT A LOAN. It lives in its own tables and this script does not
-- touch farmer_loans, loan_requests, loan payments, due dates, overdue logic or
-- any loan total. Nothing here creates a debt, a repayment schedule or a penalty.
--
-- WHAT IT ADDS
--   program_assistance_requests   the request: LQR-… number, LRN-… on approval
--   program_assistance_items      the items asked for (name/unit/price snapshot)
--   submit_assistance_request()   Farmer (failed outcome, rules checked here)
--   cancel_my_assistance_request()  Farmer, while it is still pending
--   review_assistance_request()   Manager or Officer: approve (stock is checked
--                                 and deducted in the same transaction) / reject
--   get_my_assistance_options()   which of my failed outcomes may ask, and why not
--   get_my_assistance_requests()  my requests (no staff identity)
--   get_assistance_requests()     staff list
--   set_assistance_setting()      Manager only: limits and deadline (OFF by default)
--
-- POLICY THAT IS NOT YET DECIDED STAYS OFF (NULL), nothing is invented:
--   assist_max_requests_per_failure   how many requests one failed outcome may make
--   assist_request_window_days        days after the outcome during which to ask
--   (repayment terms: none are recorded; assistance carries no repayment)
-- The only fixed rule is duplicate protection: one PENDING request per failed
-- outcome at a time.
--
-- A resolution (Pending / Closed / Reassessment / Referred) NEVER blocks a request.
--
-- CODE-prefixed errors: ASSIST_NOT_ELIGIBLE  ASSIST_LIMIT  ASSIST_ITEMS  NOT_ALLOWED
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_settings') IS NULL THEN
    RAISE EXCEPTION 'Run the Proposal 12 script (…_p6_harvest_return_resolutions.sql) first.';
  END IF;
  IF to_regprocedure('public.next_loan_request_reference(timestamptz)') IS NULL
     OR to_regprocedure('public.next_loan_reference(timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'The loan request and loan reference scripts must be applied first.';
  END IF;
END $$;

-- Policy values, OFF until the cooperative decides.
INSERT INTO public.program_settings (key, numeric_value) VALUES
  ('assist_max_requests_per_failure', NULL),
  ('assist_request_window_days',      NULL)
ON CONFLICT (key) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 1. Tables
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.program_assistance_requests (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number       TEXT NOT NULL UNIQUE,            -- LQR-YYYYMMDD-A001
  assistance_reference TEXT UNIQUE,                     -- LRN-YYYYMMDD-… once approved
  program_id           UUID NOT NULL REFERENCES public.cooperative_programs(id),
  program_member_id    UUID NOT NULL REFERENCES public.program_members(id),
  farmer_id            UUID NOT NULL,
  farmer_name          TEXT,
  status               TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  message              TEXT,
  review_note          TEXT,
  reviewed_by          UUID,
  reviewed_by_name     TEXT,
  reviewed_by_role     TEXT,
  reviewed_at          TIMESTAMPTZ,
  cancelled_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT assist_approved_has_reference
    CHECK (status <> 'approved' OR assistance_reference IS NOT NULL),
  CONSTRAINT assist_rejected_has_note
    CHECK (status <> 'rejected' OR (review_note IS NOT NULL AND btrim(review_note) <> ''))
);
CREATE INDEX IF NOT EXISTS program_assistance_requests_farmer ON public.program_assistance_requests (farmer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS program_assistance_requests_status ON public.program_assistance_requests (status, created_at DESC);
-- Duplicate protection (not policy): one pending request per failed outcome.
CREATE UNIQUE INDEX IF NOT EXISTS program_assistance_one_pending
  ON public.program_assistance_requests (program_member_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.program_assistance_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id        UUID NOT NULL REFERENCES public.program_assistance_requests(id),
  inventory_item_id UUID NOT NULL,
  item_name         TEXT NOT NULL,
  unit              TEXT NOT NULL,
  quantity          NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  unit_price        NUMERIC(12,2),                      -- catalog price at the time, for information
  UNIQUE (request_id, inventory_item_id)
);

DROP TRIGGER IF EXISTS trg_updated_at ON public.program_assistance_requests;
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.program_assistance_requests
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Requests are kept for good.
CREATE OR REPLACE FUNCTION public._program_assistance_no_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'An assistance request is kept permanently and cannot be deleted.';
END $$;
DROP TRIGGER IF EXISTS trg_no_delete ON public.program_assistance_requests;
CREATE TRIGGER trg_no_delete BEFORE DELETE ON public.program_assistance_requests
  FOR EACH ROW EXECUTE FUNCTION public._program_assistance_no_delete();
DROP TRIGGER IF EXISTS trg_no_delete ON public.program_assistance_items;
CREATE TRIGGER trg_no_delete BEFORE DELETE ON public.program_assistance_items
  FOR EACH ROW EXECUTE FUNCTION public._program_assistance_no_delete();

DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_assistance_requests;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE OR DELETE ON public.program_assistance_requests
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('loans', '');

ALTER TABLE public.program_assistance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_assistance_items    ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "assistance: staff read" ON public.program_assistance_requests;
CREATE POLICY "assistance: staff read" ON public.program_assistance_requests
  FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "assistance items: staff read" ON public.program_assistance_items;
CREATE POLICY "assistance items: staff read" ON public.program_assistance_items
  FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.program_assistance_requests, public.program_assistance_items
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.program_assistance_requests, public.program_assistance_items TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. Eligibility (one place, used by the screen and by submit)
-- ════════════════════════════════════════════════════════════
-- Returns NULL when the Farmer may ask, otherwise why not:
--   not_eligible | pending | limit
CREATE OR REPLACE FUNCTION public._assistance_blocker(p_member_id UUID, p_farmer UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m      program_members%ROWTYPE;
  v_max    NUMERIC;
  v_days   NUMERIC;
  v_count  INTEGER;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.farmer_id IS DISTINCT FROM p_farmer
     OR v_m.status <> 'active' OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RETURN 'not_eligible';
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  SELECT numeric_value INTO v_max  FROM program_settings WHERE key = 'assist_max_requests_per_failure';
  SELECT numeric_value INTO v_days FROM program_settings WHERE key = 'assist_request_window_days';
  IF v_max IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM program_assistance_requests
     WHERE program_member_id = p_member_id AND status IN ('pending', 'approved');
    IF v_count >= v_max THEN RETURN 'limit'; END IF;
  END IF;
  IF v_days IS NOT NULL AND v_m.outcome_recorded_at IS NOT NULL
     AND NOW() > v_m.outcome_recorded_at + (v_days || ' days')::INTERVAL THEN
    RETURN 'limit';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. Farmer: submit / cancel
-- ════════════════════════════════════════════════════════════
-- p_items = [{"inventoryItemId": "...", "quantity": 2.5}, ...]. Names, units and
-- prices come from the catalog, never from the client.
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
    RAISE EXCEPTION 'ASSIST_LIMIT: A request for this program is already waiting for review.';
  ELSIF v_block = 'limit' THEN
    RAISE EXCEPTION 'ASSIST_LIMIT: The limit or deadline for assistance requests has been reached.';
  ELSIF v_block IS NOT NULL THEN
    RAISE EXCEPTION 'ASSIST_NOT_ELIGIBLE: Assistance can be requested for a program outcome that failed.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR jsonb_array_length(p_items) > 20 THEN
    RAISE EXCEPTION 'ASSIST_ITEMS: Choose between 1 and 20 items.';
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_m.program_id;
  v_no := public.next_loan_request_reference(NOW());

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

CREATE OR REPLACE FUNCTION public.cancel_my_assistance_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r program_assistance_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_r FROM program_assistance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_r.farmer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Request not found.';
  END IF;
  IF v_r.status <> 'pending' THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a request that is still waiting can be cancelled.';
  END IF;
  UPDATE program_assistance_requests SET status = 'cancelled', cancelled_at = NOW() WHERE id = p_request_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.cancel_my_assistance_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_assistance_request(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Staff: approve (stock is checked and deducted here) / reject
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.review_assistance_request(
  p_request_id UUID,
  p_decision   TEXT,            -- 'approved' | 'rejected'
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
    RAISE EXCEPTION 'NOT_ALLOWED: Choose approve or reject.';
  END IF;
  SELECT * INTO v_r FROM program_assistance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Request not found.';
  END IF;
  IF v_r.status <> 'pending' THEN
    RAISE EXCEPTION 'NOT_ALLOWED: This request was already reviewed or cancelled.';
  END IF;
  IF p_decision = 'rejected' AND v_note IS NULL THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Give a reason when rejecting a request.';
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

    v_ref := public.next_loan_reference(NOW());
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

-- ════════════════════════════════════════════════════════════
-- 5. Reads
-- ════════════════════════════════════════════════════════════
-- Which of my failed outcomes can ask for assistance (and why not, if not).
CREATE OR REPLACE FUNCTION public.get_my_assistance_options()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'program_member_id', pm.id,
           'program_id', pm.program_id,
           'program_name', cp.program_name,
           'blocker', public._assistance_blocker(pm.id, auth.uid())
         ) ORDER BY pm.outcome_recorded_at DESC NULLS LAST), '[]'::jsonb)
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.farmer_id = auth.uid() AND pm.status = 'active' AND pm.distribution_outcome = 'failed';
$$;
REVOKE ALL ON FUNCTION public.get_my_assistance_options() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_assistance_options() TO authenticated;

-- My requests: status, items, the LRN once approved, and the reason if rejected.
-- No staff name appears.
CREATE OR REPLACE FUNCTION public.get_my_assistance_requests()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'request_number', r.request_number,
           'assistance_reference', r.assistance_reference,
           'program_member_id', r.program_member_id,
           'program_name', cp.program_name,
           'status', r.status,
           'message', r.message,
           'rejection_reason', CASE WHEN r.status = 'rejected' THEN r.review_note END,
           'created_at', r.created_at,
           'reviewed_at', r.reviewed_at,
           'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                       'item_name', i.item_name, 'unit', i.unit, 'quantity', i.quantity) ORDER BY i.item_name)
                       FROM program_assistance_items i WHERE i.request_id = r.id), '[]'::jsonb)
         ) ORDER BY r.created_at DESC), '[]'::jsonb)
  FROM program_assistance_requests r
  JOIN cooperative_programs cp ON cp.id = r.program_id
  WHERE r.farmer_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.get_my_assistance_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_assistance_requests() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_assistance_requests(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can read assistance requests.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.created_at,
             to_jsonb(r) || jsonb_build_object(
               'program_name', cp.program_name,
               'items', COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.item_name)
                                    FROM program_assistance_items i WHERE i.request_id = r.id), '[]'::jsonb)
             ) AS j
        FROM program_assistance_requests r
        JOIN cooperative_programs cp ON cp.id = r.program_id
       WHERE p_status IS NULL OR r.status = p_status
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_assistance_requests(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assistance_requests(TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Policy values (Manager only; NULL = off)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_assistance_setting(p_key TEXT, p_value NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager can change this setting.';
  END IF;
  IF p_key NOT IN ('assist_max_requests_per_failure', 'assist_request_window_days') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Unknown setting.';
  END IF;
  IF p_value IS NOT NULL AND (p_value < 1 OR p_value <> trunc(p_value) OR p_value > 3650) THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Enter a whole number of 1 or more, or leave it empty to turn it off.';
  END IF;
  UPDATE program_settings SET numeric_value = p_value, updated_by = auth.uid(), updated_at = NOW()
   WHERE key = p_key;
END;
$function$;
REVOKE ALL ON FUNCTION public.set_assistance_setting(TEXT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_assistance_setting(TEXT, NUMERIC) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Officer permission gate: reviewing is a Loans action
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'review_assistance_request',     'loans'),
  ('table', 'program_assistance_requests',   'loans'),
  ('table', 'program_assistance_items',      'loans')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

-- ════════════════════════════════════════════════════════════
-- VERIFICATION (run after the script; read-only)
-- ════════════════════════════════════════════════════════════
-- V1  Tables and policy keys.
--   SELECT to_regclass('public.program_assistance_requests'), to_regclass('public.program_assistance_items');
--   SELECT key, numeric_value FROM program_settings ORDER BY key;   -- assist_* are NULL (off)
-- V2  Gate rows.
--   SELECT kind, name, module FROM staff_permission_targets WHERE name LIKE '%assistance%' ORDER BY 1,2;
-- V3  Loans untouched: nothing in the loan tables references assistance.
--   SELECT count(*) FROM farmer_loans;   -- note the number before and after approving a request: it must not change
-- V4  After an approval: stock moved once and the ledger row exists.
--   SELECT t.inventory_id, t.quantity, t.reference_id FROM inventory_transactions t
--    WHERE t.reference_type = 'program_assistance' ORDER BY t.created_at DESC LIMIT 10;
-- V5  One pending request per failed outcome (expect 0 rows).
--   SELECT program_member_id, count(*) FROM program_assistance_requests WHERE status = 'pending'
--    GROUP BY 1 HAVING count(*) > 1;
