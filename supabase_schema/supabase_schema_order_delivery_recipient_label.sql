-- ============================================================
-- SAGANA — Order Delivery Recipient Name + Address Label
--
-- Admin's Order Detail and the Buyer's own Order Detail/Success screens
-- need to show who a delivery is for and which saved-address label it
-- came from ("Home"/"Work"/etc). Neither was ever captured onto the
-- orders row — only address line, lat/lng, contact number, and notes
-- were persisted by supabase_schema_checkout_fulfillment.sql. This adds
-- the two missing columns and threads them through place_order() the
-- same way every other delivery_* field already works.
--
-- Every guard below is preserved byte-for-byte from
-- supabase_schema_checkout_fulfillment.sql — only the two new params,
-- their two new INSERT columns, and the DROP's signature are new.
-- ============================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_recipient_name TEXT,
  ADD COLUMN IF NOT EXISTS delivery_label TEXT;

-- Same overload trap as before: CREATE OR REPLACE with a different
-- parameter list creates a second, separate function instead of
-- replacing the current 8-param one. Drop the exact current signature
-- first so exactly one place_order exists afterward.
DROP FUNCTION IF EXISTS place_order(UUID, NUMERIC, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT);

CREATE OR REPLACE FUNCTION place_order(
  p_listing_id              UUID,
  p_quantity_kg             NUMERIC,
  p_fulfillment_method      TEXT DEFAULT 'pickup',
  p_delivery_address        TEXT DEFAULT NULL,
  p_delivery_latitude       DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude      DOUBLE PRECISION DEFAULT NULL,
  p_delivery_contact_number TEXT DEFAULT NULL,
  p_delivery_notes          TEXT DEFAULT NULL,
  p_delivery_recipient_name TEXT DEFAULT NULL,
  p_delivery_label          TEXT DEFAULT NULL
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
    delivery_contact_number, delivery_notes, delivery_recipient_name, delivery_label
  )
  VALUES (
    p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
    p_quantity_kg * v_price_per_kg, 'pending',
    p_fulfillment_method,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_address ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_latitude ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_longitude ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_contact_number ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_notes ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_recipient_name ELSE NULL END,
    CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_label ELSE NULL END
  )
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION place_order TO authenticated;
NOTIFY pgrst, 'reload schema';
