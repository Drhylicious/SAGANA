-- ============================================================================
-- Audit 07: Farmer actions that staff are told about, and one Recent Activity
-- source.
--
--  1. cancel_loan_request          staff are notified when a Farmer cancels
--  2. cancel_my_assistance_request staff are notified when a Farmer cancels
--  3. update_batch_available_quantity  staff are notified when a Farmer reduces
--                                       the available quantity of a harvest batch
--  4. get_my_listing_edit_activity  lets a Farmer's Recent Activity show their
--                                   own edited-listing requests
--
-- (An edited-listing request already notifies staff: request_listing_edit sends
-- "Edited Listing for Approval", update_my_listing sends "Listing Updated".)
-- Each function is re-created exactly as it is live today with only the
-- notification added. The notifications go to the Manager and to Officers with
-- Manage on the tab (see audit 04). Run once, after audits 02 and 04.
-- ============================================================================

-- 1. Loan request cancelled -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_loan_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_req  loan_requests%ROWTYPE;
  v_name TEXT;
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

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_req.farmer_id;
  PERFORM public.notify_staff(
    'loan',
    'Loan Request Cancelled',
    COALESCE(v_name, 'A farmer') || ' cancelled loan request ' || v_req.request_no || '.',
    '/admin/loans/requests'
  );
END;
$function$;

-- 2. Assistance request cancelled -------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_my_assistance_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r    program_assistance_requests%ROWTYPE;
  v_name TEXT;
BEGIN
  SELECT * INTO v_r FROM program_assistance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_r.farmer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Request not found.';
  END IF;
  IF v_r.status <> 'pending' THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a request that is still waiting can be cancelled.';
  END IF;
  UPDATE program_assistance_requests SET status = 'cancelled', cancelled_at = NOW() WHERE id = p_request_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;
  PERFORM public.notify_staff(
    'program',
    'Assistance Request Cancelled',
    COALESCE(v_name, v_r.farmer_name, 'A farmer') || ' cancelled assistance request ' || v_r.request_number || '.',
    '/admin/loans/assistance'
  );
END;
$function$;

-- 3. Harvest quantity reduced -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_batch_available_quantity(p_batch_id uuid, p_new_available_kg numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id    UUID;
  v_quantity_kg  DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg      DECIMAL;
  v_adjusted_kg  DECIMAL;
  v_new_adjusted DECIMAL;
  v_new_status   TEXT;
  v_crop         TEXT;
  v_batch_no     TEXT;
  v_unit         TEXT;
  v_name         TEXT;
BEGIN
  SELECT farmer_id, quantity_kg, available_kg, sold_kg, adjusted_kg, crop_name, batch_number, unit
    INTO v_farmer_id, v_quantity_kg, v_available_kg, v_sold_kg, v_adjusted_kg, v_crop, v_batch_no, v_unit
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE;

  IF v_quantity_kg IS NULL THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;
  IF auth.uid() IS NOT NULL AND v_farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF p_new_available_kg IS NULL OR p_new_available_kg < 0 THEN
    RAISE EXCEPTION 'Available quantity cannot be negative';
  END IF;
  IF p_new_available_kg <> round(p_new_available_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_new_available_kg > v_available_kg THEN
    RAISE EXCEPTION 'Available quantity (%) cannot exceed the current available amount of % kg. Increasing available stock isn''t supported here — % kg of this batch is committed to an active listing, cooperative offer, or market linking reservation, and is restored automatically when that reservation ends.',
      p_new_available_kg, v_available_kg, (v_quantity_kg - v_sold_kg - v_adjusted_kg - v_available_kg);
  END IF;

  v_new_adjusted := v_adjusted_kg + (v_available_kg - p_new_available_kg);

  IF p_new_available_kg <= 0 THEN
    v_new_status := CASE WHEN v_quantity_kg - v_sold_kg - v_new_adjusted <= 0 THEN 'sold_out' ELSE 'reserved' END;
  ELSIF p_new_available_kg < v_quantity_kg * 0.15 THEN
    v_new_status := 'low_stock';
  ELSE
    v_new_status := 'available';
  END IF;

  UPDATE public.inventory_batches
     SET available_kg = p_new_available_kg,
         adjusted_kg  = v_new_adjusted,
         status       = v_new_status
   WHERE id = p_batch_id;

  -- Staff are told when the available quantity actually went down.
  IF p_new_available_kg < v_available_kg THEN
    SELECT full_name INTO v_name FROM user_information WHERE user_id = v_farmer_id;
    PERFORM public.notify_staff(
      'system',
      'Harvest Quantity Reduced',
      COALESCE(v_name, 'A farmer') || ' reduced the available ' || COALESCE(v_crop, 'harvest') ||
        ' (' || COALESCE(v_batch_no, 'batch') || ') from ' || v_available_kg || ' to ' ||
        p_new_available_kg || ' ' || COALESCE(v_unit, 'kg') || '.',
      '/admin/farmers/details?id=' || v_farmer_id || '&tab=1'
    );
  END IF;
END;
$function$;

-- 4. The Farmer's own edited-listing requests, for Recent Activity ---------------------
-- listing_edit_requests is readable by staff only (it names the reviewer), so the
-- Farmer reads their own through this function, which returns no reviewer data.
CREATE OR REPLACE FUNCTION public.get_my_listing_edit_activity()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'created_at') DESC), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object('id', r.id, 'created_at', r.created_at, 'crop_name', l.crop_name) AS row
    FROM listing_edit_requests r
    LEFT JOIN marketplace_listings l ON l.id = r.listing_id
    WHERE r.farmer_id = auth.uid()
    ORDER BY r.created_at DESC
    LIMIT 100
  ) x;
$$;

REVOKE ALL ON FUNCTION public.get_my_listing_edit_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_listing_edit_activity() TO authenticated;
