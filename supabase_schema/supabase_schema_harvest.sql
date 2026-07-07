-- ============================================================
-- SAGANA — Harvest Records & Inventory Batches Schema
-- Covers: Harvest Entry Form, Manage Inventory Screen,
--         Harvest History Screen, Harvest Hub stats
--
-- New tables: harvest_records, inventory_batches
-- Depends on: farmer_crops (crop_id FK)
--
-- NOTE: photo_url removed from harvest_records.
--       Crop photos live in farmer_crops.photo_url instead.
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: harvest_records
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.harvest_records (
  id                       UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id                UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  crop_id                  UUID          NOT NULL REFERENCES public.farmer_crops(id) ON DELETE CASCADE,
  crop_name                TEXT          NOT NULL,
  crop_category            TEXT          NOT NULL DEFAULT 'Other',
  quantity_kg              DECIMAL(10,2) NOT NULL CHECK (quantity_kg > 0),
  quality_grade            TEXT          NOT NULL DEFAULT 'Grade A'
                           CHECK (quality_grade IN ('Grade A', 'Grade B', 'Grade C')),
  variety                  TEXT,
  batch_number             TEXT          NOT NULL UNIQUE,
  harvest_date             DATE          NOT NULL,
  storage_location         TEXT,
  notes                    TEXT,
  submitted_to_cooperative BOOLEAN       NOT NULL DEFAULT FALSE,
  is_synced                BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_harvest_records_updated_at
  BEFORE UPDATE ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_harvest_records_farmer_date
  ON public.harvest_records (farmer_id, harvest_date DESC);

CREATE INDEX IF NOT EXISTS idx_harvest_records_crop
  ON public.harvest_records (crop_id, created_at DESC);

ALTER TABLE public.harvest_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "harvest_records: farmer manages own"
  ON public.harvest_records FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "harvest_records: admin reads all"
  ON public.harvest_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: inventory_batches
-- Auto-created on harvest submission.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_batches (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id         UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  harvest_record_id UUID          NOT NULL REFERENCES public.harvest_records(id) ON DELETE CASCADE,
  crop_id           UUID          NOT NULL REFERENCES public.farmer_crops(id) ON DELETE CASCADE,
  crop_name         TEXT          NOT NULL,
  batch_number      TEXT          NOT NULL UNIQUE,
  quantity_kg       DECIMAL(10,2) NOT NULL CHECK (quantity_kg > 0),
  available_kg      DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (available_kg >= 0),
  reserved_kg       DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (reserved_kg >= 0),
  sold_kg           DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (sold_kg >= 0),
  quality_grade     TEXT          NOT NULL DEFAULT 'Grade A',
  status            TEXT          NOT NULL DEFAULT 'available'
                    CHECK (status IN ('available', 'reserved', 'sold_out', 'withdrawn', 'low_stock')),
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_inventory_batches_updated_at
  BEFORE UPDATE ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_inventory_batches_farmer
  ON public.inventory_batches (farmer_id, status, created_at DESC);

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_batches: farmer manages own"
  ON public.inventory_batches FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "inventory_batches: admin reads all"
  ON public.inventory_batches FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

CREATE POLICY "inventory_batches: buyers read available"
  ON public.inventory_batches FOR SELECT
  USING (status = 'available' AND auth.role() = 'authenticated');
