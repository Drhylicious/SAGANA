-- ============================================================
-- SAGANA — Market Type Persistence Through the Disposal Chain
-- (Farmer-Harvest Tab rework, Phase 1 / Schema Foundation)
--
-- The farmer's crop market type (crop_master.crop_type /
-- crop_requests.crop_type — sp3_cooperative | da_amad_market |
-- open_market) previously existed only on crop_master/crop_requests
-- and had to be re-joined through farmer_crops every time a screen
-- needed to show it. Per the Farmer-Harvest tab review, market type
-- must be visible wherever a harvested crop is displayed, all the way
-- through to point of sale — so this denormalizes it onto
-- inventory_batches (same pattern already used for is_coop_eligible)
-- and cascades it onto the three downstream disposal tables that key
-- off a specific batch: marketplace_listings, cooperative_purchase_offers,
-- informal_sales.
--
-- inventory_batches.crop_type is populated explicitly in Dart
-- (harvest_entry_repository.dart's _submitOnline(), alongside the
-- existing is_coop_eligible lookup) at harvest-submission time — not by
-- a trigger — to match the codebase's existing convention for this kind
-- of snapshot.
--
-- marketplace_listings / cooperative_purchase_offers / informal_sales
-- are populated by a shared BEFORE INSERT trigger instead of editing
-- their creation RPCs directly (create_listing_with_reservation,
-- offer_batch_to_cooperative, record_informal_sale) — those functions
-- have been redefined multiple times across this schema's migration
-- history, and a trigger achieves the same result without needing to
-- reproduce or risk regressing whichever version is actually live.
-- ============================================================

BEGIN;

-- ─── inventory_batches.crop_type ────────────────────────────────────────────

ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

UPDATE public.inventory_batches ib
SET crop_type = cm.crop_type
FROM public.farmer_crops fc
JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE ib.crop_id = fc.id
  AND ib.crop_type IS NULL;

-- ─── Downstream disposal tables ─────────────────────────────────────────────

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

ALTER TABLE public.cooperative_purchase_offers
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

ALTER TABLE public.informal_sales
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

-- Backfill existing rows via their inventory_batch_id FK.
UPDATE public.marketplace_listings ml
SET crop_type = ib.crop_type
FROM public.inventory_batches ib
WHERE ml.inventory_batch_id = ib.id
  AND ml.crop_type IS NULL;

UPDATE public.cooperative_purchase_offers co
SET crop_type = ib.crop_type
FROM public.inventory_batches ib
WHERE co.inventory_batch_id = ib.id
  AND co.crop_type IS NULL;

UPDATE public.informal_sales isale
SET crop_type = ib.crop_type
FROM public.inventory_batches ib
WHERE isale.inventory_batch_id = ib.id
  AND isale.crop_type IS NULL;

-- Shared trigger function: on insert, if crop_type wasn't explicitly
-- supplied, derive it from the referenced batch. Safe to attach to any
-- table with both an inventory_batch_id and a crop_type column.
CREATE OR REPLACE FUNCTION public.set_crop_type_from_batch()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.crop_type IS NULL AND NEW.inventory_batch_id IS NOT NULL THEN
    SELECT crop_type INTO NEW.crop_type
    FROM public.inventory_batches
    WHERE id = NEW.inventory_batch_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_listings_crop_type ON public.marketplace_listings;
CREATE TRIGGER trg_marketplace_listings_crop_type
  BEFORE INSERT ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.set_crop_type_from_batch();

DROP TRIGGER IF EXISTS trg_coop_offers_crop_type ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_coop_offers_crop_type
  BEFORE INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public.set_crop_type_from_batch();

DROP TRIGGER IF EXISTS trg_informal_sales_crop_type ON public.informal_sales;
CREATE TRIGGER trg_informal_sales_crop_type
  BEFORE INSERT ON public.informal_sales
  FOR EACH ROW EXECUTE FUNCTION public.set_crop_type_from_batch();

-- ─── crop_requests.photo_url ─────────────────────────────────────────────────
-- Farmer-submitted reference photo for a "Request New Crop" submission.
-- Separate from crop_master.image_url (admin-curated catalog photo) and
-- farmer_crops.photo_url (the farmer's photo of their own planting, once
-- the request is approved and they're growing it) — this one exists only
-- for the pending-review window, so the admin has something to look at
-- when approving/rejecting. Upload flow itself is Phase 4 (UI) work; this
-- migration only adds the column.

ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS photo_url TEXT;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) New columns exist:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name IN ('inventory_batches','marketplace_listings',
--                          'cooperative_purchase_offers','informal_sales')
--      AND column_name = 'crop_type';
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'crop_requests' AND column_name = 'photo_url';
--
-- 2) Existing inventory_batches backfilled (expect no NULLs for batches
--    whose crop is linked to an approved crop_master row):
--    SELECT crop_name, crop_type FROM inventory_batches WHERE crop_type IS NULL;
--
-- 3) Existing downstream rows backfilled:
--    SELECT crop_name, crop_type FROM marketplace_listings WHERE crop_type IS NULL;
--    SELECT crop_name, crop_type FROM cooperative_purchase_offers WHERE crop_type IS NULL;
--    SELECT crop_name, crop_type FROM informal_sales WHERE crop_type IS NULL;
--
-- 4) Trigger works going forward — after this migration, create a new
--    listing/offer/informal sale against any batch and confirm its
--    crop_type matches that batch's crop_type without the app having to
--    set it explicitly.
-- ============================================================
