-- ============================================================
-- ⚠️ PARTIALLY SUPERSEDED — reject_listing here is from an
-- earlier era (releases volume_kg, not remaining_kg). The
-- canonical reject_listing is now in
-- supabase_schema_marketplace_order_reservation_fix.sql. The
-- _release_batch_reservation helper defined below is still
-- canonical and is not redefined anywhere else. See
-- supabase_schema_RESERVATION_MODEL_NOTES.md.
-- ============================================================
-- SAGANA — Listing Rejection Inventory Release
-- rejectListing() previously only updated status — the batch
-- reservation from create_listing_with_reservation() was never
-- released, leaving farmer stock permanently locked behind a
-- dead listing. Mirrors decline_cooperative_offer's release logic.
-- ============================================================

CREATE OR REPLACE FUNCTION public._release_batch_reservation(
  p_batch_id UUID,
  p_quantity DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  SELECT quantity_kg, available_kg, sold_kg
    INTO v_quantity_kg, v_available_kg, v_sold_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE;

  v_new_available := v_available_kg + p_quantity;

  v_new_status := CASE
    WHEN v_new_available <= 0 THEN
      CASE WHEN v_sold_kg >= v_quantity_kg THEN 'sold_out' ELSE 'reserved' END
    WHEN v_new_available < v_quantity_kg * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE public.inventory_batches
    SET available_kg = v_new_available, status = v_new_status
    WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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

  IF v_listing.inventory_batch_id IS NOT NULL THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.volume_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_listing.farmer_id, 'system', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION reject_listing TO authenticated;

NOTIFY pgrst, 'reload schema';