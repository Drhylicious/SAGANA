-- ============================================================
-- SAGANA — Marketplace Listing Description
--
-- Create Listing gains a required "Description" field (farmer-written,
-- shown to buyers on the Listing Details screen and to the farmer on
-- their own listing detail/Submission Success screens). Added as its own
-- column on marketplace_listings rather than reusing crop_master/
-- farmer_crops text — this is per-LISTING copy the farmer writes fresh
-- each time (e.g. "sun-dried, sourced from Barangay Payang"), not a
-- catalog-level description that would be shared across every listing of
-- that crop.
--
-- Required going forward (enforced client-side in create_listing_screen.dart
-- AND server-side below, same defense-in-depth pattern as the Ginger
-- guard already in this function). Existing rows predate the field and
-- are left NULL — not backfilled, nothing meaningful to backfill them
-- with — so the column itself stays nullable at the DB level; "required"
-- is enforced at the point of creation, not as a blanket NOT NULL that
-- would break reads of historical rows.
-- ============================================================

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Redefine with the new p_description param. This changes the function's
-- signature, so the old 6-arg overload is dropped first — leaving it in
-- place alongside the new 7-arg version would make PostgREST unable to
-- pick which one a plain RPC call means ("Could not choose the best
-- candidate function").
DROP FUNCTION IF EXISTS public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text);

CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_variety TEXT,
  p_quantity_kg DECIMAL,
  p_price_per_kg DECIMAL,
  p_photo_url TEXT,
  p_description TEXT
) RETURNS UUID AS $$
DECLARE
  v_listing_id UUID;
  v_crop_id UUID;
BEGIN
  IF p_crop_name ILIKE '%ginger%' THEN
    RAISE EXCEPTION 'Ginger cannot be listed on the open Marketplace — it can only be sold through Market Linking.';
  END IF;

  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'A description is required to create a listing.';
  END IF;

  SELECT fc.crop_master_id INTO v_crop_id
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  WHERE ib.id = p_batch_id;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, description, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, v_crop_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, btrim(p_description), 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
