-- ============================================================
-- SAGANA — Allow farmer-initiated marketplace purchases
-- (Listing Tab redesign, Phase 1)
--
-- place_order() previously hard-required the caller to hold a
-- user_roles row with role = 'buyer' — a farmer's own row has
-- role = 'farmer', so this RPC unconditionally rejected every
-- farmer-initiated call with "Buyer account not found", regardless
-- of what the client UI allowed. This is the foundational fix the
-- new Farmer-to-Farmer Marketplace tab depends on: without it, no
-- amount of Farmer-side UI work can result in a working purchase.
--
-- user_roles.user_id is UNIQUE (confirmed live via pg_constraint) —
-- one row per person, not one row per role — so this simplifies to
-- reading that single row's role/status directly, rather than
-- filtering WHERE role = 'buyer' and getting nothing back for a
-- farmer. No new row, no second role, no schema change.
--
-- Also adds a self-purchase guard: a farmer must never be able to
-- place an order against their own listing. Enforced here, at the
-- authoritative RPC layer, not just withheld in the UI — matching
-- this codebase's established pattern for every other guard in this
-- module (the Ginger guard, the Cooperative-Market-only price edit,
-- etc.): the UI hides the option, the database makes it impossible
-- regardless of what calls this RPC directly.
--
-- Every other line — reservation locking, remaining_kg decrement,
-- the orders insert itself — is preserved exactly from the current
-- canonical version (supabase_schema_place_order_buyer_status_guard.sql).
-- Only the role/status lookup and the new self-purchase check change.
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

  INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status)
  VALUES (p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
          p_quantity_kg * v_price_per_kg, 'pending')
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION place_order TO authenticated;
