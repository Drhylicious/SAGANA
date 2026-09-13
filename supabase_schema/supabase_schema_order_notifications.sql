-- ============================================================
-- SAGANA — Buyer Order Status Notifications
-- Adds a notification insert to cancel_order and complete_order.
-- Every line from the live function bodies (confirmed via
-- pg_proc in Phase 1) is preserved exactly as-is; only new
-- lines (variable declarations, two lookup SELECTs, and the
-- final INSERT) are added — no existing statement is modified.
-- ============================================================

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
  SELECT crop_name INTO v_crop_name FROM marketplace_listings WHERE id = v_listing_id;

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

  UPDATE marketplace_listings SET remaining_kg = remaining_kg
  WHERE id = v_listing_id
  RETURNING remaining_kg INTO v_remaining;

  IF v_remaining <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = v_listing_id;
  END IF;

  UPDATE orders SET status = 'completed' WHERE id = p_order_id;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name INTO v_crop_name FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_buyer_id, 'order', 'Order Completed',
    'Your order for ' || COALESCE(v_crop_name, 'produce') ||
      ' has been completed. Thank you for supporting SP3 farmers!',
    FALSE, NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_order TO authenticated;
GRANT EXECUTE ON FUNCTION complete_order TO authenticated;

NOTIFY pgrst, 'reload schema';