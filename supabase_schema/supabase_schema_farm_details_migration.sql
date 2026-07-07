-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_farm_details_migration.sql
-- Migration: Add extended farm profile fields to farmer_profiles
-- Run after supabase_schema_auth.sql
-- ─────────────────────────────────────────────────────────────────────────────

-- Coordinates for interactive map pin
ALTER TABLE farmer_profiles
  ADD COLUMN IF NOT EXISTS farm_latitude   DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS farm_longitude  DOUBLE PRECISION;

-- Human-readable address (separate from coordinates)
ALTER TABLE farmer_profiles
  ADD COLUMN IF NOT EXISTS farm_address    TEXT;

-- Agricultural characteristics
ALTER TABLE farmer_profiles
  ADD COLUMN IF NOT EXISTS farm_ownership_type  TEXT
    CHECK (farm_ownership_type IN ('owned', 'leased', 'communal')),
  ADD COLUMN IF NOT EXISTS soil_type            TEXT
    CHECK (soil_type IN ('sandy', 'clay', 'loam', 'volcanic', 'mixed')),
  ADD COLUMN IF NOT EXISTS water_source         TEXT
    CHECK (water_source IN ('rain_fed', 'irrigated', 'well', 'river', 'mixed'));

-- Index for future geo-queries (admin supply chain map)
CREATE INDEX IF NOT EXISTS farmer_profiles_coords_idx
  ON farmer_profiles(farm_latitude, farm_longitude)
  WHERE farm_latitude IS NOT NULL AND farm_longitude IS NOT NULL;

-- Note: primary_crops are NOT stored here.
-- They are derived from farmer_crops table (crop_name per farmer_id).
-- This keeps the data source of truth in one place.
