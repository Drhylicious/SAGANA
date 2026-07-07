-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_market_linking.sql
-- Tracks individual farmer participation in the DA-AMAD Ginger Market
-- Linking Program. Each row = one farmer's enrollment in the program
-- for a given season/year.
-- Run in Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS market_linking_programs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  crop_name       TEXT NOT NULL DEFAULT 'Ginger',
  season_year     INT  NOT NULL DEFAULT EXTRACT(YEAR FROM NOW()),
  status          TEXT NOT NULL DEFAULT 'submitted'
                    CHECK (status IN (
                      'submitted',    -- Farmer enrolled, awaiting buyer match
                      'buyer_found',  -- DA-AMAD buyer identified
                      'completed',    -- Sale confirmed and completed
                      'cancelled'     -- Removed from program
                    )),
  buyer_name      TEXT,              -- DA-AMAD buyer name when matched
  buyer_contact   TEXT,              -- Buyer contact info
  volume_kg       NUMERIC(10,2),     -- Committed volume for the program
  price_per_kg    NUMERIC(10,2),     -- Agreed price (set when buyer_found)
  notes           TEXT,              -- Admin notes / reason for cancellation
  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  buyer_found_at  TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_market_linking_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS market_linking_updated_at ON market_linking_programs;
CREATE TRIGGER market_linking_updated_at
  BEFORE UPDATE ON market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION update_market_linking_timestamp();

-- Indexes
CREATE INDEX IF NOT EXISTS market_linking_farmer_idx
  ON market_linking_programs(farmer_id);
CREATE INDEX IF NOT EXISTS market_linking_status_idx
  ON market_linking_programs(status);
CREATE INDEX IF NOT EXISTS market_linking_year_idx
  ON market_linking_programs(season_year DESC);

-- RLS
ALTER TABLE market_linking_programs ENABLE ROW LEVEL SECURITY;

-- Admin: full access
CREATE POLICY "Admin full access to market_linking_programs"
  ON market_linking_programs FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
  );

-- Farmers: read their own record
CREATE POLICY "Farmers read own market linking record"
  ON market_linking_programs FOR SELECT
  USING (auth.uid() = farmer_id);