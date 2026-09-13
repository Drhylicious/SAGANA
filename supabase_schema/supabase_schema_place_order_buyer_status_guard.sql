-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_place_order_buyer_status_guard.sql
-- Run after supabase_schema_marketplace_order_reservation_fix.sql
--
-- Adds a buyer-status check to place_order(). A suspended buyer (admin sets
-- user_roles.status = 'suspended' via BuyerProfileRepository.setBuyerStatus)
-- was previously able to keep placing orders indefinitely, since neither the
-- RLS read policy on marketplace_listings nor place_order() itself checked
-- account status. This closes that gap at the authoritative RPC layer.
--
-- Full function body is otherwise identical to the version in
-- supabase_schema_marketplace_order_reservation_fix.sql.
-- ─────────────────────────────────────────────────────────────────────────────

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
  v_buyer_status  TEXT;
  v_farmer_id     UUID;
  v_price_per_kg  NUMERIC;
  v_remaining     NUMERIC;
  v_order_id      UUID;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status INTO v_buyer_status
  FROM user_roles
  WHERE user_id = v_buyer_id AND role = 'buyer';

  IF v_buyer_status IS NULL THEN
    RAISE EXCEPTION 'Buyer account not found';
  END IF;
  IF v_buyer_status != 'active' THEN
    RAISE EXCEPTION 'Your account has been suspended by the SP3 Administrator. Please contact the cooperative for assistance.';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT farmer_id, price_per_kg, remaining_kg
  INTO v_farmer_id, v_price_per_kg, v_remaining
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;
  IF v_remaining < p_quantity_kg THEN
    RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', v_remaining;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg - p_quantity_kg
  WHERE id = p_listing_id;

  INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status)
  VALUES (p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
          p_quantity_kg * v_price_per_kg, 'pending')
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION place_order TO authenticated;
