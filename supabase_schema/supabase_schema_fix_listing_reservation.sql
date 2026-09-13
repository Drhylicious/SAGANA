-- ============================================================
-- ⚠️ SUPERSEDED — this file's create_listing_with_reservation was
-- an earlier fix attempt, itself superseded by
-- supabase_schema_create_listing_reservation_corrected.sql, which
-- is the canonical version. See
-- supabase_schema_RESERVATION_MODEL_NOTES.md. Kept for history
-- only.
-- ============================================================
-- SAGANA — Fix create_listing_with_reservation column/status mismatch
-- The original function (supabase_schema_inventory_disposal_paths.sql)
-- inserts into marketplace_listings using 'quantity_kg' (real column is
-- 'volume_kg') and status='pending' (not a valid value under the table's
-- CHECK constraint — only 'pending_review'/'approved'/'changes_required'/
-- 'withdrawn' are allowed). As written, every call to this RPC throws.
-- This is a straight fix to match the real table, not a new feature.
-- ============================================================

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
    farmer_id, inventory_batch_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review'
  ) RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;