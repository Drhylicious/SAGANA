-- ============================================================
-- SAGANA — Marketplace Order Reservation Fix (Option C)
-- remaining_kg on marketplace_listings becomes the single source
-- of truth for buyer-order availability. inventory_batches stays
-- exactly as-is for every other disposal path — this only changes
-- how the buyer-order sub-flow tracks its own slice of a listing.
--
-- ⚠️ NOTE: this file is canonical for place_order, cancel_order,
-- complete_order, reject_listing, withdraw_listing, and
-- resubmit_listing_with_reservation — but NOT for
-- create_listing_with_reservation, defined below. That one function
-- has a bug (wrong column name, invalid status) fixed by
-- supabase_schema_create_listing_reservation_corrected.sql, which
-- must be re-applied after this file if this file is ever re-run.
-- See supabase_schema_RESERVATION_MODEL_NOTES.md.
-- ============================================================

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS remaining_kg DECIMAL(10,2);

-- Backfill: original volume minus whatever's already committed to
-- non-cancelled orders (correct even if some order data already exists;
-- resolves to volume_kg for any listing with no orders yet).
UPDATE public.marketplace_listings ml
SET remaining_kg = ml.volume_kg - COALESCE((
  SELECT SUM(o.quantity_kg) FROM public.orders o
  WHERE o.listing_id = ml.id AND o.status IN ('pending', 'approved', 'completed')
), 0)
WHERE remaining_kg IS NULL;

ALTER TABLE public.marketplace_listings
  ALTER COLUMN remaining_kg SET NOT NULL,
  ADD CONSTRAINT marketplace_listings_remaining_kg_check CHECK (remaining_kg >= 0);

-- ─── Listing creation: initialize remaining_kg alongside the existing
--     batch-level commitment, which is otherwise unchanged. ─────────────────

CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_variety TEXT,
  p_quantity_kg DECIMAL,
  p_price_per_kg DECIMAL,
  p_photo_url TEXT
) RETURNS UUID AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, quantity_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── Reject: release remaining_kg, not the original volume_kg ──────────────

CREATE OR REPLACE FUNCTION reject_listing(
  p_listing_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, remaining_kg = 0, updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_listing.farmer_id, 'system', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW()
  );
END;
$$;

-- ─── Withdraw: same fix ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION withdraw_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_listing.status NOT IN ('pending_review', 'changes_required', 'approved') THEN
    RAISE EXCEPTION 'This listing cannot be withdrawn (status: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings SET status = 'withdrawn', remaining_kg = 0 WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_listing TO authenticated;
GRANT EXECUTE ON FUNCTION withdraw_listing TO authenticated;

-- ─── Resubmit: re-sync remaining_kg with the new volume ─────────────────────
-- Safe to always overwrite here — resubmit only happens from
-- changes_required, which is pre-approval, so no order could have
-- consumed any of remaining_kg yet.

CREATE OR REPLACE FUNCTION resubmit_listing_with_reservation(
  p_listing_id UUID,
  p_price_per_kg DECIMAL,
  p_volume_kg DECIMAL,
  p_photo_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
  v_delta DECIMAL;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  v_delta := p_volume_kg - v_listing.volume_kg;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_delta != 0 THEN
    IF v_delta > 0 THEN
      PERFORM _apply_batch_reservation(v_listing.inventory_batch_id, v_delta);
    ELSE
      PERFORM _release_batch_reservation(v_listing.inventory_batch_id, ABS(v_delta));
    END IF;
  END IF;

  UPDATE marketplace_listings
  SET price_per_kg = p_price_per_kg,
      volume_kg = p_volume_kg,
      remaining_kg = p_volume_kg,
      photo_url = p_photo_url,
      status = 'pending_review',
      admin_notes = NULL,
      submitted_at = NOW()
  WHERE id = p_listing_id;

  RETURN p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION resubmit_listing_with_reservation TO authenticated;

-- ─── Place order: operates on the listing's remaining_kg, never the batch ──

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
  v_remaining     NUMERIC;
  v_order_id      UUID;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
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

-- ─── Cancel order: give back to the listing, and revive it if it had sold out ─

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
  IF v_status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'Order cannot be cancelled from its current status: %', v_status;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_order TO authenticated;

-- ─── Complete order: record the sale on the batch, close out the listing ───

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

  UPDATE marketplace_listings SET remaining_kg = remaining_kg
  WHERE id = v_listing_id
  RETURNING remaining_kg INTO v_remaining;

  IF v_remaining <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = v_listing_id;
  END IF;

  UPDATE orders SET status = 'completed' WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION complete_order TO authenticated;

NOTIFY pgrst, 'reload schema';