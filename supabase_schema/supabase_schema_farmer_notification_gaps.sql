-- ============================================================
-- SAGANA — Farmer Notification Gaps (Phase 6)
-- Closes four confirmed one-directional notification loops found
-- during the Farmer-side review:
--   1. Listing submitted   → no admin was ever notified
--   2. Listing approved    → farmer was never notified
--   3. Listing changes required → farmer was never notified
--   4. Order completed / cancelled → only the buyer was notified,
--      never the farmer whose produce was involved
-- Every existing line in each touched function is preserved
-- exactly as-is; only new declarations/lookups/INSERTs are added.
-- ============================================================

-- ─── 1. Listing submitted → notify all admins ─────────────────────────────
-- Mirrors notify_admins_of_crop_request()'s exact "one row per admin"
-- pattern. Uses type 'listing_submitted', which admin_notifications_screen
-- already has a case for (added by supabase_schema_crop_request_admin_notify.sql
-- but never previously inserted by anything).

CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_variety TEXT,
  p_quantity_kg DECIMAL,
  p_price_per_kg DECIMAL,
  p_photo_url TEXT
) RETURNS UUID AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text) TO authenticated;

-- ─── 2. Listing approved → notify farmer ───────────────────────────────────
-- type 'listing' (not 'system' — see note above about reject_listing's
-- existing inconsistency, intentionally not touched here).

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve listings';
  END IF;

  SELECT status, farmer_id, crop_name INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'listing', 'Listing Approved',
    'Your ' || v_crop_name || ' listing is now live on the Marketplace.',
    FALSE, NOW()
  );
END;
$$;

-- ─── 3. Listing changes required → notify farmer with admin's notes ───────

CREATE OR REPLACE FUNCTION public.request_listing_changes(p_listing_id UUID, p_notes TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can request changes on listings';
  END IF;

  SELECT status, farmer_id, crop_name INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can have changes requested (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'changes_required', admin_notes = p_notes, updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'listing', 'Changes Requested',
    'Your ' || v_crop_name || ' listing needs changes before it can go live. Note: ' || p_notes,
    FALSE, NOW()
  );
END;
$$;

-- ─── 4. Order completed / cancelled → also notify the farmer ─────────────
-- Option B (approved per review): only the two outcome stages notify the
-- farmer, not 'placed' or 'approved', which require no farmer action.
-- Buyer-facing notification logic is untouched; farmer notification is
-- added alongside it in the same INSERT block pattern.

CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can cancel orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'Order cannot be cancelled from its current status: %', v_status;
  END IF;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_buyer_id, 'order', 'Order Cancelled',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW()
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'order', 'Order Cancelled',
    'An order for your ' || COALESCE(v_crop_name, 'produce') || ' listing was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW()
  );
END;
$$;

CREATE OR REPLACE FUNCTION complete_order(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete orders';
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_buyer_id, 'order', 'Order Completed',
    'Your order for ' || COALESCE(v_crop_name, 'produce') ||
      ' has been completed. Thank you for supporting SP3 farmers!',
    FALSE, NOW()
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'order', 'Order Completed',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been completed and sold.',
    FALSE, NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_order TO authenticated;
GRANT EXECUTE ON FUNCTION complete_order TO authenticated;

NOTIFY pgrst, 'reload schema';