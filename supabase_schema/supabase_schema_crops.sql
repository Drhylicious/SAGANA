-- ============================================================
-- SAGANA — Farmer Crops Schema
-- Covers: Crop Listing Screen, Add Crop Screen,
--         Harvest Management Screen, Harvest Entry Form
--
-- New table: farmer_crops
-- Referenced by: harvest_records (crop_id FK — added in harvest schema)
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: farmer_crops
-- Dynamically created crops per farmer.
-- No fixed crop list — farmers add their own crops freely.
-- category: one of 7 defined categories used for UI icon mapping
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.farmer_crops (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  crop_name   TEXT        NOT NULL,
  category    TEXT        NOT NULL DEFAULT 'Other'
              CHECK (category IN (
                'Grain',
                'Legume',
                'Root & Spice Crop',
                'Fruit',
                'Tree Crop',
                'Vegetable',
                'Other'
              )),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (farmer_id, crop_name)
);

CREATE TRIGGER trg_farmer_crops_updated_at
  BEFORE UPDATE ON public.farmer_crops
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_farmer_crops_farmer
  ON public.farmer_crops (farmer_id, created_at DESC);

-- RLS
ALTER TABLE public.farmer_crops ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_crops: farmer manages own"
  ON public.farmer_crops FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "farmer_crops: admin reads all"
  ON public.farmer_crops FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );
