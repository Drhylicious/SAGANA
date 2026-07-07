-- ============================================================
-- SAGANA — Dashboard Schema
-- Covers: Farmer Dashboard (price ticker, KPI data)
--
-- New table: price_records
-- Tables already exist (from auth schema):
--   user_roles, user_information, farmer_profiles
--
-- harvest_records, orders, farmer_loans are referenced by
-- the dashboard repository but created in later screen schemas.
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: price_records
-- Admin-entered market prices per crop.
-- No public DA-PMS API exists — admin enters prices manually.
-- price_type:
--   'sp3_cooperative' — price SP3 pays farmers for Palay/Peanut
--   'da_amad_market'  — DA-AMAD reference price (Ginger)
--   'open_market'     — general market reference (Banana, Copra, others)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.price_records (
  id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  crop_name      TEXT        NOT NULL,
  price          DECIMAL(10,2) NOT NULL CHECK (price > 0),
  previous_price DECIMAL(10,2),
  unit           TEXT        NOT NULL DEFAULT 'kg',
  price_type     TEXT        NOT NULL DEFAULT 'open_market'
                 CHECK (price_type IN (
                   'sp3_cooperative',
                   'da_amad_market',
                   'open_market'
                 )),
  recorded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  recorded_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_price_records_updated_at
  BEFORE UPDATE ON public.price_records
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- Index for fast latest-per-crop query
CREATE INDEX IF NOT EXISTS idx_price_records_crop_recorded
  ON public.price_records (crop_name, recorded_at DESC);

-- RLS
ALTER TABLE public.price_records ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read prices (farmers see ticker, buyers see price monitoring)
CREATE POLICY "price_records: authenticated users read"
  ON public.price_records FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only admins can insert/update prices
CREATE POLICY "price_records: admin inserts"
  ON public.price_records FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

CREATE POLICY "price_records: admin updates"
  ON public.price_records FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SEED DATA — Initial price records for testing
-- Replace with real SP3 prices before pilot
-- ─────────────────────────────────────────────────────────────────────────────

-- INSERT INTO public.price_records (crop_name, price, previous_price, unit, price_type)
-- VALUES
--   ('Palay',  18.00, 17.50, 'kg', 'sp3_cooperative'),
--   ('Peanut', 65.00, 62.00, 'kg', 'sp3_cooperative'),
--   ('Ginger', 55.00, 60.00, 'kg', 'da_amad_market'),
--   ('Banana', 18.50, 17.00, 'kg', 'open_market'),
--   ('Copra',  35.00, 35.00, 'kg', 'open_market');
