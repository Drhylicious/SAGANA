-- ============================================================
-- ⚠️ SUPERSEDED — place_order here is from the batch-centric
-- reservation era. The canonical place_order is now in
-- supabase_schema_marketplace_order_reservation_fix.sql. See
-- supabase_schema_RESERVATION_MODEL_NOTES.md for the full picture
-- and the safe replay order. Kept for history only.
-- ============================================================
-- SAGANA — Buyer Order Placement
-- Adds the place_order RPC: atomically reserves stock and
-- creates an order row in a single transaction, closing the
-- race condition a plain client-side INSERT would allow
-- (two buyers ordering against the same batch simultaneously).
-- ============================================================

CREATE OR REPLACE FUNCTION place_order(
  p_listing_id  UUID,
  p_quantity_kg NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id      UUID := auth.uid();
  v_farmer_id     UUID;
  v_price_per_kg  NUMERIC;
  v_batch_id      UUID;
  v_available     NUMERIC;
  v_batch_qty     NUMERIC;
  v_order_id      UUID;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT farmer_id, price_per_kg, inventory_batch_id
  INTO v_farmer_id, v_price_per_kg, v_batch_id
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;

  IF v_batch_id IS NOT NULL THEN
    SELECT available_kg, quantity_kg INTO v_available, v_batch_qty
    FROM inventory_batches
    WHERE id = v_batch_id
    FOR UPDATE;

    IF v_available IS NULL OR v_available < p_quantity_kg THEN
      RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', COALESCE(v_available, 0);
    END IF;

    UPDATE inventory_batches
    SET available_kg = available_kg - p_quantity_kg,
        reserved_kg  = reserved_kg + p_quantity_kg,
        status = CASE
          WHEN available_kg - p_quantity_kg <= 0 THEN 'reserved'
          WHEN available_kg - p_quantity_kg < v_batch_qty * 0.15 THEN 'low_stock'
          ELSE status
        END
    WHERE id = v_batch_id;
  END IF;

  INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status)
  VALUES (p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
          p_quantity_kg * v_price_per_kg, 'pending')
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION place_order TO authenticated;

-- ── FORWARD DEPENDENCY — NOT YET IMPLEMENTED ────────────────────────────────
-- place_order() moves quantity from available_kg → reserved_kg on order
-- creation. The INVERSE movement must be added when farmer/admin order-status
-- transitions are built (the future Order Management screen):
--
--   On order status → 'cancelled':
--     UPDATE inventory_batches
--     SET reserved_kg = reserved_kg - <order.quantity_kg>,
--         available_kg = available_kg + <order.quantity_kg>,
--         status = <recompute based on new available_kg>
--     WHERE id = <listing's inventory_batch_id>;
--
--   On order status → 'completed':
--     UPDATE inventory_batches
--     SET reserved_kg = reserved_kg - <order.quantity_kg>,
--         sold_kg      = sold_kg + <order.quantity_kg>
--     WHERE id = <listing's inventory_batch_id>;
--
-- Recommend wrapping both in their own SECURITY DEFINER RPCs
-- (e.g. approve_order / complete_order / cancel_order), same atomic
-- pattern as place_order — a plain client UPDATE on orders.status alone
-- would silently skip the inventory correction.