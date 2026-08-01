-- ============================================================
-- SAGANA — Admin Order Management
-- Adds complete_order and cancel_order RPCs. Both are the
-- inverse-movement half of place_order's reservation: stock
-- that was moved into reserved_kg at order placement must be
-- moved back out atomically here, or it's stuck forever.
--
-- approve_order needs no RPC — pending → approved touches only
-- the orders row (stock was already reserved at placement),
-- and the existing "Admin full access to orders" RLS policy
-- already covers a plain client-side UPDATE safely.
--
-- Both RPCs are SECURITY DEFINER, which bypasses RLS entirely —
-- so both explicitly re-check admin_profiles inside the function
-- body, same pattern as create_staff_account / create_farmer_account.
-- Without this check, SECURITY DEFINER would let ANY authenticated
-- caller (e.g. a buyer calling the RPC directly, not through the
-- app UI) cancel or complete an arbitrary order — the client-side
-- button being admin-only means nothing if the RPC itself isn't.
-- ============================================================

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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only approved orders can be marked completed (current status: %)', v_status;
  END IF;

  SELECT inventory_batch_id INTO v_batch_id
  FROM marketplace_listings
  WHERE id = v_listing_id;

  IF v_batch_id IS NOT NULL THEN
    UPDATE inventory_batches
    SET reserved_kg = GREATEST(reserved_kg - v_quantity_kg, 0),
        sold_kg      = sold_kg + v_quantity_kg
    WHERE id = v_batch_id;
  END IF;

  UPDATE orders
  SET status = 'completed'
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION complete_order TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────

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
  v_batch_id    UUID;
  v_batch_qty   NUMERIC;
  v_new_available NUMERIC;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can cancel orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Cancellable from pending (= reject) or approved. Completed/cancelled
  -- orders are terminal — no reservation left to release.
  IF v_status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'Order cannot be cancelled from its current status: %', v_status;
  END IF;

  SELECT inventory_batch_id INTO v_batch_id
  FROM marketplace_listings
  WHERE id = v_listing_id;

  IF v_batch_id IS NOT NULL THEN
    SELECT quantity_kg INTO v_batch_qty
    FROM inventory_batches WHERE id = v_batch_id
    FOR UPDATE;

    v_new_available := NULL;
    UPDATE inventory_batches
    SET reserved_kg  = GREATEST(reserved_kg - v_quantity_kg, 0),
        available_kg = available_kg + v_quantity_kg,
        status = CASE
          WHEN (available_kg + v_quantity_kg) <= 0 THEN status
          WHEN (available_kg + v_quantity_kg) < COALESCE(v_batch_qty, 0) * 0.15 THEN 'low_stock'
          ELSE 'available'
        END
    WHERE id = v_batch_id;
  END IF;

  UPDATE orders
  SET status = 'cancelled',
      notes  = COALESCE(p_reason, notes)
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_order TO authenticated;