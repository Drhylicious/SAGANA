-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_price_records_migration.sql
-- Adds source/reference document column to price_records.
-- Run in Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE price_records
  ADD COLUMN IF NOT EXISTS source TEXT;

-- Index for fast crop+type lookups (used by fetchLatestPricePerCrop)
CREATE INDEX IF NOT EXISTS price_records_crop_type_idx
  ON price_records(crop_name, price_type, recorded_at DESC);

-- RLS: Admin can INSERT/UPDATE/DELETE price records
-- Farmers/buyers can only SELECT (already covered by existing policies)
-- Add admin write policy if not already present:

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'price_records'
      AND policyname = 'Admin full access to price_records'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Admin full access to price_records"
        ON price_records FOR ALL
        USING (
          EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
        )
        WITH CHECK (
          EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
        )
    $policy$;
  END IF;
END;
$$;
