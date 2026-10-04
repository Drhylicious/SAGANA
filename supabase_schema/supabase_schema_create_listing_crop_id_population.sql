-- ============================================================
-- SAGANA — Populate crop_id on listing creation
-- (Farmer Listing Tab review, Phase 1)
--
-- create_listing_with_reservation has never written crop_id to
-- marketplace_listings, on any version of this function found in
-- schema history (fix_listing_reservation.sql,
-- create_listing_reservation_corrected.sql,
-- create_listing_ginger_guard.sql — the current canonical version
-- until this migration). Confirmed live via direct query: every
-- listing this function has ever created has crop_id = NULL.
--
-- marketplace_listings.crop_id itself already exists live —
-- admin_listing_repository.dart reads it directly, and it was
-- queryable in the verification pass that found this gap — but no
-- migration file before this one ever declared it (it's a separate
-- column from price_records.crop_id, added by
-- crop_master_price_records_refactor.sql, which does not touch this
-- table). ADD COLUMN IF NOT EXISTS below formally documents the
-- column into migration history without risk, whether or not it
-- already exists.
--
-- Resolved server-side rather than a new farmer-supplied parameter,
-- so this requires no Dart-side call-signature change and can't be
-- spoofed or mismatched by the client. NOT a direct single-column
-- read of inventory_batches.crop_id — per crop_lookup.dart's own
-- documented finding, that column references farmer_crops(id), not
-- crop_master(id) directly (a pre-existing, unrelated column-name
-- collision from an earlier migration). The real crop_master.id is
-- reached via farmer_crops.crop_master_id, the same two-step path
-- crop_lookup.dart's fetchFarmerCropToCropMasterMap()/
-- fetchCropNameMap() already establish for this exact reason. If the
-- batch's crop is still pending admin approval (crop_master_id not
-- yet linked), this resolves to NULL, which degrades the same way
-- every other canonical-name consumer in this codebase already
-- handles an unresolved crop_id.
--
-- No backfill for existing rows: a direct query
-- (SELECT status, COUNT(*) FROM marketplace_listings WHERE crop_id
-- IS NULL GROUP BY status) found exactly one affected row, status
-- 'rejected' — terminal, no buyer-visible or farmer-actionable
-- surface reads its crop_id. Scoped to the forward fix only.
--
-- Every existing line preserved exactly (Ginger guard, admin
-- fan-out notification, reservation call) — only the crop_id column
-- and its value are added.
-- ============================================================

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS crop_id UUID REFERENCES public.crop_master(id);

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
  v_crop_id UUID;
BEGIN
  IF p_crop_name ILIKE '%ginger%' THEN
    RAISE EXCEPTION 'Ginger cannot be listed on the open Marketplace — it can only be sold through Market Linking.';
  END IF;

  SELECT fc.crop_master_id INTO v_crop_id
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  WHERE ib.id = p_batch_id;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, v_crop_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review', p_quantity_kg
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

GRANT EXECUTE ON FUNCTION public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Post-migration verification — run separately after applying.
-- Expected: zero rows, UNLESS the listed batch's crop was still
-- pending admin approval at creation time (farmer_crops.crop_master_id
-- not yet linked) — that's an expected, pre-existing NULL, not a
-- bug in this migration.
-- ============================================================
-- SELECT ml.id, ml.crop_name, ml.crop_id
-- FROM public.marketplace_listings ml
-- WHERE ml.created_at > NOW() - INTERVAL '1 hour'
--   AND ml.crop_id IS NULL;
