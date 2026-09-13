-- ============================================================
-- SAGANA — Fix: crop_requests missing farmer_crop_id + crop_type
--
-- crop_repository.dart's requestNewCrop() has always inserted
-- farmer_crop_id and crop_type into crop_requests, and
-- fetchCrops() has always embedded crop_requests(status,
-- admin_notes) under farmer_crops — neither column exists on
-- crop_requests as originally created, so both operations fail
-- at the database level. This adds the missing columns,
-- restoring the FK relationship PostgREST needs to resolve the
-- embedded select, with ON DELETE CASCADE matching the same
-- cascade behavior harvest_records and inventory_batches
-- already have from farmer_crops.
-- ============================================================

ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS farmer_crop_id UUID
    REFERENCES public.farmer_crops(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS crop_type TEXT;

CREATE INDEX IF NOT EXISTS idx_crop_requests_farmer_crop_id
  ON public.crop_requests (farmer_crop_id);