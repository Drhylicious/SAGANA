-- ============================================================
-- SAGANA — Farmer crop photos: separate from Crop Master, required to sell
--
-- THE RULES (database side)
--   1. A Farmer's crop photo (farmer_crops.photo_url) is the Farmer's own
--      photo of their own crop. The Crop Master image (crop_master.image_url)
--      is a reference only and is never copied onto a Farmer's crop. The app
--      captures the Farmer photo with the camera only; the database cannot
--      tell a camera from a gallery, so it records WHEN the photo was set
--      (photo_captured_at) and requires one before an eligible sale.
--   2. Photo required (Farmer's own crop photo on the batch's crop):
--        Marketplace listing ........ required
--        Offer to Cooperative ....... required
--        DA-AMAD / Market Linking ... required
--        Informal Sale .............. NOT required
--      Enforced by BEFORE INSERT triggers, so it holds for the app's RPCs and
--      for any direct insert alike. Only NEW rows are checked; nothing already
--      submitted is touched.
--   3. A Marketplace listing's photo is always the Farmer's crop photo
--      (the trigger sets it), never a catalog image.
--   4. Crop requests no longer carry or inherit an image: approving a request
--      does not set the Crop Master image and does not copy a photo onto the
--      Farmer's crop. (crop_requests.photo_url stays as history; it is simply
--      not used any more.)
--   5. The Marketplace's "no Ginger" check no longer looks at the crop name:
--      it uses the crop's configured exclusive channel, like every other
--      channel rule.
--
-- Nothing is deleted. Safe to re-run.
-- Not applied automatically: run in the Supabase SQL editor, then the
-- VERIFICATION block at the end, then supabase_schema_crop_photos_selling_
-- rules_test.sql.
-- ============================================================

BEGIN;

-- ─── 1. When was the Farmer photo set ──────────────────────────────────────
ALTER TABLE public.farmer_crops
  ADD COLUMN IF NOT EXISTS photo_captured_at TIMESTAMPTZ;

-- Photos that already exist were set at some earlier time we cannot know; the
-- crop's last update is the closest honest value.
UPDATE public.farmer_crops
   SET photo_captured_at = COALESCE(updated_at, created_at)
 WHERE photo_url IS NOT NULL AND photo_url <> '' AND photo_captured_at IS NULL;

CREATE OR REPLACE FUNCTION public.stamp_farmer_crop_photo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.photo_url IS DISTINCT FROM OLD.photo_url THEN
    NEW.photo_captured_at :=
      CASE WHEN NEW.photo_url IS NULL OR NEW.photo_url = '' THEN NULL ELSE NOW() END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_farmer_crops_stamp_photo ON public.farmer_crops;
CREATE TRIGGER trg_farmer_crops_stamp_photo
  BEFORE UPDATE OF photo_url ON public.farmer_crops
  FOR EACH ROW EXECUTE FUNCTION public.stamp_farmer_crop_photo();

