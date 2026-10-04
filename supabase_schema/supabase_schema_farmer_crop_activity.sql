-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_farmer_crop_activity.sql
--
-- Farmer Recent Activity — Harvest category, Edit Crop Photo. Mirrors
-- farmer_profile_activity exactly (same reasoning: farmer_crops only
-- carries current state, so there's no way to know after the fact
-- whether a crop's photo changed). This table exists solely to record
-- that one fact, at the moment CropRepository.updateCropPhoto() actually
-- succeeds. Kept as its own table rather than folding into
-- farmer_profile_activity, since that table is specifically the
-- "Account" category's log — this one is Harvest's.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.farmer_crop_activity (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  crop_id     UUID NOT NULL REFERENCES public.farmer_crops(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS farmer_crop_activity_farmer_id_idx
  ON public.farmer_crop_activity (farmer_id, created_at DESC);

ALTER TABLE public.farmer_crop_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Farmers manage own crop activity"
  ON public.farmer_crop_activity
  FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

NOTIFY pgrst, 'reload schema';
