-- ============================================================
-- SAGANA — Cancel Order: Pending-Only Guard (Admin Marketplace,
-- Order Management phase)
--
-- Previously cancel_order() allowed cancelling from either 'pending'
-- or 'approved'. Per the approved decision on this review: once an
-- order is approved, the cooperative has already committed to
-- fulfilling it — the only forward action left is Complete Order,
-- not Cancel. The client-side "Cancel Order" button was already
-- removed for approved orders; this migration backs that up at the
-- API layer too (defense in depth, matching the guard pattern used
-- elsewhere in this schema, e.g. supabase_schema_reject_listing_guard.sql).
--
-- Every line is preserved exactly as the current canonical version
-- (see supabase_schema_farmer_notification_gaps.sql, which layered
-- the farmer notification on top of supabase_schema_order_notifications.sql's
-- buyer notification) — only the status guard changes.
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
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Order cannot be cancelled once approved — current status: %', v_status;
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

GRANT EXECUTE ON FUNCTION cancel_order TO authenticated;
