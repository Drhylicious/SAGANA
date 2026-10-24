-- ─────────────────────────────────────────────────────────────────────────────
-- batch9_01_decision_notices.sql
-- Follow-up to the notification review (notification_&_offline.md). Covers the
-- decisions approved on the review:
--   1. Account-created notice only for accounts an Admin creates (not self-
--      registration, not Officers, who cannot create accounts).
--   2. Admin edits to a Cooperative Market listing price notify the farmer.
--   3. Thriving outcome: a function records it and notifies the farmer.
--   4. Who cancelled: orders.cancelled_by ('buyer' or 'farmer') is stored when
--      a buyer or farmer cancels a pending order.
--   5. Loan-issued notice lists the loaned items and quantities.
--   6. BOD meeting notice: PLACEHOLDER only. Wording, timing and the meeting
--      date source are still undecided. Nothing calls it automatically.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 1. Account-created notice: admin-created accounts only ──────────────────
-- A self-registration runs while the new user is signed in, so auth.uid() equals
-- NEW.user_id and the notice is skipped. Only an Admin session creates accounts
-- for other people.
CREATE OR REPLACE FUNCTION public.fn_notify_account_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IN ('farmer', 'officer')
     AND NEW.user_id IS DISTINCT FROM auth.uid()
     AND public.is_platform_admin(auth.uid()) THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      NEW.user_id,
      'system',
      'Account Created',
      'Your SAGANA account was created by the cooperative admin. Sign in with your temporary password and change it to continue.',
      FALSE,
      NOW(),
      NULL
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ─── 2. Cooperative Market listing price edit notifies the farmer ───────────
CREATE OR REPLACE FUNCTION admin_update_listing_price(
  p_listing_id UUID,
  p_new_price DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_crop_type TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can edit listing prices';
  END IF;

  IF p_new_price IS NULL OR p_new_price <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than zero';
  END IF;

  SELECT ml.status, cm.crop_type, ml.farmer_id, ml.crop_name
    INTO v_status, v_crop_type, v_farmer_id, v_crop_name
  FROM marketplace_listings ml
  LEFT JOIN crop_master cm ON lower(cm.crop_name) = lower(ml.crop_name)
  WHERE ml.id = p_listing_id
  FOR UPDATE OF ml;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only live (approved) listings can have their price edited';
  END IF;

  IF v_crop_type IS DISTINCT FROM 'sp3_cooperative' THEN
    RAISE EXCEPTION 'Only Cooperative Market listings can have their price edited by an admin';
  END IF;

  UPDATE marketplace_listings SET price_per_kg = p_new_price WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'price', 'Cooperative Price Updated',
    'The cooperative changed the price of your ' || COALESCE(v_crop_name, 'listing') ||
      ' listing to ₱' || to_char(p_new_price, 'FM999999990.00') || '/kg.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_listing_price(UUID, DECIMAL) TO authenticated;

-- ─── 3. Thriving outcome: recorded by a function, farmer notified ───────────
CREATE OR REPLACE FUNCTION public.record_program_thriving_outcome(p_program_member_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id    UUID;
  v_program_name TEXT;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can record a program outcome';
  END IF;

  SELECT pm.farmer_id, cp.program_name
    INTO v_farmer_id, v_program_name
  FROM program_members pm
  LEFT JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.id = p_program_member_id
  FOR UPDATE OF pm;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;

  UPDATE program_members
  SET distribution_outcome = 'thriving',
      outcome_recorded_at = NOW()
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'program', 'Program Outcome: Thriving',
    'Your participation in ' || COALESCE(v_program_name, 'the program') ||
      ' was recorded as thriving.',
    FALSE, NOW(), '/farmer/profile/programs'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_program_thriving_outcome(uuid) TO authenticated;

-- ─── 4. Who cancelled: stored on the order ──────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancelled_by text
  CHECK (cancelled_by IN ('buyer', 'farmer'));

-- cancel_my_order: same rules as batch0_02, plus cancelled_by. A farmer who
-- placed the order is recorded as 'farmer'; everyone else as 'buyer'.
CREATE OR REPLACE FUNCTION public.cancel_my_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller      UUID := auth.uid();
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
  v_name        TEXT;
  v_role        TEXT;
BEGIN
  SELECT status, listing_id, quantity_kg, buyer_id
  INTO v_status, v_listing_id, v_quantity_kg, v_buyer_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'You can only cancel your own order';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending order can be cancelled (current: %)', v_status;
  END IF;

  SELECT role INTO v_role FROM user_roles WHERE user_id = v_caller;

  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_caller;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled',
      notes = COALESCE(p_reason, notes),
      cancelled_by = CASE WHEN v_role = 'farmer' THEN 'farmer' ELSE 'buyer' END
  WHERE id = p_order_id;

  PERFORM public.notify_staff(
    'order',
    'Order Cancelled by ' || CASE WHEN v_role = 'farmer' THEN 'Farmer' ELSE 'Buyer' END,
    COALESCE(v_name, 'A buyer') || ' cancelled a pending order for ' || COALESCE(v_crop_name, 'produce') || '.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Cancelled',
    COALESCE(v_name, 'A buyer') || ' cancelled their order for your ' || COALESCE(v_crop_name, 'produce') || ' listing.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.cancel_my_order(uuid, text) TO authenticated;

-- ─── 6. BOD meeting notice: PLACEHOLDER (not scheduled) ─────────────────────
-- Wording, timing and the source of the meeting date are pending decision.
-- Called by hand with the meeting date. Notifies active farmers and the staff.
CREATE OR REPLACE FUNCTION public.notify_bod_meeting_near(p_meeting_date date)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can send this notice';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'loan', 'BOD Meeting Coming Up',
         '[PLACEHOLDER] The next BOD meeting is on ' || to_char(p_meeting_date, 'Mon DD, YYYY') || '.',
         FALSE, NOW(), '/farmer/profile/loans'
  FROM user_roles ur
  WHERE ur.role = 'farmer' AND ur.status = 'active';
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'system', 'BOD Meeting Coming Up',
         '[PLACEHOLDER] The next BOD meeting is on ' || to_char(p_meeting_date, 'Mon DD, YYYY') || '.',
         FALSE, NOW(), '/admin/loans'
  FROM user_roles ur
  WHERE ur.role IN ('admin', 'officer');

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_bod_meeting_near(date) TO authenticated;

-- ─── 5. Loan-issued notice lists the items ──────────────────────────────────
-- issue_loan is copied from supabase_schema_role_based_staff_access.sql (the
-- latest definition in the repo). Only the notice body changes: the items are
-- read from farmer_loan_items, which is already written before the notice.

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
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
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

  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fl.reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans fl
  WHERE fl.reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
  )
  RETURNING id INTO v_loan_id;

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

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select proname from pg_proc where proname in ('record_program_thriving_outcome','notify_bod_meeting_near');   -- 2 rows
--   select column_name from information_schema.columns where table_name = 'orders' and column_name = 'cancelled_by';  -- 1 row
--   select prosrc ilike '%is_platform_admin(auth.uid())%' from pg_proc where proname = 'fn_notify_account_created';  -- true

-- ─── 7. Realtime for forced sign-out (approved) ─────────────────────────────
-- The app listens to its own user_roles row, so a suspension signs the user
-- out straight away. Without this, the change is only seen at the next resume
-- or Sync. Adds the table to the realtime publication only if it is not there.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'user_roles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_roles;
  END IF;
END $$;

-- ─── 8. Reference price notice: says what changed ───────────────────────────
-- Replaces the three-argument notify_price_update (supabase_schema_phase2_
-- notification_completeness.sql). The new p_previous_price is optional, so an
-- older caller still works. A first price says "set"; a raised price says
-- "increased from ... to ..."; a lowered price says "decreased from ...". A
-- save that leaves the price unchanged sends nothing.
DROP FUNCTION IF EXISTS public.notify_price_update(TEXT, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.notify_price_update(
  p_crop_name TEXT,
  p_new_price NUMERIC,
  p_unit TEXT,
  p_previous_price NUMERIC DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_change TEXT;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can announce price updates';
  END IF;

  IF p_previous_price IS NOT NULL AND p_previous_price = p_new_price THEN
    RETURN 0;
  END IF;

  v_change := CASE
    WHEN p_previous_price IS NULL THEN
      'set the reference price of ' || p_crop_name || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
    WHEN p_new_price > p_previous_price THEN
      'increased the price of ' || p_crop_name || ' from ₱' ||
        TO_CHAR(p_previous_price, 'FM999999990.00') || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
    ELSE
      'decreased the price of ' || p_crop_name || ' from ₱' ||
        TO_CHAR(p_previous_price, 'FM999999990.00') || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
  END;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ur.user_id,
    'price',
    'Price Update: ' || p_crop_name,
    'SP3 Admin ' || v_change || '. ' ||
      CASE
        WHEN ur.role = 'buyer' THEN 'Check the Prices tab for the latest market rates.'
        ELSE 'Check the Analytics tab for the latest market rates.'
      END,
    FALSE,
    NOW(),
    CASE WHEN ur.role = 'buyer' THEN '/buyer/prices' ELSE '/farmer/analytics' END
  FROM user_roles ur
  WHERE ur.role IN ('farmer', 'buyer')
    AND ur.status = 'active';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_price_update(TEXT, NUMERIC, TEXT, NUMERIC) TO authenticated;

-- ─── 9. Listing owner told when a purchase of their listing is completed ───
-- complete_order is copied from supabase_schema_role_based_staff_access.sql;
-- only the seller notice text changes.
CREATE OR REPLACE FUNCTION public.complete_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_batch_id    UUID;
  v_remaining   NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can complete orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only approved orders can be marked completed (current status: %)', v_status;
  END IF;

  SELECT inventory_batch_id INTO v_batch_id
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_batch_id IS NOT NULL THEN
    UPDATE inventory_batches SET sold_kg = sold_kg + v_quantity_kg WHERE id = v_batch_id;
  END IF;

  SELECT remaining_kg INTO v_remaining
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_remaining <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = v_listing_id;
  END IF;

  UPDATE orders SET status = 'completed' WHERE id = p_order_id;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Completed',
    'Your order for ' || COALESCE(v_crop_name, 'produce') ||
      ' has been completed. Thank you for supporting SP3 farmers!',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Completed',
    'Someone completed a purchase of your ' || COALESCE(v_crop_name, 'produce') || ' listing.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;
