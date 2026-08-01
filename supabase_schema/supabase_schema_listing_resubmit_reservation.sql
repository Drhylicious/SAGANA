-- ============================================================
-- SAGANA — Resubmit Listing Inventory Reconciliation
-- resubmitListing() previously only updated the listing row —
-- a quantity change on resubmit never touched the batch
-- reservation. Reconciles the delta using the same helpers
-- create_listing_with_reservation and reject_listing already use.
-- ============================================================

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
      photo_url = p_photo_url,
      status = 'pending_review',
      admin_notes = NULL,
      submitted_at = NOW()
  WHERE id = p_listing_id;

  RETURN p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION resubmit_listing_with_reservation TO authenticated;

NOTIFY pgrst, 'reload schema';