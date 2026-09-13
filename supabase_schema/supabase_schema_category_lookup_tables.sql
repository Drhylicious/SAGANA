-- ============================================================
-- SAGANA — Inventory & Crop Category Lookup Tables
-- (Admin Dashboard investigation — Category architecture revision)
--
-- Problem: inventory category (cooperative_inventory.category /
-- cooperative_programs.distribution_category) and crop category
-- (crop_master.category / farmer_crops.category) were both a hardcoded
-- Dart list (AppConstants.inventoryCategories / FarmerCropModel.categories)
-- backed by a DB CHECK constraint enum. Adding a category required a code
-- change + a migration + an app release — the cooperative's own staff
-- could never do it after handover. The two vocabularies had also already
-- drifted out of sync once (loan_items_master.category was missing
-- 'Harvest Stock' and 'Livestock').
--
-- Fix: two admin-managed lookup tables, mirroring crop_master's own
-- existing pattern exactly (id/name/is_active/sort_order/created_by +
-- "admin manages all" / "authenticated reads active" RLS). Every category
-- dropdown now reads its option list from here instead of a Dart constant,
-- and an admin can add a new one inline from the dropdown itself.
--
-- Consuming tables keep storing the category as plain TEXT exactly as
-- before (cooperative_inventory.category, cooperative_programs
-- .distribution_category, crop_master.category, farmer_crops.category,
-- loan_items_master.category) — only the set of allowed values moves from
-- a hardcoded CHECK constraint to rows in these two tables. Every existing
-- read/filter/report (e.g. cooperative_stock_report_screen.dart, which
-- groups cooperative_inventory by raw category text) keeps working
-- untouched.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.inventory_categories (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL UNIQUE,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_inventory_categories_updated_at
  BEFORE UPDATE ON public.inventory_categories
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.inventory_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_categories: admin manages all"
  ON public.inventory_categories FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "inventory_categories: authenticated reads active"
  ON public.inventory_categories FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- Seed with the categories already hardcoded in AppConstants.inventoryCategories
INSERT INTO public.inventory_categories (name, sort_order) VALUES
  ('Fertilizer', 1),
  ('Seeds', 2),
  ('Animal Feeds', 3),
  ('Pesticide', 4),
  ('Tools & Equipment', 5),
  ('Agricultural Supplies', 6),
  ('Harvest Stock', 7),
  ('Livestock', 8)
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.crop_categories (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL UNIQUE,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_crop_categories_updated_at
  BEFORE UPDATE ON public.crop_categories
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.crop_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "crop_categories: admin manages all"
  ON public.crop_categories FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "crop_categories: authenticated reads active"
  ON public.crop_categories FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- Seed with the categories already hardcoded in FarmerCropModel.categories.
-- 'Other' is deliberately excluded — with categories now admin-manageable
-- at runtime, a catch-all no longer serves a purpose and would just
-- invite every not-yet-categorized crop to pile up under it instead of
-- getting its own real category.
INSERT INTO public.crop_categories (name, sort_order) VALUES
  ('Grain', 1),
  ('Legume', 2),
  ('Root & Spice Crop', 3),
  ('Fruit', 4),
  ('Tree Crop', 5),
  ('Vegetable', 6)
ON CONFLICT (name) DO NOTHING;

-- Idempotent cleanup in case this migration already ran once with 'Other'
-- seeded before this decision — removes it as a selectable option going
-- forward. Existing crop_master/farmer_crops rows already stored as
-- 'Other' are untouched (they're plain text, not FK'd to this table).
DELETE FROM public.crop_categories WHERE name = 'Other';

-- Drop the old hardcoded CHECK constraints so a category added at runtime
-- to inventory_categories / crop_categories isn't rejected by a stale
-- enum. Found dynamically by column rather than by guessed constraint
-- name — this exact column has already been re-constrained multiple times
-- in this codebase (cooperative_inventory_category_check ->
-- _check2, cooperative_programs_distribution_category_check2 -> _check3;
-- see supabase_schema_livestock_inventory_category.sql), so hardcoding a
-- name here would likely go stale again.
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
      AND con.conrelid = ANY(ARRAY[
        'public.cooperative_inventory'::regclass,
        'public.cooperative_programs'::regclass,
        'public.loan_items_master'::regclass,
        'public.crop_master'::regclass,
        'public.farmer_crops'::regclass
      ])
      AND att.attname IN ('category', 'distribution_category')
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.tbl, r.conname);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
