-- ============================================================================
-- Audit 06: Officer listing review is decided by the Marketplace permission.
--
-- Checked on the live database: approve_listing, reject_listing and
-- admin_update_listing_price already accept any staff member (is_staff()), so an
-- Officer is not blocked by a Manager-profile check any more. What is left is:
--   * the refusal text still says "only Managers", and
--   * the function itself does not look at the Officer's level; only the API gate
--     (staff_permission_gate) does.
-- This script makes the rule explicit and in the function: the Manager, or an
-- Officer with MANAGE on Marketplace, may approve, disapprove or re-price a
-- listing. A View Only Officer is refused with a clear message.
--
-- Each function is re-created exactly as it is live today, changing only the
-- permission check and its message. Run once, in the Supabase SQL editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status    TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT (public.is_staff() AND public.staff_can_manage('marketplace', auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: only the Manager or an Officer with Manage access to Marketplace can approve listings';
  END IF;

  SELECT status, farmer_id, crop_name
    INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'listing', 'Listing Approved',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' listing is now live on the Marketplace.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_listing(p_listing_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT (public.is_staff() AND public.staff_can_manage('marketplace', auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: only the Manager or an Officer with Manage access to Marketplace can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.volume_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Disapproved',
    'Your ' || COALESCE(v_listing.crop_name, 'produce') || ' listing was not approved.' ||
      CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN ' Reason: ' || btrim(p_reason) ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_listing_price(p_listing_id uuid, p_new_price numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status    TEXT;
  v_crop_type TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT (public.is_staff() AND public.staff_can_manage('marketplace', auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: only the Manager or an Officer with Manage access to Marketplace can edit listing prices';
  END IF;

  IF p_new_price IS NULL OR p_new_price <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than zero';
  END IF;

  SELECT ml.status, ml.crop_type, ml.farmer_id, ml.crop_name
    INTO v_status, v_crop_type, v_farmer_id, v_crop_name
  FROM marketplace_listings ml
  WHERE ml.id = p_listing_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only live (approved) listings can have their price edited';
  END IF;

  IF NOT COALESCE((SELECT mt.manager_sets_price FROM market_types mt WHERE mt.code = v_crop_type), FALSE) THEN
    RAISE EXCEPTION 'Only Cooperative Market listings can have their price edited by a Manager';
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
$function$;
