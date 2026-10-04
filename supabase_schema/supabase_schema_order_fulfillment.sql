-- ============================================================
-- SAGANA — Order Fulfillment: Pickup / Delivery capture
-- (Listing Tab redesign, Phase 5)
--
-- Adds the ability for a buyer to record how an APPROVED order will be
-- fulfilled — pickup at the Barangay Payanas location, or delivery to
-- an address they provide. This is deliberately a data-capture addition,
-- not an enforcement/logistics system: SAGANA has no existing delivery
-- infrastructure (no driver/routing concept anywhere in this schema),
-- so the app's job here is to record the buyer's stated choice and
-- details for the cooperative to act on manually — not to promise or
-- orchestrate the delivery itself.
--
-- Deliberately NOT touching complete_order() or cancel_order() — this
-- is an entirely separate, additive concern layered on top of the
-- existing order lifecycle, not a new precondition for either of those
-- RPCs. An order can be completed or cancelled with or without a
-- fulfillment method ever having been set.
--
-- Columns are nullable and live directly on `orders` (not a separate
-- table) since this is strictly 1:1 per order — matches this codebase's
-- existing preference for atomic single-table RPC updates over extra
-- joins for 1:1 data.
-- ============================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS fulfillment_method TEXT
    CHECK (fulfillment_method IN ('pickup', 'delivery')),
  ADD COLUMN IF NOT EXISTS delivery_address TEXT,
  ADD COLUMN IF NOT EXISTS delivery_latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_contact_number TEXT,
  ADD COLUMN IF NOT EXISTS delivery_notes TEXT;

-- ─── set_order_fulfillment ──────────────────────────────────────────────────
-- Guarded RPC rather than a raw client update, matching this module's
-- established convention (place_order, complete_order, cancel_order all
-- go through guarded RPCs, never a direct .update()).
--
-- Guards, in order:
--   1. Caller must be authenticated.
--   2. p_fulfillment_method must be 'pickup' or 'delivery'.
--   3. The order must exist, and the caller must be its own buyer —
--      one buyer cannot set fulfillment details on another buyer's
--      order, and a farmer/admin cannot set it on a buyer's behalf.
--   4. The order must be 'approved' — matches the confirmed workflow
--      ("once an order is approved, the buyer should be prompted to
--      choose"). Not required before approval, not meaningful after
--      completion/cancellation.
--   5. Choosing 'delivery' requires a non-blank address and contact
--      number — a defense-in-depth backstop matching this codebase's
--      pattern elsewhere (the UI already prompts for these; the RPC
--      makes it impossible to save an unusable delivery record
--      regardless of what calls this directly).
--
-- Switching from one method to the other is allowed (no "already set,
-- can't change" lock) — re-running this RPC simply overwrites the
-- previous choice, and switching to 'pickup' clears any stale delivery
-- fields rather than leaving them dangling.
CREATE OR REPLACE FUNCTION set_order_fulfillment(
  p_order_id UUID,
  p_fulfillment_method TEXT,
  p_delivery_address TEXT DEFAULT NULL,
  p_delivery_latitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude DOUBLE PRECISION DEFAULT NULL,
  p_delivery_contact_number TEXT DEFAULT NULL,
  p_delivery_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id      UUID := auth.uid();
  v_order_buyer_id UUID;
  v_order_status   TEXT;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'fulfillment_method must be pickup or delivery';
  END IF;

  SELECT buyer_id, status INTO v_order_buyer_id, v_order_status
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_order_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_order_buyer_id != v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer who placed this order can set its fulfillment method';
  END IF;
  IF v_order_status != 'approved' THEN
    RAISE EXCEPTION 'Fulfillment method can only be set once the order has been approved';
  END IF;

  IF p_fulfillment_method = 'delivery' THEN
    IF p_delivery_address IS NULL OR trim(p_delivery_address) = '' THEN
      RAISE EXCEPTION 'A delivery address is required when choosing delivery';
    END IF;
    IF p_delivery_contact_number IS NULL OR trim(p_delivery_contact_number) = '' THEN
      RAISE EXCEPTION 'A contact number is required when choosing delivery';
    END IF;
  END IF;

  UPDATE orders
  SET fulfillment_method      = p_fulfillment_method,
      delivery_address        = CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_address ELSE NULL END,
      delivery_latitude       = CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_latitude ELSE NULL END,
      delivery_longitude      = CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_longitude ELSE NULL END,
      delivery_contact_number = CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_contact_number ELSE NULL END,
      delivery_notes          = CASE WHEN p_fulfillment_method = 'delivery' THEN p_delivery_notes ELSE NULL END
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_order_fulfillment TO authenticated;

NOTIFY pgrst, 'reload schema';
