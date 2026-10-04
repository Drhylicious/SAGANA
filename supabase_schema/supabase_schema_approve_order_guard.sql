-- ============================================================
-- SAGANA — Approve Order: guarded RPC (Admin Order Management)
--
-- approveOrder() previously did a raw client
-- .update({'status':'approved'}).eq('status','pending') directly against
-- the orders table — the only order-status mutation in this module that
-- didn't go through a guarded RPC. Every sibling action (place_order,
-- cancel_order, complete_order) is a SECURITY DEFINER RPC with an
-- explicit admin check and a FOR UPDATE row lock; the raw update had
-- neither, relying only on RLS (an "admin can update orders" policy)
-- and a non-atomic conditional WHERE clause. Functionally safe in
-- practice, but inconsistent with this module's own established
-- convention and missing the row lock the other three actions rely on
-- to avoid a concurrent-action race.
--
-- Preserves the exact existing behavior: silently no-ops (returns
-- FALSE) if the order has already moved on from 'pending' — same
-- "avoids clobbering a race" intent the old .eq('status','pending')
-- clause had — rather than raising, since two admins tapping Approve
-- around the same time isn't an error condition worth surfacing.
-- Notifications (buyer + farmer) move server-side too, matching
-- complete_order's/cancel_order's own pattern, instead of being
-- assembled client-side after the fact.
-- ============================================================

CREATE OR REPLACE FUNCTION approve_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status     TEXT;
  v_listing_id UUID;
  v_buyer_id   UUID;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve orders';
  END IF;

  SELECT status, listing_id, buyer_id, farmer_id
  INTO v_status, v_listing_id, v_buyer_id, v_farmer_id
  FROM orders WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status <> 'pending' THEN
    RETURN FALSE;
  END IF;

  UPDATE orders SET status = 'approved' WHERE id = p_order_id;

  SELECT crop_name INTO v_crop_name FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Approved',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' has been approved and is being prepared.',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Approved',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been approved and is being prepared for the buyer.',
    FALSE, NOW(), '/farmer/marketplace'
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_order TO authenticated;

NOTIFY pgrst, 'reload schema';
