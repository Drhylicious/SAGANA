-- ============================================================
-- SAGANA — p42: a loan request can be linked to the Failed-program referral it came from
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p41. Nothing is deleted. The only data
-- change is step 4: it links an existing Pending/Approved request to its referral when that is unambiguous.
--
-- Why: after "Referred for Loan Assessment" the Farmer taps Request a loan on the program card. Until now the
-- request was not tied to the program, so the card could not show that a request was already sent. This script:
--   1. adds loan_requests.program_member_id (empty for every normal request, which is unchanged);
--   2. lets submit_loan_request take that link, and checks it: the Farmer's own, active, Failed, and the latest
--      decision is Referred for Loan Assessment;
--   3. refuses a second request for the same referral while one is Pending or already Approved
--      (Disapproved or Cancelled lets the Farmer ask again);
--   4. adds get_my_program_loan_requests() so the card can show the status of the latest linked request.
--
-- NOT TOUCHED: loan items, prices, stock, loan calculations, the approval workflow, and every existing request.
-- The old 3-argument submit_loan_request is replaced by one with an extra optional argument, so the app that is
-- already running keeps working.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.loan_requests') IS NULL THEN
    RAISE EXCEPTION 'Apply the farmer loan requests script first.';
  END IF;
  IF to_regprocedure('public._assistance_blocker(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Apply p40/p41 first.';
  END IF;
END $$;

-- ═══ 1. The link ═══════════════════════════════════════════════════════════
ALTER TABLE public.loan_requests
  ADD COLUMN IF NOT EXISTS program_member_id UUID REFERENCES public.program_members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_loan_requests_program_member
  ON public.loan_requests (program_member_id) WHERE program_member_id IS NOT NULL;

-- One Pending request per referral, even if two taps race.
CREATE UNIQUE INDEX IF NOT EXISTS uq_loan_requests_one_pending_per_referral
  ON public.loan_requests (program_member_id)
  WHERE program_member_id IS NOT NULL AND status = 'pending';

-- ═══ 2. Submit, with the optional link ═════════════════════════════════════
DROP FUNCTION IF EXISTS public.submit_loan_request(JSONB, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.submit_loan_request(
  p_items             JSONB,
  p_notes             TEXT DEFAULT NULL,
  p_idempotency_key   TEXT DEFAULT NULL,
  p_program_member_id UUID DEFAULT NULL
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
  v_member     program_members%ROWTYPE;
  v_latest     TEXT;
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

  -- The referral this request comes from (optional).
  IF p_program_member_id IS NOT NULL THEN
    SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id;
    IF NOT FOUND OR v_member.farmer_id IS DISTINCT FROM v_uid
       OR v_member.status <> 'active' OR COALESCE(v_member.distribution_outcome, '') <> 'failed' THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_INVALID';
    END IF;
    SELECT f.resolution INTO v_latest FROM program_failure_resolutions f
     WHERE f.program_member_id = p_program_member_id ORDER BY f.created_at DESC LIMIT 1;
    IF v_latest IS DISTINCT FROM 'referred_for_loan_assessment' THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_INVALID';
    END IF;
    IF EXISTS (SELECT 1 FROM loan_requests lr
                WHERE lr.program_member_id = p_program_member_id
                  AND lr.status IN ('pending', 'approved')) THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_ALREADY_REQUESTED';
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

  INSERT INTO loan_requests AS lr (farmer_id, status, total_value, notes, idempotency_key, program_member_id)
  VALUES (v_uid, 'pending', v_total, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_idempotency_key, p_program_member_id)
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
    jsonb_build_object('total', v_total, 'items', jsonb_array_length(p_items),
                       'program_member_id', p_program_member_id));

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
REVOKE ALL ON FUNCTION public.submit_loan_request(JSONB, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_loan_request(JSONB, TEXT, TEXT, UUID) TO authenticated;

-- ═══ 3. What the program card shows ════════════════════════════════════════
-- The latest request linked to each of the Farmer's referrals. A Cancelled request is left out, so the card
-- offers the button again.
CREATE OR REPLACE FUNCTION public.get_my_program_loan_requests()
RETURNS TABLE (
  program_member_id UUID,
  request_id        UUID,
  request_no        TEXT,
  status            TEXT,
  requested_at      TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT ON (lr.program_member_id)
         lr.program_member_id, lr.id, lr.request_no, lr.status, lr.requested_at
    FROM loan_requests lr
   WHERE lr.farmer_id = auth.uid()
     AND lr.program_member_id IS NOT NULL
     AND lr.status <> 'cancelled'
   ORDER BY lr.program_member_id, lr.requested_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_my_program_loan_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_program_loan_requests() TO authenticated;

-- ═══ 4. Link the requests that were sent before this script ════════════════
-- A request sent from the Referred card before p42 has no link, so the card cannot see it. Link it only when it is
-- unambiguous: the Farmer has exactly ONE active Failed program whose latest decision is Referred for Loan
-- Assessment, and the request was sent after that decision. Only the newest such Pending or Approved request is
-- linked (the one-Pending-per-referral rule). Anything unclear is left alone.
WITH referred AS (
  SELECT pm.id AS member_id, pm.farmer_id,
         (SELECT f.created_at FROM program_failure_resolutions f
           WHERE f.program_member_id = pm.id ORDER BY f.created_at DESC LIMIT 1) AS decided_at
    FROM program_members pm
   WHERE pm.status = 'active' AND pm.distribution_outcome = 'failed'
     AND (SELECT f.resolution FROM program_failure_resolutions f
           WHERE f.program_member_id = pm.id ORDER BY f.created_at DESC LIMIT 1) = 'referred_for_loan_assessment'
),
single AS (
  SELECT farmer_id, min(member_id::text)::uuid AS member_id, min(decided_at) AS decided_at
    FROM referred GROUP BY farmer_id HAVING count(*) = 1
),
pick AS (
  SELECT DISTINCT ON (s.member_id) lr.id AS request_id, s.member_id
    FROM single s
    JOIN loan_requests lr ON lr.farmer_id = s.farmer_id
   WHERE lr.program_member_id IS NULL
     AND lr.status IN ('pending', 'approved')
     AND lr.requested_at >= s.decided_at
     AND NOT EXISTS (SELECT 1 FROM loan_requests x
                      WHERE x.program_member_id = s.member_id AND x.status IN ('pending', 'approved'))
   ORDER BY s.member_id, lr.requested_at DESC
)
UPDATE loan_requests lr SET program_member_id = pick.member_id
  FROM pick WHERE lr.id = pick.request_id;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK 0 (which requests are now linked to a program):
--   SELECT request_no, status, program_member_id FROM public.loan_requests WHERE program_member_id IS NOT NULL;
-- CHECK 1 (expect 1 row, the 4-argument version only):
--   SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
--    WHERE proname = 'submit_loan_request' AND pronamespace = 'public'::regnamespace;
-- CHECK 2 (the new column exists; every existing request has it empty):
--   SELECT count(*) AS requests, count(program_member_id) AS linked FROM public.loan_requests;
