-- ============================================================
-- SAGANA — Checkout + My Addresses (Phase 4)
--
-- Extends place_order() to accept fulfillment info directly, so it can
-- be captured atomically with order creation instead of via a separate
-- set_order_fulfillment() call after Admin approval. New params default
-- to 'pickup'/NULL, so every existing 2-arg caller keeps working
-- unmodified until the Dart call sites are updated in a later phase.
--
-- set_order_fulfillment() (supabase_schema_order_fulfillment.sql) is
-- left in place, unmodified — once nothing calls it, it's inert dead
-- code (its approved-only gate can never fire against the new flow).
--
-- Every guard below (auth, role/status, quantity, listing lock,
-- self-purchase, stock) is preserved byte-for-byte from the current
-- canonical version (supabase_schema_place_order_farmer_purchasing.sql)
-- — only the fulfillment params/validation and the INSERT's column list
-- are new.
--
-- Postgres identifies a function by name + parameter signature, so
-- CREATE OR REPLACE with a different parameter list does NOT replace the
-- old 2-argument place_order(uuid, numeric) — it creates a second,
-- separate overload, which then makes `GRANT EXECUTE ON FUNCTION
-- place_order` (no argument list) ambiguous. The DROP below removes that
-- old overload explicitly first, so exactly one place_order exists
-- afterward. Safe because every Dart caller already passes all 8 named
-- parameters on every call (buyer_marketplace_repository.dart) — nothing
-- still calls the 2-argument form.
-- ============================================================

DROP FUNCTION IF EXISTS place_order(UUID, NUMERIC);

CREATE OR REPLACE FUNCTION place_order(
  p_listing_id              UUID,
  p_quantity_kg             NUMERIC,
  p_fulfillment_method      TEXT DEFAULT 'pickup',
  p_delivery_address        TEXT DEFAULT NULL,
  p_delivery_latitude       DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude      DOUBLE PRECISION DEFAULT NULL,
  p_delivery_contact_number TEXT DEFAULT NULL,
  p_delivery_notes          TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id      UUID := auth.uid();
  v_caller_role   TEXT;
  v_caller_status TEXT;
  v_farmer_id     UUID;
  v_price_per_kg  NUMERIC;
  v_remaining     NUMERIC;
  v_order_id      UUID;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_caller_role, v_caller_status
  FROM user_roles
  WHERE user_id = v_buyer_id;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('buyer', 'farmer') THEN
    RAISE EXCEPTION 'Only buyer or farmer accounts can place marketplace orders';
  END IF;
  IF v_caller_status != 'active' THEN
    RAISE EXCEPTION 'Your account has been suspended by the SP3 Administrator. Please contact the cooperative for assistance.';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  IF p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'fulfillment_method must be pickup or delivery';
  END IF;
  IF p_fulfillment_method = 'delivery' THEN
    IF p_delivery_address IS NULL OR trim(p_delivery_address) = '' THEN
      RAISE EXCEPTION 'A delivery address is required when choosing delivery';
    END IF;
    IF p_delivery_contact_number IS NULL OR trim(p_delivery_contact_number) = '' THEN
      RAISE EXCEPTION 'A contact number is required when choosing delivery';
    END IF;
  END IF;

  SELECT farmer_id, price_per_kg, remaining_kg
  INTO v_farmer_id, v_price_per_kg, v_remaining
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;

  IF v_farmer_id = v_buyer_id THEN
    RAISE EXCEPTION 'You cannot place an order on your own listing';
  END IF;

  IF v_remaining < p_quantity_kg THEN
    RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', v_remaining;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg - p_quantity_kg
  WHERE id = p_listing_id;

  INSERT INTO orders (
    listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status,
    fulfillment_method, delivery_address, delivery_latitude, delivery_longitude,
    delivery_contact_number, delivery_notes
  )
  VALUES (
    p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
    p_quantity_kg * v_price_per_kg, 'pending',
    p_fulfillment_method,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_address ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_latitude ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_longitude ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_contact_number ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_notes ELSE NULL END
  )
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION place_order TO authenticated;
NOTIFY pgrst, 'reload schema';