-- ─── 2. "Does this batch's crop have the Farmer's own photo?" ──────────────
CREATE OR REPLACE FUNCTION public.farmer_crop_photo_for_batch(p_batch_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULLIF(btrim(fc.photo_url), '')
    FROM public.inventory_batches ib
    JOIN public.farmer_crops fc ON fc.id = ib.crop_id
   WHERE ib.id = p_batch_id;
$$;
REVOKE ALL ON FUNCTION public.farmer_crop_photo_for_batch(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.farmer_crop_photo_for_batch(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.require_batch_crop_photo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_photo TEXT;
BEGIN
  IF NEW.inventory_batch_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_photo := public.farmer_crop_photo_for_batch(NEW.inventory_batch_id);
  IF v_photo IS NULL THEN
    RAISE EXCEPTION 'PHOTO_REQUIRED: Take a photo of your actual crop in Crop Roster before selling this batch.';
  END IF;

  -- A listing always shows the Farmer's own crop photo.
  IF TG_TABLE_NAME = 'marketplace_listings' THEN
    NEW.photo_url := v_photo;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_listings_require_photo ON public.marketplace_listings;
CREATE TRIGGER trg_marketplace_listings_require_photo
  BEFORE INSERT ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.require_batch_crop_photo();

DROP TRIGGER IF EXISTS trg_coop_offers_require_photo ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_coop_offers_require_photo
  BEFORE INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public.require_batch_crop_photo();

DROP TRIGGER IF EXISTS trg_market_linking_require_photo ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_require_photo
  BEFORE INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.require_batch_crop_photo();

-- Informal sales: deliberately no trigger. A completed face-to-face sale is
-- recorded as it happened, with or without a photo.

-- ─── 3. Marketplace listing: exclusive channel by configuration, not by name ─
-- This is the repository's canonical create_listing_with_reservation, copied
-- unchanged from supabase_schema_market_rules_by_data.sql: a crop reserved for
-- one selling channel (crop_master.exclusive_channel — Ginger -> DA-AMAD Market
-- Linking) is refused by that setting, never by its name. A database that only
-- has the older, name-based version gets the configured rule from this file.
CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(p_batch_id uuid, p_crop_name text, p_variety text, p_quantity_kg numeric, p_price_per_kg numeric, p_photo_url text, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_listing_id UUID;
  v_crop_id UUID;
  v_excl TEXT;
  v_excl_name TEXT;
BEGIN
  SELECT cm.exclusive_channel, sc.name
    INTO v_excl, v_excl_name
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  JOIN public.crop_master cm  ON cm.id = fc.crop_master_id
  LEFT JOIN public.selling_channels sc ON sc.code = cm.exclusive_channel
  WHERE ib.id = p_batch_id;

  IF v_excl IS NOT NULL THEN
    RAISE EXCEPTION '% can only be sold through % — it cannot be listed on the Marketplace.',
      p_crop_name, v_excl_name;
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
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_listing_id;
END;
$function$;

-- ─── 4. Approving a crop request no longer touches any image ────────────────
-- The live approve_crop_request, with exactly two lines removed: the request
-- photo is no longer written to the new Crop Master entry (image_url), and no
-- longer copied onto the Farmer's crop (photo_url). Everything else — the staff
-- check, the crop-type validation, the notification — is unchanged.
CREATE OR REPLACE FUNCTION public.approve_crop_request(
  p_request_id uuid,
  p_admin_notes text DEFAULT NULL::text,
  p_crop_type text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request RECORD;
  v_crop_master_id UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'da_amad_market', 'open_market') THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
  END IF;

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops
    SET crop_master_id = v_crop_master_id
    WHERE id = v_request.farmer_crop_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );

  RETURN v_crop_master_id;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Triggers exist (expect 4 rows):
--    SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
--      ('trg_farmer_crops_stamp_photo','trg_marketplace_listings_require_photo',
--       'trg_coop_offers_require_photo','trg_market_linking_require_photo');
-- 2. Then run supabase_schema_crop_photos_selling_rules_test.sql (expect FAILED CHECKS: 0).
--
-- ─── OPTIONAL: Farmer photos that are really the Crop Master image ────────
-- Before this change, approving a crop request copied the request's photo to
-- BOTH the catalog entry and the Farmer's crop, so a Farmer's "own" photo may
-- be the same picture as the catalog's. Preview (read-only):
--    SELECT fc.id, fc.farmer_id, fc.crop_name, fc.photo_url
--    FROM farmer_crops fc JOIN crop_master cm ON cm.id = fc.crop_master_id
--    WHERE fc.photo_url IS NOT NULL AND fc.photo_url = cm.image_url;
-- If you want those Farmers to take a fresh camera photo, clear them (this
-- only empties the photo link; no file is deleted, and nothing else changes):
--    UPDATE farmer_crops fc SET photo_url = NULL
--    FROM crop_master cm
--    WHERE cm.id = fc.crop_master_id AND fc.photo_url IS NOT NULL AND fc.photo_url = cm.image_url;
-- ───────────────────────────────────────────────────────────────────────────
