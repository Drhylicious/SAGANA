-- ============================================================
-- SAGANA — Cooperative Crop Master List
-- Admin-managed list of official SP3 crops.
-- Farmers select from this list when adding crops.
-- Separate from farmer_crops (which tracks per-farmer cultivation).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.crop_master (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  crop_name   TEXT        NOT NULL UNIQUE,
  category    TEXT        NOT NULL DEFAULT 'Other'
              CHECK (category IN (
                'Grain', 'Legume', 'Root & Spice Crop',
                'Fruit', 'Tree Crop', 'Vegetable', 'Other'
              )),
  description TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_crop_master_updated_at
  BEFORE UPDATE ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.crop_master ENABLE ROW LEVEL SECURITY;

-- Admin: full access
CREATE POLICY "crop_master: admin manages all"
  ON public.crop_master FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- Farmers and buyers: read active crops only
CREATE POLICY "crop_master: authenticated reads active"
  ON public.crop_master FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- Seed SP3's 5 primary crops
INSERT INTO public.crop_master (crop_name, category, description, sort_order) VALUES
  ('Palay',  'Grain',            'Rice (unmilled). Sold directly to SP3 cooperative.', 1),
  ('Peanut', 'Legume',           'Groundnut. Sold directly to SP3 cooperative.', 2),
  ('Ginger', 'Root & Spice Crop','Sold via DA-AMAD market linking program.', 3),
  ('Banana', 'Fruit',            'Sold via open marketplace.', 4),
  ('Copra',  'Tree Crop',        'Dried coconut meat. Sold via open marketplace.', 5)
ON CONFLICT (crop_name) DO NOTHING;