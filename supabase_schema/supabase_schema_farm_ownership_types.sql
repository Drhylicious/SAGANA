-- ============================================================
-- SAGANA — Farm Ownership Type Lookup Table
-- (Farmer Profile tab investigation — Edit Farm Details revision)
--
-- Problem: farm_ownership_type was a hardcoded Dart list
-- (_ownershipOptions in edit_farm_details_screen.dart) backed by a DB
-- CHECK constraint enum ('owned'/'leased'/'communal'), with a fourth,
-- independent copy of the same three labels in
-- FarmerProfileModel.ownershipLabel. Adding or renaming an option required
-- a code change + a migration + an app release.
--
-- Fix: one admin-managed lookup table, mirroring inventory_categories'
-- / crop_categories' existing pattern exactly (see
-- supabase_schema_category_lookup_tables.sql) — id/name/is_active/
-- sort_order/created_by + "admin manages all" / "authenticated reads
-- active" RLS. Unlike those two tables, this one has no farmer-facing
-- "add new" affordance (land ownership is a fixed taxonomy Admin should
-- control, not a free-text farmer label) — only fetchOwnershipTypes() is
-- exposed to the app for now.
--
-- farmer_profiles.farm_ownership_type keeps storing plain TEXT exactly as
-- before, but now stores the human-readable name directly (e.g. 'Owned'),
-- matching how cooperative_inventory.category already stores
-- inventory_categories.name verbatim — no separate code/label split.
-- Existing rows are migrated from the old lowercase codes below.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.farm_ownership_types (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL UNIQUE,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_farm_ownership_types_updated_at
  BEFORE UPDATE ON public.farm_ownership_types
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.farm_ownership_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farm_ownership_types: admin manages all"
  ON public.farm_ownership_types FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "farm_ownership_types: authenticated reads active"
  ON public.farm_ownership_types FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

INSERT INTO public.farm_ownership_types (name, sort_order) VALUES
  ('Owned', 1),
  ('Leased', 2),
  ('Communal / Shared', 3)
ON CONFLICT (name) DO NOTHING;

-- Migrate existing farmer_profiles rows from the old lowercase codes to
-- the new human-readable names before dropping the old CHECK constraint.
UPDATE public.farmer_profiles
SET farm_ownership_type = CASE farm_ownership_type
  WHEN 'owned'    THEN 'Owned'
  WHEN 'leased'   THEN 'Leased'
  WHEN 'communal' THEN 'Communal / Shared'
  ELSE farm_ownership_type
END
WHERE farm_ownership_type IN ('owned', 'leased', 'communal');

-- Drop the old hardcoded CHECK constraint so a value added at runtime to
-- farm_ownership_types isn't rejected by a stale enum. Found dynamically
-- by column rather than by guessed constraint name, matching the same
-- pattern used in supabase_schema_category_lookup_tables.sql.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname, con.conrelid::regclass::text AS tbl
    FROM pg_constraint con
    JOIN pg_attribute att
      ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.contype = 'c'
      AND con.conrelid = 'public.farmer_profiles'::regclass
      AND att.attname = 'farm_ownership_type'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.tbl, r.conname);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
