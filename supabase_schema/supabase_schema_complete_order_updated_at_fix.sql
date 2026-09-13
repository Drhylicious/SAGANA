-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_complete_order_updated_at_fix.sql
-- Run after supabase_schema_order_notifications.sql
--
-- Fixes a no-op UPDATE inside complete_order(): the previous version wrote
-- remaining_kg back to itself (UPDATE ... SET remaining_kg = remaining_kg
-- ... RETURNING remaining_kg INTO v_remaining) purely to read the current
-- value. Since nothing was actually changing, this was only ever a read —
-- but issuing it as an UPDATE still fires trg_marketplace_listings_updated_at,
-- producing a false "this listing was just modified" timestamp on every
-- single order completion.
--
-- This version replaces that UPDATE with a plain SELECT. No other line in
-- the function changes — cancel_order() in the same file is untouched and
-- not redefined here since it was not affected.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Was: UPDATE marketplace_listings SET remaining_kg = remaining_kg WHERE
  -- id = v_listing_id RETURNING remaining_kg INTO v_remaining; — a no-op
  -- write that only existed to read the value back, and incorrectly bumped
  -- updated_at on an unmodified row. remaining_kg was already correctly
  -- decremented by place_order() at order-placement time; this function
  -- only ever needed to read it, not write it.
  SELECT remaining_kg INTO v_remaining
  FROM marketplace_listings WHERE id = v_listing_id;

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

GRANT EXECUTE ON FUNCTION complete_order TO authenticated;